import AppKit
import BridgeCore
import Foundation

// Caller authentication belongs above everything in this file, before a byte of
// stdin is read and before `NSApplication` exists. It arrives with issue #21.

/// Native messaging hands the Bridge a pipe on stdin. A Finder launch hands it
/// `/dev/null`, which is a character device, so this tells the two apart well enough
/// to keep the user-launch window reachable on a branch where caller authentication
/// does not exist yet. Issue #21 replaces it: the `AllowedBrowser` match is the real
/// answer to "did a browser start me".
func stdinIsPipe() -> Bool {
  var status = stat()
  guard fstat(STDIN_FILENO, &status) == 0 else { return false }
  return (status.st_mode & S_IFMT) == S_IFIFO
}

func runHandoff() -> Never {
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
      BridgeLog.wire.info("no Handoff pipeline on this build, answering declined")
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

if stdinIsPipe() {
  runHandoff()
} else {
  runUserLaunchWindow()
}
