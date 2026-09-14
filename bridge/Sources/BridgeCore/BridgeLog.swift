import os

/// Every Bridge diagnostic, because stdout carries protocol frames and nothing else.
///
/// Lines carry hosts, methods, phases, error codes, and the matched browser's name.
/// They never carry URLs, query strings, bodies, form fields, tokens, or assertions:
/// the `logSummary` properties on the wire types are how a request or a response is
/// named in a line without spelling out what it contains.
public enum BridgeLog {
  public static let subsystem = "tech.maxanderson.enterprise-sso-bridge"

  /// The native-messaging exchange: framing, decoding, and the terminal response.
  public static let wire = Logger(subsystem: subsystem, category: "wire")
}
