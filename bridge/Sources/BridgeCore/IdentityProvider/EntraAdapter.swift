import Foundation

/// Entra: the only identity provider v1 implements.
///
/// It knows what makes a Sign-in request replayable, where it says the response will
/// land, and the field names a Callback carries.
public struct EntraAdapter: IdentityProviderAdapter {
  public static let entryOrigins = EntryOrigins.entra

  /// The OIDC field names, recognized only at the `redirect_uri`. `SAMLResponse` is
  /// not here: it is recognized wherever it appears.
  private static let oidcResponseFields = ["code", "id_token", "error"]

  public init() {}

  public func plan(_ request: SignInRequest) -> HandoffPlan? {
    let query = Self.queryItems(of: request.url)
    let rawRedirectURI = query.first { $0.name == "redirect_uri" }?.value
    let samlRequests = Self.samlRequests(in: request, query: query)

    // The judgment this adapter owns: neither of these means there is nothing to
    // replay, whatever else the request carries.
    guard rawRedirectURI != nil || !samlRequests.isEmpty else { return nil }

    // A `redirect_uri` that will not parse still makes the request replayable; it just
    // leaves the Approval with nothing truthful to show.
    let redirectURI = rawRedirectURI.flatMap(Self.webURL)
    // With competing SAML values, the Bridge cannot predict which one Entra will read.
    let saml =
      samlRequests.count == 1 ? SAMLAuthnRequest.destinations(fromEncoded: samlRequests[0]) : nil
    let destination = redirectURI ?? saml?.assertionConsumerService ?? saml?.issuer

    // Entra validates a `redirect_uri` against the client's registration and posts a
    // SAML assertion to the ACS URL, so each is where the Callback lands only when it is
    // the sole protocol in play. A `redirect_uri` on a SAML request is not what Entra
    // answers, and an issuer is not an endpoint at all.
    let boundDestination: URL? =
      switch (rawRedirectURI, samlRequests.count) {
      case (.some, 0): redirectURI
      case (nil, 1): saml?.assertionConsumerService
      default: nil
      }

    return HandoffPlan(destination: destination, boundDestination: boundDestination) {
      candidate in
      Self.recognizes(candidate, redirectURI: redirectURI)
    }
  }

  /// The rules in docs/spec/callback-recognition.md, asked only about a candidate the
  /// core has already admitted.
  ///
  /// The body rule is asked before the `redirect_uri` match, which would otherwise
  /// answer for every `form_post` Callback on its own and leave the OIDC field names
  /// doing nothing. The set of candidates this accepts is the same either way.
  private static func recognizes(_ candidate: CandidateNavigation, redirectURI: URL?) -> Bool {
    let atRedirectURI = redirectURI.map { Self.matches(candidate.url, $0) } ?? false

    if candidate.method == .post {
      if let response = candidate.field("SAMLResponse"), !response.isEmpty { return true }
      if atRedirectURI,
        oidcResponseFields.contains(where: { candidate.field($0)?.isEmpty == false })
      {
        return true
      }
    }
    if queryItems(of: candidate.url).contains(where: { $0.name == "SAMLResponse" }) {
      return true
    }
    return atRedirectURI
  }

  /// Scheme, host, port, and path. Not the query: a Callback's whole payload is in the
  /// query or the body, so requiring it to match would recognize nothing.
  private static func matches(_ candidate: URL, _ redirectURI: URL) -> Bool {
    candidate.scheme?.lowercased() == redirectURI.scheme?.lowercased()
      && candidate.host()?.lowercased() == redirectURI.host()?.lowercased()
      && candidate.effectivePort == redirectURI.effectivePort
      && normalizedPath(of: candidate) == normalizedPath(of: redirectURI)
  }

  /// Check both carriers so a POST with a SAML value in each cannot bind a destination.
  private static func samlRequests(in request: SignInRequest, query: [URLQueryItem]) -> [String] {
    let queryValues = query.filter { isSAMLRequest($0.name) }.map { $0.value ?? "" }
    if case .post(_, let fields) = request {
      return queryValues + fields.filter { isSAMLRequest($0.name) }.map(\.value)
    }
    return queryValues
  }

  /// Entra matches this name without regard to case, including when it checks for duplicates.
  private static func isSAMLRequest(_ name: String) -> Bool {
    name.lowercased() == "samlrequest"
  }

  private static func queryItems(of url: URL) -> [URLQueryItem] {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
  }

  private static func webURL(_ text: String) -> URL? {
    guard let url = URL(string: text), url.scheme != nil, url.host() != nil else { return nil }
    return url
  }

  /// The path as its segments, each decoded on its own.
  ///
  /// Decoding the whole path first would turn `%2F` into a separator and make
  /// `/callback/a%2Fb` compare equal to `/callback/a/b`, which an Application can route
  /// to different resources. Splitting before decoding keeps an encoded slash inside
  /// its segment while still ignoring cosmetic differences like `%7E` for `~`.
  /// An empty path and "/" are the same place.
  private static func normalizedPath(of url: URL) -> [String] {
    let path = url.path(percentEncoded: true)
    let segments = (path.isEmpty ? "/" : path)
      .split(separator: "/", omittingEmptySubsequences: false)
    return segments.map { $0.removingPercentEncoding ?? String($0) }
  }
}
