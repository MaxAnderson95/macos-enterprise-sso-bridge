import Foundation

/// A navigation the Bridge is deciding about, in the same `(url, method, fields)` shape
/// the Sign-in request arrives in.
///
/// A value, never a `WKNavigationAction`, which is what makes the recognition rules
/// testable without a webview. `fields` is what the core managed to extract from a
/// urlencoded body, so a multipart or JSON POST reaches the adapter with none.
public struct CandidateNavigation: Equatable, Sendable {
  public let url: URL
  public let method: HTTPMethod
  public let fields: [FormField]

  public init(url: URL, method: HTTPMethod, fields: [FormField] = []) {
    self.url = url
    self.method = method
    self.fields = fields
  }

  /// The first value under this name, matching how a form's fields are read back.
  public func field(_ name: String) -> String? {
    fields.first { $0.name == name }?.value
  }
}

/// The checks the Bridge core makes before it asks an adapter anything.
///
/// A candidate Callback targets HTTPS, carries no embedded credentials, is not still at
/// the identity provider, and, when it is a POST, arrived with a urlencoded body the
/// core could read. These are provider-independent, so they stay here rather than being
/// restated inside every adapter's `recognizes`. The one check that needs WebKit,
/// main-frame only, belongs to the navigation delegate; so does running the extraction
/// whose result the POST rule below reads.
///
/// A navigation this refuses is allowed to proceed. The Bridge captures Callbacks; it
/// is not a security proxy for the provider's redirect chain.
public enum CallbackEligibility {
  /// Why a navigation is not a candidate. Named rather than boolean because the two
  /// refusals differ in what they are worth saying: still being at the provider is
  /// every navigation of a normal sign-in, while an unencrypted or credentialed target
  /// is unusual enough that the navigation delegate logs its host.
  public enum Refusal: String, Sendable {
    case notEncrypted = "not https"
    case embeddedCredentials = "embedded credentials"
    case stillAtTheProvider = "still at the identity provider"
    case noURLEncodedBody = "post body is not urlencoded"
  }

  public static func refusal(
    _ candidate: CandidateNavigation,
    identityProviderHost: String
  ) -> Refusal? {
    guard candidate.url.scheme?.lowercased() == "https" else { return .notEncrypted }
    guard candidate.url.user() == nil, candidate.url.password() == nil else {
      return .embeddedCredentials
    }
    guard let host = candidate.url.host()?.lowercased() else { return .notEncrypted }
    guard host != identityProviderHost.lowercased() else { return .stillAtTheProvider }
    // The positive rule from docs/spec/callback-recognition.md, enforced where the
    // extraction's result is a value: a POST arrives with fields only when the core
    // read a urlencoded body, so an empty one is a multipart or JSON POST, or a
    // submission whose fields could not be found at all. Neither is handed over, and
    // the alternative is worse than letting it proceed: the `redirect_uri` rule alone
    // would answer for it and the Application would receive a form carrying nothing.
    guard candidate.method == .get || !candidate.fields.isEmpty else { return .noURLEncodedBody }
    return nil
  }

  public static func permits(
    _ candidate: CandidateNavigation,
    identityProviderHost: String
  ) -> Bool {
    refusal(candidate, identityProviderHost: identityProviderHost) == nil
  }
}
