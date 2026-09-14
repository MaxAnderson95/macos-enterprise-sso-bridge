import Foundation

/// Framing broke badly enough that there is nothing worth writing a response to.
///
/// Every case means the same thing to the caller: log it and exit non-zero without
/// writing to stdout. They are separate cases so the log line can say which one it
/// was, which is the only diagnostic a developer gets when a browser spawns the
/// Bridge and nothing appears.
public enum FramingError: Error, Equatable {
  /// The input ended cleanly, on a frame boundary, without a frame.
  case endOfInput
  /// The input ended part-way through the four-byte length prefix.
  case truncatedLengthPrefix(bytesRead: Int)
  /// The length prefix promised more body than the input had.
  case truncatedBody(expected: Int, received: Int)
  /// The length prefix names a frame larger than the Bridge will allocate for.
  case frameTooLarge(length: UInt32)
}

/// The length-prefixed framing both engines already speak: a 32-bit native-endian
/// length followed by that many bytes of UTF-8 JSON.
///
/// This is the seam the wire format is tested through. The executable builds one over
/// the real stdin and stdout; the tests build one over a `Pipe` pair, and it is the
/// same code path either way, so nothing that skips caller authentication has to be
/// compiled to exercise the format.
public struct FrameChannel {
  /// The largest inbound frame the Bridge will allocate for.
  ///
  /// Browser-to-host is effectively unbounded in both engines, so this is not a
  /// protocol limit: it is what stops a bogus length prefix from turning into a
  /// multi-gigabyte allocation. It is set to the host-to-browser cap for symmetry,
  /// which leaves roughly two orders of magnitude of headroom over a real Sign-in
  /// request carrying a deflated SAMLRequest.
  public static let maximumFrameSize = 1_024 * 1_024

  private let input: FileHandle
  private let output: FileHandle

  public init(input: FileHandle, output: FileHandle) {
    self.input = input
    self.output = output
  }

  public static func standardIO() -> FrameChannel {
    FrameChannel(input: .standardInput, output: .standardOutput)
  }

  /// Reads exactly one frame, blocking until it arrives.
  public func readFrame() throws -> Data {
    let prefix = try read(exactly: 4)
    guard prefix.count == 4 else {
      throw prefix.isEmpty
        ? FramingError.endOfInput : .truncatedLengthPrefix(bytesRead: prefix.count)
    }

    // Native byte order by construction: the bytes are loaded as a `UInt32` without
    // being told an order, which is what both engines write on this machine.
    let length = prefix.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    guard length <= UInt32(Self.maximumFrameSize) else {
      throw FramingError.frameTooLarge(length: length)
    }

    let body = try read(exactly: Int(length))
    guard body.count == Int(length) else {
      throw FramingError.truncatedBody(expected: Int(length), received: body.count)
    }
    return body
  }

  public func writeFrame(_ payload: Data) throws {
    guard payload.count <= Self.maximumFrameSize else {
      throw FramingError.frameTooLarge(length: UInt32(clamping: payload.count))
    }
    var frame = withUnsafeBytes(of: UInt32(payload.count)) { Data($0) }
    frame.append(payload)
    try output.write(contentsOf: frame)
  }

  /// A pipe hands over whatever has arrived, so a frame split across writes reaches
  /// the reader as several short reads rather than one whole one.
  private func read(exactly count: Int) throws -> Data {
    var accumulated = Data()
    accumulated.reserveCapacity(count)
    while accumulated.count < count {
      guard let chunk = try input.read(upToCount: count - accumulated.count), !chunk.isEmpty else {
        break
      }
      accumulated.append(chunk)
    }
    return accumulated
  }
}
