import Foundation

/// One identity provider's knowledge, and the only place provider-shaped judgment
/// lives. See docs/adr/0003-build-time-identity-provider-adapter-seam.md.
///
/// Two static facts and one call: where sign-in starts, and what to do with a Sign-in
/// request that arrived there. Everything else about a Handoff, selecting the adapter,
/// replaying the request, the navigation delegate, and assembling the response, is the
/// Bridge core's.
public protocol IdentityProviderAdapter: Sendable {
  /// The sign-in entry origins this adapter claims, compared on scheme, host, and port.
  static var entryOrigins: [URL] { get }

  /// Nil when nothing in this Sign-in request is replayable, which the Bridge answers
  /// `unsupported_request` before any window is shown.
  func plan(_ request: SignInRequest) -> HandoffPlan?
}

/// The whole per-Handoff contract, made once at the start of the Handoff.
///
/// The two questions the core needs answered arrive together: what to tell the user
/// before they approve, and whether a navigation is the Callback. `recognizes` closes
/// over the Sign-in request, so the core never carries it back to the adapter on every
/// navigation.
public struct HandoffPlan: Sendable {
  /// Where the Callback will land, for the Approval to show. Nil means the Handoff is
  /// replayable but its destination could not be derived, and the Approval says so
  /// rather than guessing.
  public let destination: URL?

  /// Whether this candidate is the Callback. Only ever asked about a candidate the
  /// core has already admitted; see `CallbackEligibility`.
  public let recognizes: @Sendable (CandidateNavigation) -> Bool

  public init(destination: URL?, recognizes: @escaping @Sendable (CandidateNavigation) -> Bool) {
    self.destination = destination
    self.recognizes = recognizes
  }
}
