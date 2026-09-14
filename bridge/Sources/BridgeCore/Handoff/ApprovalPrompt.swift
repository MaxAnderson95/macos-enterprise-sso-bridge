import Foundation

/// Everything the Approval is allowed to say, and the copy it says it in.
///
/// Every value here is something the Bridge established for itself: the destination
/// from the adapter's plan, the identity provider from the Sign-in request's own URL
/// after the adapter claimed that origin, and the browser from the `AllowedBrowser`
/// caller authentication matched. Nothing the Extension asserts alongside the request
/// can reach this type, so no claimed Application name can reach the window. See
/// docs/adr/0002-user-approval-before-every-handoff.md.
///
/// The copy lives here rather than in the window so that both states are readable
/// without AppKit, and so the window is left with nothing to decide but layout.
public struct ApprovalPrompt: Equatable, Sendable {
  /// Where the Callback lands. Nil is the second approval state: replayable, but the
  /// adapter could not derive a destination, which the prompt says rather than guesses.
  public let destinationHost: String?
  public let providerHost: String
  public let browserName: String

  public init(plan: HandoffPlan, request: SignInRequest, caller: AllowedBrowser) {
    // A request frame without a host never decodes, and the adapter matched this
    // origin to claim the request, so the fallback is unreachable rather than a case
    // the copy is written for.
    self.init(
      destinationHost: plan.destination?.host(),
      providerHost: request.url.host() ?? "the identity provider",
      browserName: caller.displayName
    )
  }

  public init(destinationHost: String?, providerHost: String, browserName: String) {
    self.destinationHost = destinationHost
    self.providerHost = providerHost
    self.browserName = browserName
  }

  /// Names the destination when there is one, and otherwise the provider, because the
  /// heading is the question being asked and a heading naming nothing is not a question.
  public var heading: String {
    if let destinationHost {
      "Sign in to \(destinationHost)?"
    } else {
      "Sign in through \(providerHost)?"
    }
  }

  /// The second state leans on recency instead of a destination: the user clicked the
  /// toolbar action a second ago, so an unexpected prompt is the signal to cancel.
  public var body: String {
    if destinationHost != nil {
      "\(browserName) asked to sign in through \(providerHost) using this Mac's work "
        + "account. Nothing has loaded yet."
    } else {
      "\(browserName) asked for a sign-in, but the Bridge cannot tell which site will "
        + "receive it. Continue only if you started this sign-in yourself a moment ago."
    }
  }
}
