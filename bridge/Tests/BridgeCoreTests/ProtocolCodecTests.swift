import Foundation
import Testing

@testable import BridgeCore

@Suite("Request decoding")
struct RequestDecodingTests {
  private func decode(_ json: String) throws -> RequestMessage {
    try JSONDecoder().decode(RequestMessage.self, from: Data(json.utf8))
  }

  @Test("The GET fixture the Extension sends")
  func getFixture() throws {
    let message = try JSONDecoder().decode(
      RequestMessage.self,
      from: Fixtures.data("request-get.json")
    )
    #expect(message.version == 1)
    #expect(message.signInRequest.method == .get)
    #expect(message.signInRequest.url.host() == "login.microsoftonline.com")
  }

  @Test("A POST keeps every field, including a repeated name, in order")
  func postFixture() throws {
    let message = try JSONDecoder().decode(
      RequestMessage.self,
      from: Fixtures.data("request-post.json")
    )
    guard case .post(_, let fields) = message.signInRequest else {
      Issue.record("expected a POST Sign-in request")
      return
    }
    #expect(fields.map(\.name) == ["SAMLRequest", "RelayState", "RelayState"])
    #expect(fields[1].value == "https://app.example.com/sso/start")
    #expect(fields[2].value == "second-value-under-the-same-name")
  }

  @Test("A POST with no fields decodes to none rather than failing")
  func postWithoutFields() throws {
    let message = try decode(
      #"{"version":1,"url":"https://login.microsoftonline.com/x","method":"POST"}"#)
    #expect(
      message.signInRequest
        == .post(url: URL(string: "https://login.microsoftonline.com/x")!, fields: []))
  }

  @Test(
    "Anything that is not a valid version 1 request is refused",
    arguments: [
      #"{"version":1,"method":"GET"}"#,
      #"{"version":1,"url":"https://login.microsoftonline.com/x"}"#,
      #"{"version":1,"url":"/relative","method":"GET"}"#,
      #"{"version":1,"url":"not a url at all","method":"GET"}"#,
      #"{"version":1,"url":"https://login.microsoftonline.com/x","method":"PUT"}"#,
      #"{"version":1,"url":"https://login.microsoftonline.com/x","method":"get"}"#,
      #"{"version":1,"url":"https://login.microsoftonline.com/x","method":"GET","fields":[["a","b"]]}"#,
      #"{"version":1,"url":"https://login.microsoftonline.com/x","method":"POST","fields":[["a"]]}"#,
      #"{"version":1,"url":"https://login.microsoftonline.com/x","method":"POST","fields":{"a":"b"}}"#,
    ]
  )
  func invalidRequests(json: String) {
    #expect(throws: (any Error).self) { try decode(json) }
  }
}

@Suite("Response encoding")
struct ResponseEncodingTests {
  private func encoded(_ response: BridgeResponse) throws -> NSDictionary {
    try NSDictionary.parsing(ResponseEncoder.encode(response).payload)
  }

  @Test("A GET Callback")
  func callbackGet() throws {
    let url = URL(string: "https://app.example.com/sso/callback?code=0.AXkAo1&state=abc123")!
    #expect(try encoded(.callback(.get(url: url))) == Fixtures.object("response-callback-get.json"))
  }

  @Test("A POST Callback carries its fields as [name, value] pairs")
  func callbackPost() throws {
    let response = BridgeResponse.callback(
      .post(
        url: URL(string: "https://app.example.com/sso/acs")!,
        fields: [
          FormField(
            name: "SAMLResponse",
            value: "PHNhbWxwOlJlc3BvbnNlIHhtbG5zOnNhbWxwPSJ1cm46b2FzaXM6"
          ),
          FormField(name: "RelayState", value: "https://app.example.com/sso/start"),
        ]
      )
    )
    #expect(try encoded(response) == Fixtures.object("response-callback-post.json"))
  }

  @Test("Declined carries nothing else")
  func declined() throws {
    #expect(try encoded(.declined) == Fixtures.object("response-declined.json"))
  }

  @Test("An error carries its code and detail")
  func error() throws {
    let response = BridgeResponse.error(.navigationFailed, detail: "NSURLErrorDomain -1003")
    #expect(try encoded(response) == Fixtures.object("response-error.json"))
  }

  @Test("unsupported_version carries the version the Bridge implements")
  func unsupportedVersion() throws {
    let response = BridgeResponse.error(.unsupportedVersion(bridgeVersion: 1), detail: nil)
    #expect(try encoded(response) == Fixtures.object("response-unsupported-version.json"))
  }

  @Test("A Callback inside the budget is sent as it is")
  func withinBudget() throws {
    let response = callback(withValueOf: ResponseEncoder.budget / 2)
    let (sent, payload) = try ResponseEncoder.encode(response)
    #expect(sent == response)
    #expect(payload.count <= ResponseEncoder.budget)
  }

  // A frame over the cap is closed by the port with an IO error in Chromium and
  // throws in Gecko, and either way the Extension sees a bare disconnect that reads
  // exactly like a crash. A coded error is the only useful thing to send instead.
  @Test("A Callback over the budget becomes callback_too_large")
  func overBudget() throws {
    let (sent, payload) = try ResponseEncoder.encode(callback(withValueOf: ResponseEncoder.budget))
    guard case .error(let code, _) = sent else {
      Issue.record("expected an error response")
      return
    }
    #expect(code == .callbackTooLarge)
    #expect(payload.count < ResponseEncoder.budget)
  }

  private func callback(withValueOf length: Int) -> BridgeResponse {
    .callback(
      .post(
        url: URL(string: "https://app.example.com/sso/acs")!,
        fields: [FormField(name: "SAMLResponse", value: String(repeating: "A", count: length))]
      )
    )
  }
}
