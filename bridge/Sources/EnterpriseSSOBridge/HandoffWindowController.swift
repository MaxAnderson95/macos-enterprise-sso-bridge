import AppKit
import BridgeCore

/// The Bridge's one window, through every state a Handoff puts it in.
///
/// Two shapes, settled by the prototype in issue #10. The Approval is a 540 pt panel
/// that reads as a question; on approval the same window grows to 900 x 520 to hold the
/// webview, and that resize is the visible signal that the Handoff started. Plate:
/// https://agentdrop.gucu.org/a/0mgxOqOaPuNPlfwTgl0vo0/bridge-window-states.png
///
/// It renders copy and reports which button the user pressed, and decides nothing about
/// what an answer means. Cancel in the panel, Cancel in the footer, Close on the
/// failure state, and the close button are all the same report, which is what keeps
/// "one way to end a Handoff early" true of the code and not just of the prose.
///
/// It takes the webview as an `NSView`, so the window knows about layout and nothing
/// about WebKit.
@MainActor
final class HandoffWindowController: NSObject, NSWindowDelegate {
  /// The panel width the Approval and the failure state share.
  static let panelWidth: CGFloat = 540
  /// What the window grows to once there is a webview to hold.
  static let handoffContentSize = NSSize(width: 900, height: 520)

  private static let margin: CGFloat = 24
  private static let footerHeight: CGFloat = 44

  private let prompt: ApprovalPrompt
  private let copy: HandoffWindowCopy
  private let onApprove: () -> Void
  private let onDismiss: () -> Void
  private(set) var window: NSWindow?
  private var footerLabel: NSTextField?

  init(prompt: ApprovalPrompt, onApprove: @escaping () -> Void, onDismiss: @escaping () -> Void) {
    self.prompt = prompt
    self.copy = HandoffWindowCopy(prompt: prompt)
    self.onApprove = onApprove
    self.onDismiss = onDismiss
  }

  /// Shows the panel and takes focus. The user clicked the toolbar action a second
  /// earlier, so the focus change is expected, and a prompt nobody sees is not an
  /// Approval.
  func present() {
    let content = approvalContentView()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: content.fittingSize.height),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    // Fixed, because the body already carries the destination and the requesting
    // browser, so a per-state title would be motion without information.
    window.title = "Enterprise SSO Bridge"
    window.contentView = content
    window.delegate = self
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate()
  }

  /// State 3. The window grows around the webview it was handed, and the footer keeps
  /// the destination on screen, which is the only place it survives once the provider's
  /// page is up.
  func showAuthenticating(webView: NSView) {
    swapContent(to: authenticatingContentView(webView: webView), size: Self.handoffContentSize)
  }

  /// State 4. The Callback was recognized and stopped and the response is going out, so
  /// the same window says so rather than a second one appearing.
  func showReturningCallback() {
    footerLabel?.stringValue = copy.returningCallback
  }

  /// State 5. A Handoff that fails while the user is looking at it says what happened
  /// instead of vanishing.
  func showFailure() {
    footerLabel = nil
    let content = failureContentView()
    swapContent(
      to: content,
      size: NSSize(width: Self.panelWidth, height: content.fittingSize.height)
    )
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    onDismiss()
    return false
  }

  @objc private func approve() {
    onApprove()
  }

  @objc private func dismiss() {
    onDismiss()
  }

  private func swapContent(to content: NSView, size: NSSize) {
    guard let window else { return }
    window.contentView = content
    window.setContentSize(size)
    window.center()
  }

  private func approvalContentView() -> NSView {
    let heading = headingLabel(prompt.heading)
    let body = bodyLabel(prompt.body)

    let cancel = NSButton(title: "Cancel", target: self, action: #selector(dismiss))
    cancel.bezelStyle = .push
    cancel.keyEquivalent = "\u{1b}"

    let signIn = NSButton(title: "Sign In", target: self, action: #selector(approve))
    signIn.bezelStyle = .push
    signIn.keyEquivalent = "\r"

    return panel(heading: heading, body: body, buttons: [cancel, signIn])
  }

  private func failureContentView() -> NSView {
    let close = NSButton(title: "Close", target: self, action: #selector(dismiss))
    close.bezelStyle = .push
    close.keyEquivalent = "\r"

    return panel(
      heading: headingLabel(copy.failureHeading),
      body: bodyLabel(copy.failureBody),
      buttons: [close]
    )
  }

  private func authenticatingContentView(webView: NSView) -> NSView {
    let separator = NSBox()
    separator.boxType = .separator

    let stack = NSStackView(views: [webView, separator, footerView()])
    stack.orientation = .vertical
    stack.alignment = .width
    stack.spacing = 0
    stack.distribution = .fill
    // The webview takes whatever the footer does not, rather than the two negotiating.
    webView.setContentHuggingPriority(.defaultLow - 1, for: .vertical)
    return stack
  }

  private func footerView() -> NSView {
    let spinner = NSProgressIndicator()
    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.startAnimation(nil)

    let label = NSTextField(labelWithString: copy.authenticating)
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingTail
    footerLabel = label

    let cancel = NSButton(title: "Cancel", target: self, action: #selector(dismiss))
    cancel.bezelStyle = .push
    cancel.keyEquivalent = "\u{1b}"

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
    let row = NSStackView(views: [spinner, label, spacer, cancel])
    row.orientation = .horizontal
    row.spacing = 8
    row.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

    let footer = NSView()
    footer.addSubview(row)
    row.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      footer.heightAnchor.constraint(equalToConstant: Self.footerHeight),
      row.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
      row.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
      row.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
    ])
    return footer
  }

  /// Wrapping, and by character, because the Approval's heading names the Callback
  /// destination and a host long enough to overflow 540 pt would otherwise be clipped at
  /// the right edge. The clipped part is the end, which is exactly the part that
  /// distinguishes `trusted.example.com.<padding>.attacker.example` from the host the
  /// user expects, and the body does not repeat it. An Approval that hides where the
  /// response goes is not the control ADR 0002 describes.
  private func headingLabel(_ text: String) -> NSTextField {
    let heading = NSTextField(wrappingLabelWithString: text)
    heading.font = .boldSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize)
    heading.lineBreakMode = .byCharWrapping
    heading.preferredMaxLayoutWidth = Self.panelWidth - Self.margin * 2
    return heading
  }

  private func bodyLabel(_ text: String) -> NSTextField {
    let body = NSTextField(wrappingLabelWithString: text)
    body.textColor = .secondaryLabelColor
    body.preferredMaxLayoutWidth = Self.panelWidth - Self.margin * 2
    return body
  }

  /// The 540 pt panel both question-shaped states use.
  private func panel(heading: NSView, body: NSView, buttons: [NSView]) -> NSView {
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
    let buttonRow = NSStackView(views: [spacer] + buttons)
    buttonRow.orientation = .horizontal
    buttonRow.spacing = 12

    let stack = NSStackView(views: [heading, body, buttonRow])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.setCustomSpacing(20, after: body)
    stack.edgeInsets = NSEdgeInsets(
      top: Self.margin, left: Self.margin, bottom: 20, right: Self.margin)
    stack.widthAnchor.constraint(equalToConstant: Self.panelWidth).isActive = true
    buttonRow.widthAnchor.constraint(
      equalTo: stack.widthAnchor, constant: -Self.margin * 2
    ).isActive = true
    return stack
  }
}
