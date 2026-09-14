import Foundation
import Testing

@testable import BridgeCore

/// A stand-in for the `WKWebView` issue #25 will create, which exists only to be
/// counted. The count lives on the factory rather than on the `Handoff`, so the test
/// asks the question the rule is written in: was a webview *made*, and when?
private final class WebViewSpy {
  private(set) var creations = 0

  func make() -> Made {
    creations += 1
    return Made()
  }

  struct Made {}
}

private let prompt = ApprovalPrompt(
  destinationHost: "app.example.com",
  providerHost: "login.microsoftonline.com",
  browserName: "Helium"
)

/// ADR 0002's ordering, pinned here rather than in prose: the Approval is what stands
/// between a hostile extension and a silent token minter, and it only stands there if
/// nothing has loaded by the time it is on screen.
@Suite("Nothing is created before the Approval")
struct ApprovalOrderingTests {
  @Test("Everything the Approval does before the user answers makes no webview")
  func nothingBeforeApproval() {
    let spy = WebViewSpy()
    let handoff = Handoff(prompt: prompt, makeWebView: spy.make)

    // The whole pre-approval phase: the Handoff exists, and the window has read
    // everything it renders. Moving webview creation into the state machine's setup,
    // or into the prompt, fails here.
    #expect(spy.creations == 0)
    #expect(handoff.phase == .awaitingApproval)
    #expect(handoff.prompt.heading == "Sign in to app.example.com?")
    #expect(!handoff.prompt.body.isEmpty)
    #expect(spy.creations == 0)
  }

  @Test("Declining ends the Handoff having made nothing")
  func declineMakesNothing() {
    let spy = WebViewSpy()
    let handoff = Handoff(prompt: prompt, makeWebView: spy.make)

    #expect(handoff.decline() == .declined)
    #expect(spy.creations == 0)
    #expect(handoff.phase == .awaitingApproval)
  }

  @Test("The Approval makes exactly one webview")
  func exactlyOneAfterApproval() {
    let spy = WebViewSpy()
    let handoff = Handoff(prompt: prompt, makeWebView: spy.make)

    handoff.approve()
    #expect(spy.creations == 1)
    #expect(handoff.phase == .authenticating)
  }

  /// A window cannot easily press Sign In twice, but "exactly once" is the claim, so
  /// the second Approval has to be the one that is refused rather than the one that
  /// quietly starts a second load.
  @Test("A second Approval makes no second webview")
  func approvingTwice() {
    let spy = WebViewSpy()
    let handoff = Handoff(prompt: prompt, makeWebView: spy.make)

    handoff.approve()
    handoff.approve()
    #expect(spy.creations == 1)
  }

  /// Declining after the Approval is the same call and the same response; only the
  /// phase in the log differs, which is the line docs/spec/bridge.md asks for.
  @Test("Declining after approval is still one decline, from the later phase")
  func declineAfterApproval() {
    let spy = WebViewSpy()
    let handoff = Handoff(prompt: prompt, makeWebView: spy.make)

    handoff.approve()
    #expect(handoff.decline() == .declined)
    #expect(handoff.phase == .authenticating)
  }
}

/// What the panel is allowed to say. The two states are one optional apart, and the
/// values behind them all come from the Bridge's own work rather than from the frame.
@Suite("What the Approval says")
struct ApprovalPromptTests {
  private let entra = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!

  private func prompt(destination: String?) -> ApprovalPrompt {
    ApprovalPrompt(
      plan: HandoffPlan(
        destination: destination.map { URL(string: $0)! },
        recognizes: { _ in false }
      ),
      request: .get(url: entra),
      caller: .helium
    )
  }

  @Test("A derived destination is the question the heading asks")
  func withDestination() {
    let prompt = prompt(destination: "https://app.example.com/signin-oidc")
    #expect(prompt.heading == "Sign in to app.example.com?")
    #expect(
      prompt.body == "Helium asked to sign in through login.microsoftonline.com using "
        + "this Mac's work account. Nothing has loaded yet."
    )
  }

  @Test("A plan with no destination says so instead of guessing")
  func withoutDestination() {
    let prompt = prompt(destination: nil)
    #expect(prompt.heading == "Sign in through login.microsoftonline.com?")
    #expect(
      prompt.body == "Helium asked for a sign-in, but the Bridge cannot tell which site "
        + "will receive it. Continue only if you started this sign-in yourself a moment ago."
    )
  }

  /// The prompt takes the browser from caller authentication's match and the provider
  /// from the request's own origin, both of which the Bridge established. There is
  /// nowhere in this type for a name the Extension asserted to arrive.
  @Test("Only the matched browser's own name reaches the prompt")
  func browserName() {
    let named = prompt(destination: "https://app.example.com/c")
    #expect(named.browserName == AllowedBrowser.helium.displayName)
    #expect(prompt(destination: nil).providerHost == "login.microsoftonline.com")
  }
}
