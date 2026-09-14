import Foundation
import Testing

@testable import BridgeCore

/// The recognition rules, exercised as values. No `WKWebView`, no navigation delegate,
/// and no network: a candidate is a `(url, method, fields)` triple, which is the whole
/// point of the adapter seam.
@Suite("Recognizing a Callback")
struct CallbackRecognitionTests {
  struct RecognitionCase: Sendable, CustomTestStringConvertible {
    let name: String
    let url: String
    let method: HTTPMethod
    let fields: [(String, String)]
    let recognized: Bool

    var candidate: CandidateNavigation {
      CandidateNavigation(
        url: URL(string: url)!,
        method: method,
        fields: fields.map(FormField.init(name:value:))
      )
    }

    var testDescription: String { name }
  }

  /// The Sign-in request every case below is judged against: an OIDC authorize whose
  /// `redirect_uri` is `https://app.example.com/signin-oidc`.
  static let plan = EntraAdapter().plan(
    .get(
      url: URL(
        string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
          + "?client_id=abc&redirect_uri=https%3A%2F%2Fapp.example.com%2Fsignin-oidc"
      )!
    )
  )!

  @Test("Which navigations the adapter calls the Callback", arguments: recognitionCases)
  func recognition(_ testCase: RecognitionCase) {
    #expect(Self.plan.recognizes(testCase.candidate) == testCase.recognized)
  }

  /// An encoded slash belongs to one path segment and a literal slash separates two, so
  /// an Application can route them to different resources. Treating them as the same
  /// place would let whichever came first end the Handoff.
  @Test("An encoded slash in the redirect_uri path is not a separator")
  func encodedSlashIsNotASeparator() throws {
    let plan = try #require(
      EntraAdapter().plan(
        .get(
          url: URL(
            string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
              + "?client_id=abc&redirect_uri=https%3A%2F%2Fapp.example.com%2Fcallback%2Fa%252Fb"
          )!
        )
      )
    )
    let candidate = { (url: String) in
      CandidateNavigation(url: URL(string: url)!, method: .get, fields: [])
    }
    #expect(plan.recognizes(candidate("https://app.example.com/callback/a%2Fb")))
    #expect(!plan.recognizes(candidate("https://app.example.com/callback/a/b")))
  }

  static let recognitionCases: [RecognitionCase] = [
    RecognitionCase(
      name: "the redirect_uri itself",
      url: "https://app.example.com/signin-oidc",
      method: .get,
      fields: [],
      recognized: true
    ),
    RecognitionCase(
      name: "the redirect_uri carrying a code, which the query is not matched on",
      url: "https://app.example.com/signin-oidc?code=0.Ac8&session_state=x",
      method: .get,
      fields: [],
      recognized: true
    ),
    RecognitionCase(
      name: "the redirect_uri written with its default port",
      url: "https://app.example.com:443/signin-oidc",
      method: .get,
      fields: [],
      recognized: true
    ),
    RecognitionCase(
      name: "another path on the same host is not the redirect_uri",
      url: "https://app.example.com/signin-saml",
      method: .get,
      fields: [],
      recognized: false
    ),
    RecognitionCase(
      name: "another port on the same host is not the redirect_uri",
      url: "https://app.example.com:8443/signin-oidc",
      method: .get,
      fields: [],
      recognized: false
    ),
    RecognitionCase(
      name: "a lookalike host is not the redirect_uri",
      url: "https://app.example.com.evil.example/signin-oidc",
      method: .get,
      fields: [],
      recognized: false
    ),
    RecognitionCase(
      name: "a SAMLResponse in the query, anywhere",
      url: "https://other.example.com/acs?SAMLResponse=PHNhbWxw",
      method: .get,
      fields: [],
      recognized: true
    ),
    RecognitionCase(
      name: "a urlencoded POST body carrying a SAMLResponse, anywhere",
      url: "https://other.example.com/sso/acs",
      method: .post,
      fields: [("SAMLResponse", "PHNhbWxw"), ("RelayState", "opaque")],
      recognized: true
    ),
    RecognitionCase(
      name: "an empty SAMLResponse is not a response",
      url: "https://other.example.com/sso/acs",
      method: .post,
      fields: [("SAMLResponse", "")],
      recognized: false
    ),
    RecognitionCase(
      name: "a form_post carrying a code, at the redirect_uri",
      url: "https://app.example.com/signin-oidc",
      method: .post,
      fields: [("code", "0.Ac8"), ("state", "opaque")],
      recognized: true
    ),
    RecognitionCase(
      name: "a form_post carrying an id_token, at the redirect_uri",
      url: "https://app.example.com/signin-oidc",
      method: .post,
      fields: [("id_token", "eyJ0eXAi")],
      recognized: true
    ),
    RecognitionCase(
      name: "a form_post carrying an error, at the redirect_uri",
      url: "https://app.example.com/signin-oidc",
      method: .post,
      fields: [("error", "access_denied")],
      recognized: true
    ),
    RecognitionCase(
      name: "a code posted somewhere that is not the redirect_uri",
      url: "https://other.example.com/signin-oidc",
      method: .post,
      fields: [("code", "0.Ac8")],
      recognized: false
    ),
    // The core extracts fields only from an `application/x-www-form-urlencoded` body,
    // so a multipart POST reaches the adapter with none and cannot match a field rule.
    RecognitionCase(
      name: "a multipart POST, whose body the core never extracted",
      url: "https://other.example.com/sso/acs",
      method: .post,
      fields: [],
      recognized: false
    ),
    RecognitionCase(
      name: "a SAMLart in the query is not recognized at all",
      url: "https://other.example.com/acs?SAMLart=AAQAA",
      method: .get,
      fields: [],
      recognized: false
    ),
    RecognitionCase(
      name: "a SAMLart posted is not recognized at all",
      url: "https://other.example.com/acs",
      method: .post,
      fields: [("SAMLart", "AAQAA")],
      recognized: false
    ),
    // Both of these are the core's to refuse, not the adapter's: the adapter answers on
    // field names and the redirect_uri, and would call each of them a Callback. See
    // `CallbackEligibilityTests`, which is where they stop.
    RecognitionCase(
      name: "a non-HTTPS target the adapter alone would accept",
      url: "http://other.example.com/acs?SAMLResponse=PHNhbWxw",
      method: .get,
      fields: [],
      recognized: true
    ),
    RecognitionCase(
      name: "a credentialed target the adapter alone would accept",
      url: "https://user:secret@app.example.com/signin-oidc",
      method: .get,
      fields: [],
      recognized: true
    ),
  ]
}

