import Foundation
import Testing

@testable import BridgeCore

@Suite("Planning a Handoff")
struct EntraPlanTests {
  /// One Sign-in request and what the adapter should be able to say about it. A nil
  /// `destination` in a case that is still replayable is the difference that matters:
  /// the Approval says so plainly rather than guessing.
  struct PlanCase: Sendable, CustomTestStringConvertible {
    let name: String
    let request: SignInRequest
    let replayable: Bool
    let destination: String?

    var testDescription: String { name }
  }

  static let entra = "https://login.microsoftonline.com"

  static func get(_ url: String) -> SignInRequest {
    .get(url: URL(string: url)!)
  }

  static func post(_ url: String, _ fields: [(String, String)]) -> SignInRequest {
    .post(url: URL(string: url)!, fields: fields.map(FormField.init(name:value:)))
  }

  @Test("What the adapter can say about a Sign-in request", arguments: planCases)
  func planning(_ testCase: PlanCase) {
    let plan = EntraAdapter().plan(testCase.request)
    #expect((plan != nil) == testCase.replayable)
    #expect(plan?.destination?.absoluteString == testCase.destination)
  }

  static let planCases: [PlanCase] = [
    PlanCase(
      name: "OIDC authorize with a redirect_uri",
      request: get(
        "\(entra)/common/oauth2/v2.0/authorize?client_id=abc&response_type=code"
          + "&redirect_uri=https%3A%2F%2Fapp.example.com%2Fsignin-oidc&scope=openid"
      ),
      replayable: true,
      destination: "https://app.example.com/signin-oidc"
    ),
    PlanCase(
      name: "OIDC form_post, where the redirect_uri is still in the query",
      request: post(
        "\(entra)/common/oauth2/v2.0/authorize?response_mode=form_post"
          + "&redirect_uri=https%3A%2F%2Fapp.example.com%2Fsignin-oidc",
        [("state", "opaque")]
      ),
      replayable: true,
      destination: "https://app.example.com/signin-oidc"
    ),
    PlanCase(
      name: "SAML HTTP-POST binding, destination from the ACS URL",
      request: post(
        "\(entra)/common/saml2",
        [("SAMLRequest", SAMLFixtures.acsPostBinding), ("RelayState", "opaque")]
      ),
      replayable: true,
      destination: "https://app.example.com/sso/acs"
    ),
    PlanCase(
      name: "SAML HTTP-POST binding whose XML carries a UTF-8 byte-order mark",
      request: post(
        "\(entra)/common/saml2",
        [("SAMLRequest", SAMLFixtures.acsPostBindingWithBOM), ("RelayState", "opaque")]
      ),
      replayable: true,
      destination: "https://app.example.com/sso/acs"
    ),
    PlanCase(
      name: "SAML HTTP-Redirect binding, inflated to reach the ACS URL",
      request: get(
        "\(entra)/common/saml2?SAMLRequest="
          + SAMLFixtures.acsRedirectBinding.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics)!
      ),
      replayable: true,
      destination: "https://app.example.com/sso/acs"
    ),
    PlanCase(
      name: "SAML with no ACS URL falls back to the issuer",
      request: post("\(entra)/common/saml2", [("SAMLRequest", SAMLFixtures.issuerOnly)]),
      replayable: true,
      destination: "https://app.example.com/sso/metadata"
    ),
    PlanCase(
      name: "SAML whose issuer is a URN is replayable with no destination",
      request: post("\(entra)/common/saml2", [("SAMLRequest", SAMLFixtures.urnIssuer)]),
      replayable: true,
      destination: nil
    ),
    PlanCase(
      name: "SAMLRequest that decodes to nothing is replayable with no destination",
      request: post("\(entra)/common/saml2", [("SAMLRequest", "not-base64-at-all***")]),
      replayable: true,
      destination: nil
    ),
    PlanCase(
      name: "A relative redirect_uri is replayable with no destination",
      request: get("\(entra)/common/oauth2/v2.0/authorize?redirect_uri=%2Fsignin-oidc"),
      replayable: true,
      destination: nil
    ),
    PlanCase(
      name: "Neither a redirect_uri nor a SAMLRequest is not replayable",
      request: get("\(entra)/common/oauth2/v2.0/authorize?client_id=abc&scope=openid"),
      replayable: false,
      destination: nil
    ),
    PlanCase(
      name: "A POST carrying some other form is not replayable",
      request: post("\(entra)/common/login", [("username", "someone@example.com")]),
      replayable: false,
      destination: nil
    ),
  ]
}

@Suite("Selecting an adapter")
struct AdapterSelectionTests {
  private func request(_ url: String) -> SignInRequest {
    .get(url: URL(string: url)!)
  }

