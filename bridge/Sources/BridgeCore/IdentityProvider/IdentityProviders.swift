import Foundation

/// The registry, and the one call the rest of the Bridge makes to plan a Handoff.
///
/// Selection and planning are the same question from the core's side, so they are one
/// call: nil is `unsupported_request`, whether because no adapter claims the origin or
/// because the adapter that does found nothing replayable.
public enum IdentityProviders {
  static let adapters: [any IdentityProviderAdapter] = [EntraAdapter()]

  public static func plan(for request: SignInRequest) -> HandoffPlan? {
    guard let adapter = adapters.first(where: { claims(request.url, $0) }) else {
      // Not redundant with the Extension's capture filter. ADR 0002 treats the
      // Extension as untrusted, so the Bridge decides which origins it will replay.
      BridgeLog.handoff.error(
        "no adapter claims \(request.url.host() ?? "?", privacy: .public)"
      )
      return nil
    }
    guard let plan = adapter.plan(request) else {
      BridgeLog.handoff.error("nothing replayable in the Sign-in request")
      return nil
    }
    if let destination = plan.destination {
      BridgeLog.handoff.info(
        "planned a Handoff returning to \(destination.host() ?? "?", privacy: .public)"
      )
    } else {
      BridgeLog.handoff.notice("planned a Handoff whose destination could not be derived")
    }
    return plan
  }

  /// Scheme, host, and port, since an entry origin is an origin and carries no path.
  private static func claims(_ url: URL, _ adapter: any IdentityProviderAdapter) -> Bool {
    type(of: adapter).entryOrigins.contains { origin in
      url.scheme?.lowercased() == origin.scheme?.lowercased()
        && url.host()?.lowercased() == origin.host()?.lowercased()
        && url.effectivePort == origin.effectivePort
    }
  }
}
