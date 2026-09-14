import Foundation

@testable import BridgeCore

/// A `FrameChannel` over a real `Pipe` pair, which is the same code path the
/// executable feeds from stdin. Nothing here bypasses caller authentication, because
/// nothing here is the executable.
final class WireHarness {
  private let toBridge = Pipe()
  private let fromBridge = Pipe()

  let frames: FrameChannel
  let channel: ProtocolChannel

  init() {
    frames = FrameChannel(
      input: toBridge.fileHandleForReading,
      output: fromBridge.fileHandleForWriting
    )
    channel = ProtocolChannel(frames: frames)
  }

  /// A length prefix in this machine's byte order, built here rather than borrowed
  /// from `FrameChannel`, so the two agree only if both are right.
  static func framed(_ payload: Data) -> Data {
    var frame = withUnsafeBytes(of: UInt32(payload.count)) { Data($0) }
    frame.append(payload)
    return frame
  }

  func write(_ bytes: Data) throws {
    try toBridge.fileHandleForWriting.write(contentsOf: bytes)
  }

  func closeInput() throws {
    try toBridge.fileHandleForWriting.close()
  }

  /// Writes the bytes, then closes the writing end so a reader waiting on more input
  /// sees the end of the stream instead of blocking.
  func writeAndClose(_ bytes: Data) throws {
    try write(bytes)
    try closeInput()
  }

  /// Delivers the bytes in pieces from another thread, so the reader genuinely has to
  /// survive short reads rather than finding a fully buffered pipe.
  func writeInPieces(_ bytes: Data, pieces: [Int]) {
    let handle = toBridge.fileHandleForWriting
    Thread.detachNewThread {
      var offset = 0
      for piece in pieces {
        let end = min(offset + piece, bytes.count)
        try? handle.write(contentsOf: bytes[offset..<end])
        offset = end
        Thread.sleep(forTimeInterval: 0.02)
      }
      if offset < bytes.count {
        try? handle.write(contentsOf: bytes[offset...])
      }
      try? handle.close()
    }
  }

  /// Everything the Bridge put on its output, read to the end.
  func written() throws -> Data {
    try fromBridge.fileHandleForWriting.close()
    return try fromBridge.fileHandleForReading.readToEnd() ?? Data()
  }
}
