import Foundation

/// The Application origins the user listed in the Bridge's preferences, whose Handoffs
/// proceed without an Approval. See
/// docs/adr/0004-pre-approved-applications-skip-the-approval.md.
///
/// Matched only against the plan's `boundDestination`, the one the adapter can say the
/// Callback will actually reach, never against a display hint or anything the Extension
/// sends: the Extension is the distrusted party, and a hint is not where the credential
/// goes.
public struct PreApprovedApplications: Equatable, Sendable {
  /// The `.app`'s bundle identifier, named explicitly rather than read through
  /// `UserDefaults.standard`, so the bare SwiftPM executable used in development reads
  /// the same list as the installed app.
  public static let preferencesDomain = "tech.maxanderson.enterprise-sso-bridge"
  public static let preferenceKey = "PreApprovedApplications"

  private struct Origin: Equatable, Sendable {
    let host: String
    let port: Int
  }

  private let origins: [Origin]

  /// Whatever the preferences hold under the key. Nil, a value that is not an array, and
  /// an empty array all pre-approve nothing. Each element that is not an HTTPS origin is
  /// logged by index, never by value, and ignored.
  public init(preferenceValue: Any?) {
    guard let preferenceValue else {
      origins = []
      return
    }
    guard let entries = preferenceValue as? [Any] else {
      BridgeLog.handoff.error("ignored \(Self.preferenceKey, privacy: .public): not an array")
      origins = []
      return
    }
    origins = entries.enumerated().compactMap { index, entry in
      guard let origin = (entry as? String).flatMap(Self.origin(from:)) else {
        BridgeLog.handoff.error(
          "ignored \(Self.preferenceKey, privacy: .public) entry \(index, privacy: .public): not an HTTPS origin"
        )
        return nil
      }
      return origin
    }
  }

  public static func fromPreferences() -> PreApprovedApplications {
    PreApprovedApplications(
      preferenceValue: CFPreferencesCopyAppValue(
        preferenceKey as CFString, preferencesDomain as CFString))
  }

  /// Scheme, host, and effective port, compared exactly. A nil destination is one the
  /// adapter could not bind the Callback to, and is never pre-approved.
  public func contains(_ destination: URL?) -> Bool {
    guard let destination, destination.scheme?.lowercased() == "https",
      let host = destination.host()?.lowercased(), let port = destination.effectivePort
    else {
      return false
    }
    return origins.contains(Origin(host: host, port: port))
  }

  /// What the user typed into the editor, as the entry it would store: `https://host`,
  /// or `https://host:port` for a port other than 443. A bare host is taken as HTTPS, and
  /// a pasted URL is cut down to its origin, because the origin is all an entry can
  /// match. Nil for anything that is not HTTPS or that carries credentials, so the
  /// editor can never store an entry that `init(preferenceValue:)` would ignore.
  public static func entry(from input: String) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let text = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard let url = URL(string: text), url.scheme?.lowercased() == "https",
      url.user == nil, url.password == nil,
      let host = url.host()?.lowercased(), !host.isEmpty, let port = url.effectivePort
    else {
      return nil
    }
    // `host()` strips an IPv6 literal's brackets, which the authority needs back.
    let authority = host.contains(":") ? "[\(host)]" : host
    let entry = port == 443 ? "https://\(authority)" : "https://\(authority):\(port)"
    return origin(from: entry) == nil ? nil : entry
  }

  /// Whether a stored string is one `init(preferenceValue:)` reads, so the editor can
  /// mark the ones it ignores.
  public static func isReadable(_ entry: String) -> Bool {
    origin(from: entry) != nil
  }

  /// The strings stored under the key, in order, for the editor to show. Includes any an
  /// earlier `defaults write` stored that `init(preferenceValue:)` ignores, so the user
  /// can see and remove them.
  public static func storedEntries() -> [String] {
    let value = CFPreferencesCopyAppValue(preferenceKey as CFString, preferencesDomain as CFString)
    return (value as? [Any])?.compactMap { $0 as? String } ?? []
  }

  /// Replaces the stored list. An empty list removes the key, which is the state a fresh
  /// install starts in.
  public static func store(_ entries: [String]) {
    CFPreferencesSetAppValue(
      preferenceKey as CFString,
      entries.isEmpty ? nil : entries as CFArray,
      preferencesDomain as CFString
    )
    if !CFPreferencesAppSynchronize(preferencesDomain as CFString) {
      BridgeLog.handoff.error("could not save \(preferenceKey, privacy: .public)")
    }
  }

  /// An origin and nothing else: a path, query, fragment, or credentials would suggest
  /// matching the entry does more than name a host and port, and it does not.
  private static func origin(from entry: String) -> Origin? {
    guard let url = URL(string: entry), url.scheme?.lowercased() == "https",
      let host = url.host()?.lowercased(), !host.isEmpty, let port = url.effectivePort,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      ["", "/"].contains(url.path())
    else {
      return nil
    }
    return Origin(host: host, port: port)
  }
}
