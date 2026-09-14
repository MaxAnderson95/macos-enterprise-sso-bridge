import AppKit
import BridgeCore
import WebKit

/// The Handoff's half of the process: put the panel up, and turn whatever happens next
/// into the one terminal response this Handoff is allowed to send.
///
/// Every way a Handoff can end early reaches `dismiss` through `Handoff.decline`, so
/// Cancel on the Approval, Cancel in the footer, the close button, and Close on the
/// failure state are one path with one log line, not four that have to be kept in
/// agreement. Once a response has gone out, that same path only closes the process,
/// because a Handoff sends exactly one answer.
@MainActor
final class HandoffAppDelegate: NSObject, NSApplicationDelegate {
  private let handoff: Handoff<WKWebView>
  private let request: SignInRequest
  private let plan: HandoffPlan
  private let channel: ProtocolChannel
  private var controller: HandoffWindowController?
  private var webViewHandoff: HandoffWebView?
  private var answered = false

  init(
    handoff: Handoff<WKWebView>,
    request: SignInRequest,
    plan: HandoffPlan,
    channel: ProtocolChannel
  ) {
    self.handoff = handoff
    self.request = request
    self.plan = plan
    self.channel = channel
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = HandoffWindowController(
      prompt: handoff.prompt,
      onApprove: { [weak self] in self?.approve() },
      onDismiss: { [weak self] in self?.dismiss() }
    )
    controller.present()
    self.controller = controller
  }

  /// The Approval, and the only place a webview is created. The order is the rule ADR
  /// 0002 exists for: the factory runs here, the window grows around what it produced,
  /// and only then does anything load.
  private func approve() {
    let webView = handoff.approve()
    let webViewHandoff = HandoffWebView(
      webView: webView,
      request: request,
      plan: plan,
      onOutcome: { [weak self] outcome in self?.finish(outcome) }
    )
    self.webViewHandoff = webViewHandoff
    controller?.showAuthenticating(webView: webView)
    webViewHandoff.start()
  }

  private func finish(_ outcome: HandoffWebView.Outcome) {
    switch outcome {
    case .captured(let callback):
      deliver(callback)
    case .failed(let detail):
      fail(with: .error(.navigationFailed, detail: detail))
    }
  }

  /// The Callback going back whole: a GET as a URL, a POST with its fields, which the
  /// Extension's Relay page submits from the original tab.
  ///
  /// An assertion too fat for the 1 MiB native-messaging cap becomes
  /// `callback_too_large` inside the channel, and that code's copy says the Bridge has
  /// the details, so the window is what has to show them. Reading back what was sent
  /// rather than what was asked for is the only way this knows which happened.
  private func deliver(_ callback: Callback) {
    guard case .callback = answer(with: .callback(callback)) else {
      controller?.showFailure()
      return
    }
    controller?.showReturningCallback()
    exit(0)
  }

  /// The Extension is told immediately, and the window stays up saying what happened,
  /// because a Handoff that fails while the user is looking at it should not vanish.
  private func fail(with response: BridgeResponse) {
    answer(with: response)
    controller?.showFailure()
  }

  private func dismiss() {
    guard !answered else {
      // The failure state's Close button. The answer went out when it failed.
      exit(0)
    }
    terminate(with: handoff.decline())
  }

  @discardableResult
  private func answer(with response: BridgeResponse) -> BridgeResponse {
    answered = true
    do {
      return try channel.send(response) ?? response
    } catch {
      BridgeLog.wire.error("could not write the terminal response: \(error, privacy: .public)")
      exit(1)
    }
  }

  private func terminate(with response: BridgeResponse) -> Never {
    answer(with: response)
    exit(0)
  }
}
