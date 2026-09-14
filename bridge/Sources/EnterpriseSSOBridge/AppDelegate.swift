import AppKit
import BridgeCore

/// The window state for a user launch: the Bridge was double-clicked, or opened from the
/// Dock or launchd, so there is no Sign-in request and nothing to approve. It says what
/// the app is for and offers a way out. The Approval panel is a different window and
/// lives in `ApprovalWindowController`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private static let readme = URL(
    string: "https://github.com/MaxAnderson95/macos-enterprise-sso-bridge#readme"
  )!

  private var window: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 200),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Enterprise SSO Bridge"
    window.contentView = userLaunchContentView()
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  @objc private func openReadme() {
    NSWorkspace.shared.open(Self.readme)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func userLaunchContentView() -> NSView {
    let heading = NSTextField(labelWithString: "Enterprise SSO Bridge")
    heading.font = .preferredFont(forTextStyle: .title2)

    let body = NSTextField(
      wrappingLabelWithString:
        "There is nothing to do here. The Bridge runs when a browser needs it, shows what "
        + "it is about to sign you into, and quits again."
    )
    body.textColor = .secondaryLabelColor

    let version = NSTextField(labelWithString: "Version \(BridgeVersion.current)")
    version.textColor = .secondaryLabelColor
    version.font = .preferredFont(forTextStyle: .subheadline)

    let readme = NSButton(
      title: "Read the documentation", target: self, action: #selector(openReadme))
    readme.bezelStyle = .accessoryBarAction

    let quit = NSButton(title: "Quit", target: self, action: #selector(quit))
    quit.bezelStyle = .push
    quit.keyEquivalent = "\r"

    let buttons = NSStackView(views: [readme, NSView(), quit])
    buttons.orientation = .horizontal
    buttons.distribution = .fill

    let stack = NSStackView(views: [heading, body, version, buttons])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
    buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
    return stack
  }
}
