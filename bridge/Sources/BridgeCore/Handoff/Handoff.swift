import Foundation

/// One sign-in transaction, and the rule ADR 0002 exists to enforce: nothing that can
/// load web content is created until the user approves, or, for a Pre-approved
/// Application, until the point the Approval would have been given.
///
/// The webview arrives from an injected factory instead of being created here, so the
/// ordering is a fact about this type rather than a habit of its caller: a test with a
/// spy can see whether a webview was made, and when. That seam is also what keeps
/// WebKit and AppKit out of `BridgeCore`. Generic over what the factory produces
/// because the core never needs to know what a webview is, only when one may exist.
public final class Handoff<WebView> {
  /// Which part of the Handoff was on screen, for the `declined` line that
  /// docs/spec/bridge.md asks for.
  public enum Phase: String, Sendable {
    case awaitingApproval = "awaiting approval"
    case authenticating
  }

  /// How a planned Handoff begins: as a Handoff to run, or as the answer that ends it
  /// before any window exists.
  public enum Start {
    case handoff(Handoff)
    case answer(BridgeResponse)
  }

  public let prompt: ApprovalPrompt
  /// True when the destination is a Pre-approved Application, so the window calls
  /// `approve()` itself as it opens instead of asking.
  public let isPreApproved: Bool
  public private(set) var phase: Phase = .awaitingApproval

  private let makeWebView: () -> WebView
  private var webView: WebView?

  init(prompt: ApprovalPrompt, isPreApproved: Bool = false, makeWebView: @escaping () -> WebView) {
    self.prompt = prompt
    self.isPreApproved = isPreApproved
    self.makeWebView = makeWebView
  }

  /// ADR 0004's table. A pre-approved destination skips the Approval whoever started
  /// the Handoff; otherwise a click gets the Approval, and an automatic start is told
  /// `approval_required` so no window takes focus for a sign-in the user did not ask
  /// the Bridge for.
  public static func start(
    prompt: ApprovalPrompt,
    trigger: HandoffTrigger,
    destinationIsPreApproved: Bool,
    makeWebView: @escaping () -> WebView
  ) -> Start {
    if destinationIsPreApproved {
      BridgeLog.handoff.notice(
        "pre-approved Handoff to \(prompt.destinationHost ?? "?", privacy: .public), \(trigger.rawValue, privacy: .public)"
      )
      return .handoff(Handoff(prompt: prompt, isPreApproved: true, makeWebView: makeWebView))
    }
    switch trigger {
    case .manual:
      return .handoff(Handoff(prompt: prompt, makeWebView: makeWebView))
    case .automatic:
      return .answer(.approvalRequired)
    }
  }

  /// The Approval, given by the user or, for a Pre-approved Application, by the window
  /// as it opens. The only call that reaches the factory, and the only way out of
  /// `awaitingApproval`.
  @discardableResult
  public func approve() -> WebView {
    if let webView {
      BridgeLog.handoff.error("ignored a second Approval for one Handoff")
      return webView
    }
    let created = makeWebView()
    webView = created
    phase = .authenticating
    BridgeLog.handoff.info("approved, now \(self.phase.rawValue, privacy: .public)")
    return created
  }

  /// Cancel, the close button, and every other way a Handoff ends without a Callback.
  /// One call, so a decline from any phase is the same decline and carries the phase
  /// it came from into the log.
  public func decline() -> BridgeResponse {
    BridgeLog.handoff.notice("declined while \(self.phase.rawValue, privacy: .public)")
    return .declined
  }
}
