import Foundation

/// The navigation that leaves the identity provider and returns to the Application.
public enum Callback: Equatable, Sendable {
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
}

/// The closed set of `error` codes, with the one code that carries data carrying it
/// in its own case rather than as an optional every other code has to ignore.
public enum BridgeErrorCode: Equatable, Sendable {
  /// The Bridge does not implement the request's `version`.
  case unsupportedVersion(bridgeVersion: Int)
  /// The frame arrived and parsed as JSON, but is not a valid request.
  case malformedRequest
  /// Nothing in the Sign-in request is replayable: the adapter returned no plan.
  case unsupportedRequest
  /// The assembled Callback exceeds the host-to-browser cap.
  case callbackTooLarge
  /// The `WKWebView` failed to load, with the underlying error in `detail`.
  case navigationFailed
  /// Anything else the Bridge cannot complete.
  case internalFailure

  public var wireName: String {
    switch self {
    case .unsupportedVersion: "unsupported_version"
    case .malformedRequest: "malformed_request"
    case .unsupportedRequest: "unsupported_request"
    case .callbackTooLarge: "callback_too_large"
    case .navigationFailed: "navigation_failed"
    case .internalFailure: "internal"
    }
  }

  var bridgeVersion: Int? {
    switch self {
    case .unsupportedVersion(let version): version
    default: nil
    }
  }
}

/// The one message the Bridge sends, tagged on `result`.
///
/// An enum with associated values rather than a bag of optionals, so the Bridge
/// cannot build a half-populated response and every later termination path has to
/// name which of the three outcomes it is producing.
public enum BridgeResponse: Equatable, Sendable {
  case callback(Callback)
  case declined
  case error(BridgeErrorCode, detail: String?)

  /// The outcome and, for a Callback, its host. Never a path, a query, or a field.
  public var logSummary: String {
    switch self {
    case .callback(let callback):
      "callback \(callback.method.rawValue) \(callback.url.host() ?? "?")"
    case .declined:
      "declined"
    case .error(let code, _):
      "error \(code.wireName)"
    }
  }
}

extension BridgeResponse: Encodable {
  private enum CodingKeys: String, CodingKey {
    case result
    case url
    case method
    case fields
    case code
    case detail
    case bridgeVersion
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .callback(let callback):
      try container.encode("callback", forKey: .result)
      try container.encode(callback.url.absoluteString, forKey: .url)
      try container.encode(callback.method.rawValue, forKey: .method)
      if case .post(_, let fields) = callback {
        try container.encode(fields, forKey: .fields)
      }
    case .declined:
      try container.encode("declined", forKey: .result)
    case .error(let code, let detail):
      try container.encode("error", forKey: .result)
      try container.encode(code.wireName, forKey: .code)
      try container.encodeIfPresent(detail, forKey: .detail)
      try container.encodeIfPresent(code.bridgeVersion, forKey: .bridgeVersion)
    }
  }
}
