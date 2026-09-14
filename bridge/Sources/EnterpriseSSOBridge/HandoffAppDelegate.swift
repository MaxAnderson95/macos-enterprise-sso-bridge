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
    case .captured(.get(let url)):
      controller?.showReturningCallback()
      terminate(with: .callback(.get(url: url)))
    case .captured(.post):
      // Recognizing a POST Callback is only half done without its body, which is issue
      // #26. Answering `internal` says so; answering with a fieldless POST Callback
      // would hand the browser a form submission carrying no assertion.
      fail(with: .error(.internalFailure, detail: "post callback body extraction"))
    case .failed(let detail):
      fail(with: .error(.navigationFailed, detail: detail))
    }
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

  private func answer(with response: BridgeResponse) {
    answered = true
    do {
      try channel.send(response)
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
