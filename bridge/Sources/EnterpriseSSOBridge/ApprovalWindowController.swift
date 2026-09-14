import AppKit
import BridgeCore

/// The Approval on screen: a 540 pt panel that reads as a question, with Sign In as the
/// default button and two ways to say no that are the same way.
///
/// It renders an `ApprovalPrompt` and reports which button the user pressed. It decides
/// nothing about what either answer means, which is what keeps the copy and the ordering
/// rule testable without AppKit.
@MainActor
final class ApprovalWindowController: NSObject, NSWindowDelegate {
  /// The prototype settled this, and the two states share it. Plate:
  /// https://agentdrop.gucu.org/a/0mgxOqOaPuNPlfwTgl0vo0/bridge-window-states.png
  static let width: CGFloat = 540
  private static let margin: CGFloat = 24

  private let prompt: ApprovalPrompt
  private let onApprove: () -> Void
  private let onDecline: () -> Void
  private(set) var window: NSWindow?

  init(prompt: ApprovalPrompt, onApprove: @escaping () -> Void, onDecline: @escaping () -> Void) {
    self.prompt = prompt
    self.onApprove = onApprove
    self.onDecline = onDecline
  }

  /// Shows the panel and takes focus. The user clicked the toolbar action a second
  /// earlier, so the focus change is expected, and a prompt nobody sees is not an
  /// Approval.
  func present() {
    let content = contentView()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: Self.width, height: content.fittingSize.height),
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

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    onDecline()
    return false
  }

  @objc private func approve() {
    onApprove()
  }

  @objc private func decline() {
    onDecline()
  }

  private func contentView() -> NSView {
    let heading = NSTextField(labelWithString: prompt.heading)
    heading.font = .boldSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize)

    let body = NSTextField(wrappingLabelWithString: prompt.body)
    body.textColor = .secondaryLabelColor
    body.preferredMaxLayoutWidth = Self.width - Self.margin * 2

    let cancel = NSButton(title: "Cancel", target: self, action: #selector(decline))
    cancel.bezelStyle = .push
    cancel.keyEquivalent = "\u{1b}"

    let signIn = NSButton(title: "Sign In", target: self, action: #selector(approve))
    signIn.bezelStyle = .push
    signIn.keyEquivalent = "\r"

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
    let buttons = NSStackView(views: [spacer, cancel, signIn])
    buttons.orientation = .horizontal
    buttons.spacing = 12

    let stack = NSStackView(views: [heading, body, buttons])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.setCustomSpacing(20, after: body)
    stack.edgeInsets = NSEdgeInsets(
      top: Self.margin, left: Self.margin, bottom: 20, right: Self.margin)
    stack.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
    buttons.widthAnchor.constraint(
      equalTo: stack.widthAnchor, constant: -Self.margin * 2
    ).isActive = true
    return stack
  }
}
