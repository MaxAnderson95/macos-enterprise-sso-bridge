import Foundation

/// One sign-in transaction, and the rule ADR 0002 exists to enforce: nothing that can
/// load web content is created until the user approves.
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

  public let prompt: ApprovalPrompt
  public private(set) var phase: Phase = .awaitingApproval

  private let makeWebView: () -> WebView
  private var webView: WebView?

  public init(prompt: ApprovalPrompt, makeWebView: @escaping () -> WebView) {
    self.prompt = prompt
    self.makeWebView = makeWebView
  }

  /// The Approval. The only call that reaches the factory, and the only way out of
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