  private let replayable = "/authorize?redirect_uri=https%3A%2F%2Fa.example.com%2Fc"

  @Test(
    "An origin an adapter claims gets a plan",
    arguments: [
      "https://login.microsoftonline.com",
      "https://LOGIN.MICROSOFTONLINE.COM",
      "https://login.microsoftonline.com:443",
    ]
  )
  func claimedOrigins(_ origin: String) {
    #expect(IdentityProviders.plan(for: request(origin + replayable)) != nil)
  }

  /// The Extension is untrusted under ADR 0002, so its capture filter having let these
  /// through is not an argument for replaying them.
  @Test(
    "Anything else is unsupported_request, however replayable it looks",
    arguments: [
      "https://login.microsoftonline.com.evil.example",
      "https://evil.example",
      "http://login.microsoftonline.com",
      "https://login.microsoftonline.com:8443",
      "https://sub.login.microsoftonline.com",
    ]
  )
  func unclaimedOrigins(_ origin: String) {
    #expect(IdentityProviders.plan(for: request(origin + replayable)) == nil)
  }

  @Test("A claimed origin with nothing replayable is still no plan")
  func claimedButNotReplayable() {
    #expect(IdentityProviders.plan(for: request("https://login.microsoftonline.com/common")) == nil)
  }
}

/// The steps `main` takes between the frame and the answer, over a real `Pipe`.
///
/// Driving the shipped executable this way is impossible by construction: caller
/// authentication rejects a shell parent before a byte of stdin is read, which is what
/// `packaging/caller-authentication-negative-test.sh` asserts. So the wire behaviour is
/// established here, through the same framing code the executable feeds from stdin.
@Suite("Answering a Sign-in request with nothing replayable")
struct UnsupportedRequestTests {
  private func received(_ url: String) throws -> SignInRequest {
    let harness = WireHarness()
    let payload = Data(#"{"version":1,"url":"\#(url)","method":"GET"}"#.utf8)
    try harness.writeAndClose(WireHarness.framed(payload))
    guard case .request(let request) = try harness.channel.receiveRequest() else {
      throw UnexpectedAnswer()
    }
    return request
  }

  private struct UnexpectedAnswer: Error {}

  @Test("Nothing replayable becomes unsupported_request on the wire")
  func unsupportedRequest() throws {
    let harness = WireHarness()
    let request = try received("https://login.microsoftonline.com/common/login")
    #expect(IdentityProviders.plan(for: request) == nil)

    try harness.channel.send(.error(.unsupportedRequest, detail: nil))
    let object = try NSDictionary.parsing(harness.written().dropFirst(4))
    #expect(object["result"] as? String == "error")
    #expect(object["code"] as? String == "unsupported_request")
  }

  @Test("A replayable Sign-in request gets a plan instead")
  func replayable() throws {
    let request = try received(
      "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
        + "?redirect_uri=https%3A%2F%2Fapp.example.com%2Fsignin-oidc"
    )
    #expect(IdentityProviders.plan(for: request) != nil)
  }
}

@Suite("Reading a SAMLRequest")
struct SAMLAuthnRequestTests {
  /// Each fixture decodes back to the XML it was built from, so a case that leans on
  /// one is leaning on a real AuthnRequest.
  @Test(
    "Both of Entra's bindings decode to AuthnRequest XML",
    arguments: [
      SAMLFixtures.acsRedirectBinding,
      SAMLFixtures.acsPostBinding,
      SAMLFixtures.issuerOnly,
      SAMLFixtures.urnIssuer,
    ]
  )
  func decodes(_ encoded: String) throws {
    let xml = try #require(SAMLAuthnRequest.xml(fromEncoded: encoded))
    #expect(String(decoding: xml, as: UTF8.self).hasPrefix("<samlp:AuthnRequest"))
  }

  @Test("Padding a redirect binding stripped is restored")
  func stripsPadding() {
    let unpadded = SAMLFixtures.acsRedirectBinding.replacingOccurrences(of: "=", with: "")
    #expect(
      SAMLAuthnRequest.destination(fromEncoded: unpadded)?.absoluteString
        == "https://app.example.com/sso/acs"
    )
  }

  @Test(
    "Anything that is not a readable AuthnRequest has no destination",
    arguments: [
      "",
      "****",
      Data("<samlp:Response/>".utf8).base64EncodedString(),
      Data("not xml at all".utf8).base64EncodedString(),
    ]
  )
  func refusesJunk(_ encoded: String) {
    #expect(SAMLAuthnRequest.destination(fromEncoded: encoded) == nil)
  }
}
