import AppKit
import BridgeCore

/// The Approval's half of the process: put the panel up, and turn whichever answer the
/// user gives into the one terminal response this Handoff is allowed to send.
///
/// Both ways of saying no reach `terminate` through `Handoff.decline`, so Cancel, the
/// close button, and anything later that ends a Handoff early are one path with one log
/// line, not three that have to be kept in agreement.
@MainActor
final class ApprovalAppDelegate: NSObject, NSApplicationDelegate {
  private let handoff: Handoff<Void>
  private let channel: ProtocolChannel
  private var controller: ApprovalWindowController?

  init(handoff: Handoff<Void>, channel: ProtocolChannel) {
    self.handoff = handoff
    self.channel = channel
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = ApprovalWindowController(
      prompt: handoff.prompt,
      onApprove: { [weak self] in self?.approve() },
      onDecline: { [weak self] in self?.decline() }
    )
    controller.present()
    self.controller = controller
  }

  private func approve() {
    handoff.approve()
    // Temporary. The Approval is real and the webview seam is real, but the factory
    // this build passes in makes nothing, because replaying the Sign-in request is
    // issue #25. An approved Handoff therefore cannot be completed, and saying so is
    // the honest answer; `declined` here would report a refusal the user never gave.
    terminate(with: .error(.internalFailure, detail: "replay not implemented"))
  }

  private func decline() {
    terminate(with: handoff.decline())
  }

  private func terminate(with response: BridgeResponse) -> Never {
    do {
      try channel.send(response)
    } catch {
      BridgeLog.wire.error("could not write the terminal response: \(error, privacy: .public)")
      exit(1)
    }
    exit(0)
  }
}
