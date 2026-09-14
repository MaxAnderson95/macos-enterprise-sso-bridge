import Foundation

/// The Application's original request to the identity provider, as the Extension
/// observed it and as the Bridge will replay it.
///
/// Modelled as an enum rather than a method plus an optional field list, so a GET
/// carrying form fields is unrepresentable rather than something every later caller
/// has to remember to reject.
public enum SignInRequest: Equatable, Sendable {
  case get(url: URL)
  case post(url: URL, fields: [FormField])

  public var url: URL {
    switch self {
    case .get(let url): url
    case .post(let url, _): url
    }
  }

  public var method: HTTPMethod {
    switch self {
    case .get: .get
    case .post: .post
    }
  }

  /// Method and host only, for `os_log`. Never the path, the query, or the fields.
  public var logSummary: String {
    "\(method.rawValue) \(url.host() ?? "?")"
  }
}

/// The one message the Extension sends: the wire version, and the Sign-in request.
///
/// There is no Handoff identifier. One process serves one Handoff, so there is
/// nothing to route.
public struct RequestMessage: Equatable, Sendable {
  public let version: Int
  public let signInRequest: SignInRequest

  public init(version: Int, signInRequest: SignInRequest) {
    self.version = version
    self.signInRequest = signInRequest
  }
}

extension RequestMessage: Decodable {
  private enum CodingKeys: String, CodingKey {
    case version
    case url
    case method
    case fields
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .version)

    // Decoded as a string and parsed here because `URL`'s own decoding accepts a
    // relative reference, which is not a request the Bridge could ever replay. Which
    // scheme and which origin are allowed is the adapter's judgment, not the codec's.
    let rawURL = try container.decode(String.self, forKey: .url)
    guard let url = URL(string: rawURL), url.scheme != nil, url.host() != nil else {
      throw DecodingError.dataCorruptedError(
        forKey: .url,
        in: container,
        debugDescription: "url must be an absolute URL with a host"
      )
    }

    let rawMethod = try container.decode(String.self, forKey: .method)
    guard let method = HTTPMethod(rawValue: rawMethod) else {
      throw DecodingError.dataCorruptedError(
        forKey: .method,
        in: container,
        debugDescription: "method must be GET or POST"
      )
    }

    let fields = try container.decodeIfPresent([FormField].self, forKey: .fields)
    switch method {
    case .get:
      guard fields == nil else {
        throw DecodingError.dataCorruptedError(
          forKey: .fields,
          in: container,
          debugDescription: "fields is present only on a POST"
        )
      }
      self.init(version: version, signInRequest: .get(url: url))
    case .post:
      self.init(version: version, signInRequest: .post(url: url, fields: fields ?? []))
    }
  }
}

/// Just enough of a request frame to answer `unsupported_version` before the rest of
/// the schema is read, because a version the Bridge does not implement is free to
/// spell everything else differently.
struct VersionEnvelope: Decodable {
  let version: Int
}
