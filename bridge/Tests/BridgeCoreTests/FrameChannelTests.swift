import Foundation
import Testing

@testable import BridgeCore

@Suite("Framing over a real Pipe")
struct FrameChannelTests {
  private let payload = Data(#"{"version":1}"#.utf8)

  @Test("A whole frame round-trips")
  func roundTrip() throws {
    let harness = WireHarness()
    try harness.writeAndClose(WireHarness.framed(payload))
    #expect(try harness.frames.readFrame() == payload)
  }

  @Test("A frame arriving in pieces is reassembled")
  func splitFrame() throws {
    let harness = WireHarness()
    let frame = WireHarness.framed(payload)
    // A prefix split down the middle, then a body split again, is what a short read
    // looks like from the reader's side.
    harness.writeInPieces(frame, pieces: [2, 3, 5])
    #expect(try harness.frames.readFrame() == payload)
  }

  @Test("A frame the Bridge writes is the frame the Bridge reads")
  func writeThenRead() throws {
    let harness = WireHarness()
    try harness.frames.writeFrame(payload)
    #expect(try harness.written() == WireHarness.framed(payload))
  }

  @Test("The length prefix is this machine's byte order, not a guess")
  func nativeByteOrder() throws {
    let harness = WireHarness()
    try harness.frames.writeFrame(payload)
    let prefix = try harness.written().prefix(4)
    #expect(prefix == withUnsafeBytes(of: UInt32(payload.count)) { Data($0) })
  }

  @Test("Input that ends on a frame boundary is the end of input")
  func endOfInput() throws {
    let harness = WireHarness()
    try harness.closeInput()
    #expect(throws: FramingError.endOfInput) { try harness.frames.readFrame() }
    #expect(try harness.written().isEmpty)
  }

  @Test("Input that ends inside the length prefix is broken framing")
  func truncatedPrefix() throws {
    let harness = WireHarness()
    try harness.writeAndClose(Data([0x01, 0x00]))
    #expect(throws: FramingError.truncatedLengthPrefix(bytesRead: 2)) {
      try harness.frames.readFrame()
    }
    #expect(try harness.written().isEmpty)
  }

  @Test("Input that ends inside the body is broken framing")
  func truncatedBody() throws {
    let harness = WireHarness()
    var frame = WireHarness.framed(payload)
    frame.removeLast(4)
    try harness.writeAndClose(frame)
    #expect(
      throws: FramingError.truncatedBody(expected: payload.count, received: payload.count - 4)
    ) {
      try harness.frames.readFrame()
    }
    #expect(try harness.written().isEmpty)
  }

  @Test("An absurd length prefix is refused before anything is allocated")
  func absurdLength() throws {
    let harness = WireHarness()
    try harness.writeAndClose(Data([0xff, 0xff, 0xff, 0xff]))
    #expect(throws: FramingError.frameTooLarge(length: 0xffff_ffff)) {
      try harness.frames.readFrame()
    }
    #expect(try harness.written().isEmpty)
  }
}
