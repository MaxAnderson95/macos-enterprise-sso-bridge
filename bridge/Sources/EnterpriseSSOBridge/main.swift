import AppKit
import BridgeCore
import Foundation
import WebKit

@MainActor
func runHandoff(caller: AllowedBrowser) -> Never {
  let channel = ProtocolChannel.standardIO()
  let received: ProtocolChannel.ReceivedRequest
  do {
    received = try channel.receiveRequest()
  } catch {
    BridgeLog.wire.error("broken framing, exiting without a response: \(error, privacy: .public)")
    exit(1)
  }

  let request: SignInRequest
  switch received {
  case .answer(let response):
    send(response, over: channel)
  case .request(let received):
    request = received
  }

  guard let plan = IdentityProviders.plan(for: request) else {
    // No window has been shown and none will be: nothing replayable is answered before
    // the user is ever interrupted.
    send(.error(.unsupportedRequest, detail: nil), over: channel)
  }

  let prompt = ApprovalPrompt(plan: plan, request: request, caller: caller)
  // The one place in the Bridge that constructs a `WKWebView`, and it is a closure
  // `Handoff.approve()` alone can reach. That is what makes ADR 0002's ordering a
  // property of the code rather than of this file's statement order.
  let handoff = Handoff(prompt: prompt, makeWebView: HandoffWebView.makeWebView)
  runHandoffWindow(handoff: handoff, request: request, plan: plan, channel: channel)
}

@MainActor
func runHandoffWindow(
  handoff: Handoff<WKWebView>,
  request: SignInRequest,
  plan: HandoffPlan,
  channel: ProtocolChannel
) -> Never {
  let application = NSApplication.shared
  let delegate = HandoffAppDelegate(
    handoff: handoff, request: request, plan: plan, channel: channel)
  application.setActivationPolicy(.regular)
  application.delegate = delegate
  application.run()
  // The delegate answers and exits from whichever way the Handoff ended, so reaching
  // here means the run loop ended with nothing said.
  send(.error(.internalFailure, detail: "the window closed without an answer"), over: channel)
}

func send(_ response: BridgeResponse, over channel: ProtocolChannel) -> Never {
  do {
    try channel.send(response)
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
