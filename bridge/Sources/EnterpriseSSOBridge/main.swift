import AppKit
import BridgeCore
import Foundation

func runHandoff(caller: AllowedBrowser) -> Never {
  let channel = ProtocolChannel.standardIO()
  let received: ProtocolChannel.ReceivedRequest
  do {
    received = try channel.receiveRequest()
  } catch {
    BridgeLog.wire.error("broken framing, exiting without a response: \(error, privacy: .public)")
    exit(1)
  }

  do {
    switch received {
    case .answer(let response):
      try channel.send(response)
    case .request:
      // Temporary. Planning the Handoff is issue #23, the Approval is #24, and the
      // replay is #25; until the first of those lands there is nothing to approve,
      // so the honest terminal response is the one the user would have given.
      BridgeLog.wire.info(
        "no Handoff pipeline on this build, answering declined to \(caller.displayName, privacy: .public)"
      )
      try channel.send(.declined)
    }
  } catch {
    BridgeLog.wire.error("could not write the terminal response: \(error, privacy: .public)")
    exit(1)
  }
  exit(0)
}

@MainActor
func runUserLaunchWindow() -> Never {
  let application = NSApplication.shared
  let delegate = AppDelegate()
  application.setActivationPolicy(.regular)
  application.delegate = delegate
  application.run()
  exit(0)
}

// The gate, above everything: no `NSApplication`, no stdin, nothing but this until it
// answers. See docs/spec/caller-authentication.md.
let caller: AllowedBrowser
do {
  caller = try CallerAuthentication.verify()
} catch CallerAuthenticationFailure.userLaunch {
  runUserLaunchWindow()
} catch {
  exit(1)
}

runHandoff(caller: caller)
