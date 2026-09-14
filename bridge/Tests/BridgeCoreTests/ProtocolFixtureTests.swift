import Foundation
import Testing

@testable import BridgeCore

/// The one place the two hand-written halves of the schema meet as bytes.
///
/// `request-post-frame.le.hex` is produced by the Extension's suite, framing included,
/// so what is decoded here is what a browser puts on the pipe rather than what this
/// side believes a browser puts on the pipe.
@Suite("A frame the Extension produced")
struct ProtocolFixtureTests {
  @Test(
    "decodes to the Sign-in request the fixture describes",
    .enabled(if: UInt32(littleEndian: 1) == 1, "the length prefix is native-endian")
  )
  func decodesTheExtensionsFrame() throws {
    let harness = WireHarness()
    try harness.writeAndClose(try Hex.data(Fixtures.text("request-post-frame.le.hex")))

    let received = try harness.channel.receiveRequest()
    guard case .request(.post(let url, let fields)) = received else {
      Issue.record("expected a POST Sign-in request")
      return
    }
    let described = try Fixtures.object("request-post.json")["url"] as? String
    #expect(url.absoluteString == described)
    #expect(fields.map(\.name) == ["SAMLRequest", "RelayState", "RelayState"])
    #expect(try harness.written().isEmpty)
  }
}
