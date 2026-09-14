import Foundation

/// Entra: the only identity provider v1 implements.
///
/// It knows three things nobody else in the Bridge does: that `redirect_uri` and
/// `SAMLRequest` are what make a Sign-in request replayable, where each of them says
/// the response will land, and the field names a Callback carries.
public struct EntraAdapter: IdentityProviderAdapter {
  public static let entryOrigins = EntryOrigins.entra

  /// The OIDC field names, recognized only at the `redirect_uri`. `SAMLResponse` is
  /// not here: it is recognized wherever it appears.
  private static let oidcResponseFields = ["code", "id_token", "error"]

  public init() {}

  public func plan(_ request: SignInRequest) -> HandoffPlan? {
    let query = Self.queryItems(of: request.url)
    let rawRedirectURI = query.first { $0.name == "redirect_uri" }?.value
    let samlRequest = Self.samlRequest(in: request, query: query)

    // The judgment this adapter owns: neither of these means there is nothing to
    // replay, whatever else the request carries.
    guard rawRedirectURI != nil || samlRequest != nil else { return nil }

    // A `redirect_uri` that will not parse still makes the request replayable; it just
    // leaves the Approval with nothing truthful to show.
    let redirectURI = rawRedirectURI.flatMap(Self.webURL)
    let destination = redirectURI ?? samlRequest.flatMap(SAMLAuthnRequest.destination)

    return HandoffPlan(destination: destination) { candidate in
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

  /// A POST carries `SAMLRequest` as a form field; the HTTP-Redirect binding puts it in
  /// the query.
  private static func samlRequest(in request: SignInRequest, query: [URLQueryItem]) -> String? {
    if case .post(_, let fields) = request,
      let field = fields.first(where: { $0.name == "SAMLRequest" })
    {
      return field.value
    }
    return query.first { $0.name == "SAMLRequest" }?.value
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