/// The core's half of the split: provider-independent, and asked before the adapter is.
@Suite("Admitting a candidate at all")
struct CallbackEligibilityTests {
  private static let providerHost = "login.microsoftonline.com"

  private func permits(_ url: String) -> Bool {
    CallbackEligibility.permits(
      CandidateNavigation(url: URL(string: url)!, method: .get),
      identityProviderHost: Self.providerHost
    )
  }

  @Test(
    "An ordinary HTTPS navigation away from the provider is admitted",
    arguments: [
      "https://app.example.com/signin-oidc",
      "https://other.example.com/acs?SAMLResponse=PHNhbWxw",
      "https://app.example.com:8443/signin-oidc",
    ]
  )
  func admitted(_ url: String) {
    #expect(permits(url))
  }

  /// A navigation this refuses is allowed to proceed rather than cancelled. The Bridge
  /// captures Callbacks; it is not a proxy policing the provider's redirect chain.
  @Test(
    "Non-HTTPS, credentialed, and still-at-the-provider navigations are not",
    arguments: [
      "http://other.example.com/acs?SAMLResponse=PHNhbWxw",
      "https://user:secret@app.example.com/signin-oidc",
      "https://:secret@app.example.com/signin-oidc",
      "https://login.microsoftonline.com/common/reprocess",
      "https://LOGIN.MICROSOFTONLINE.COM/common/reprocess",
      "about:blank",
    ]
  )
  func refused(_ url: String) {
    #expect(!permits(url))
  }

  /// The refusals the navigation delegate logs differently: an unencrypted or
  /// credentialed target is unusual and gets a notice line naming its host, while
  /// being still at the provider is most of a normal sign-in.
  @Test("Each refusal says which one it is")
  func refusalReason() {
    func refusal(_ url: String) -> CallbackEligibility.Refusal? {
      CallbackEligibility.refusal(
        CandidateNavigation(url: URL(string: url)!, method: .get),
        identityProviderHost: Self.providerHost
      )
    }
    #expect(refusal("http://other.example.com/acs") == .notEncrypted)
    #expect(refusal("https://user:secret@app.example.com/c") == .embeddedCredentials)
    #expect(refusal("https://login.microsoftonline.com/common/reprocess") == .stillAtTheProvider)
    #expect(refusal("https://app.example.com/signin-oidc") == nil)
  }
}

/// The two halves put together, which is what the navigation delegate actually asks:
/// the core's checks, then the adapter's rules, then a Callback in the shape the
/// protocol sends.
@Suite("What the Bridge does with one navigation")
struct CallbackCaptureTests {
  private static let plan = CallbackRecognitionTests.plan

  private func verdict(
    _ url: String, method: HTTPMethod = .get, fields: [(String, String)] = []
  ) -> CallbackCapture.Verdict {
    CallbackCapture.verdict(
      for: CandidateNavigation(
        url: URL(string: url)!,
        method: method,
        fields: fields.map(FormField.init(name:value:))
      ),
      plan: Self.plan,
      identityProviderHost: "login.microsoftonline.com"
    )
  }

  @Test("A recognized GET is the Callback, and its navigation is over")
  func recognizedGET() {
    #expect(
      verdict("https://app.example.com/signin-oidc?code=0.Ac8")
        == .capture(.get(url: URL(string: "https://app.example.com/signin-oidc?code=0.Ac8")!))
    )
  }

  @Test("A recognized POST carries its fields in order")
  func recognizedPOST() {
    let fields = [("SAMLResponse", "PHNhbWxw"), ("RelayState", "opaque")]
    #expect(
      verdict("https://other.example.com/sso/acs", method: .post, fields: fields)
        == .capture(
          .post(
            url: URL(string: "https://other.example.com/sso/acs")!,
            fields: fields.map(FormField.init(name:value:))
          )
        )
    )
  }

  /// The whole point of the core's checks being first: the adapter would call both of
  /// these a Callback, and neither is one. Both are allowed to proceed, because the
  /// Bridge captures Callbacks and does not police the provider's redirect chain.
  @Test(
    "A navigation the core refuses is never captured, whatever the adapter would say",
    arguments: [
      "http://other.example.com/acs?SAMLResponse=PHNhbWxw",
      "https://user:secret@app.example.com/signin-oidc",
      "https://login.microsoftonline.com/common/login",
    ]
  )
  func refusedIsNeverCaptured(_ url: String) {
    #expect(verdict(url) == .proceed)
  }

  @Test("An ordinary navigation the adapter does not recognize proceeds")
  func unrecognized() {
    #expect(verdict("https://app.example.com/other") == .proceed)
  }
}
