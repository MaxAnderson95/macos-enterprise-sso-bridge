import AppKit
import BridgeCore

/// A placeholder window so the shipped bundle launches instead of crashing.
/// The Approval window and the Handoff it gates arrive in later work.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 160),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Enterprise SSO Bridge"
    window.contentView = placeholderContentView()
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  private func placeholderContentView() -> NSView {
    let heading = NSTextField(labelWithString: "Enterprise SSO Bridge")
    heading.font = .preferredFont(forTextStyle: .title2)

    let body = NSTextField(
      wrappingLabelWithString:
        "The Bridge runs when a browser needs it. Version \(BridgeVersion.current)."
    )
    body.textColor = .secondaryLabelColor

    let stack = NSStackView(views: [heading, body])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
    return stack
  }
}
