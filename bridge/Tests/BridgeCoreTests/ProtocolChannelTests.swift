import Foundation
import Testing

@testable import BridgeCore

@Suite("One request in, one terminal response out")
struct ProtocolChannelTests {
  private func receiving(_ json: String) throws -> ProtocolChannel.ReceivedRequest {
    let harness = WireHarness()
    try harness.writeAndClose(WireHarness.framed(Data(json.utf8)))
    return try harness.channel.receiveRequest()
  }

  @Test("A valid request is handed back to be acted on")
  func validRequest() throws {
    let received = try receiving(
      #"{"version":1,"url":"https://login.microsoftonline.com/x","method":"GET"}"#
    )
    #expect(received == .request(.get(url: URL(string: "https://login.microsoftonline.com/x")!)))
  }

  @Test("A version the Bridge does not implement answers unsupported_version")
  func unsupportedVersion() throws {
    let received = try receiving(#"{"version":2,"url":"https://login.microsoftonline.com/x"}"#)
    #expect(
      received == .answer(.error(.unsupportedVersion(bridgeVersion: 1), detail: nil))
    )
  }

  // Decided before the rest of the schema is read, because a version the Bridge does
  // not implement is free to spell everything else differently.
  @Test("The version is judged before the schema is")
  func versionBeatsSchema() throws {
    let received = try receiving(#"{"version":99,"nothing":"else is valid here"}"#)
    #expect(received == .answer(.error(.unsupportedVersion(bridgeVersion: 1), detail: nil)))
  }

  @Test(
    "A whole frame that is not a valid request answers malformed_request",
    arguments: [
      "not json at all",
      #"{"url":"https://login.microsoftonline.com/x","method":"GET"}"#,
      #"{"version":"1","url":"https://login.microsoftonline.com/x","method":"GET"}"#,
      #"{"version":1,"url":"https://login.microsoftonline.com/x","method":"TRACE"}"#,
      #"{"version":1,"url":"javascript:alert(1)","method":"GET"}"#,
    ]
  )
  func malformedRequest(json: String) throws {
    guard case .answer(.error(let code, _)) = try receiving(json) else {
      Issue.record("expected a terminal answer")
      return
    }
    #expect(code == .malformedRequest)
  }

  @Test("The terminal response goes out as one frame")
  func sendsOneFrame() throws {
    let harness = WireHarness()
    try harness.channel.send(.declined)
    let written = try harness.written()
    #expect(written == WireHarness.framed(Data(#"{"result":"declined"}"#.utf8)))
  }

  // One process, one Handoff. Several termination paths converge on `send`, and two
  // frames on the wire would be a second Handoff the Extension never asked for.
  @Test("A second terminal response is suppressed")
  func onlyOneResponse() throws {
    let harness = WireHarness()
    try harness.channel.send(.declined)
    try harness.channel.send(.error(.internalFailure, detail: "second"))
    let written = try harness.written()
    #expect(written == WireHarness.framed(Data(#"{"result":"declined"}"#.utf8)))
  }

  @Test("Broken framing leaves stdout empty")
  func brokenFramingWritesNothing() throws {
    let harness = WireHarness()
    try harness.writeAndClose(Data([0x05, 0x00, 0x00]))
    #expect(throws: FramingError.truncatedLengthPrefix(bytesRead: 3)) {
      try harness.channel.receiveRequest()
    }
    #expect(try harness.written().isEmpty)
  }
}

@Suite("Logging carries nothing the spec forbids")
struct LogSummaryTests {
  @Test("A Sign-in request is named by method and host only")
  func signInRequestSummary() {
    let url = URL(string: "https://login.microsoftonline.com/tenant/saml2?secret=value")!
    let request = SignInRequest.post(
      url: url,
      fields: [FormField(name: "SAMLRequest", value: "an-assertion")]
    )
    #expect(request.logSummary == "POST login.microsoftonline.com")
  }

  @Test("A response is named by outcome and host only")
  func responseSummary() {
    let url = URL(string: "https://app.example.com/sso/acs?code=secret")!
    let callback = BridgeResponse.callback(
      .post(url: url, fields: [FormField(name: "SAMLResponse", value: "an-assertion")])
    )
    #expect(callback.logSummary == "callback POST app.example.com")
    #expect(BridgeResponse.declined.logSummary == "declined")
    #expect(BridgeResponse.error(.internalFailure, detail: "x").logSummary == "error internal")
  }
}
