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
/// A candidate Callback targets HTTPS, carries no embedded credentials, and is not
/// still at the identity provider. These are provider-independent, so they stay here
/// rather than being restated inside every adapter's `recognizes`. The two checks that
/// need WebKit, main-frame only and urlencoded-body extraction, belong to the
/// navigation delegate; by the time a `CandidateNavigation` exists they have been made.
///
/// A navigation this refuses is allowed to proceed. The Bridge captures Callbacks; it
/// is not a security proxy for the provider's redirect chain.
public enum CallbackEligibility {
  public static func permits(
    _ candidate: CandidateNavigation,
    identityProviderHost: String
  ) -> Bool {
    guard candidate.url.scheme?.lowercased() == "https" else { return false }
    guard candidate.url.user() == nil, candidate.url.password() == nil else { return false }
    guard let host = candidate.url.host()?.lowercased() else { return false }
    return host != identityProviderHost.lowercased()
  }
}
