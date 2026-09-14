import Foundation

/// What the Bridge does with one main-frame navigation, and the whole of the judgment
/// behind it.
///
/// The navigation delegate turns a `WKNavigationAction` into a `CandidateNavigation`
/// and does what this says. Everything that decides anything is here, as a function of
/// values, so the delegate is left with WebKit mechanics and this is testable without a
/// webview. The order is the one docs/spec/callback-recognition.md sets out: the core's
/// own checks first, the adapter's rules only about a candidate they admit.
public enum CallbackCapture {
  public enum Verdict: Equatable, Sendable {
    /// The Callback. Its navigation is not allowed to complete: the Application
    /// receives it from the original browser, not from the `WKWebView`.
    case capture(Callback)
    /// Anything else, including a navigation the core refused to consider. Refusing to
    /// call something a Callback is not a reason to stop it.
    case proceed
  }

  public static func verdict(
    for candidate: CandidateNavigation,
    plan: HandoffPlan,
    identityProviderHost: String
  ) -> Verdict {
    if let refusal = CallbackEligibility.refusal(
      candidate, identityProviderHost: identityProviderHost)
    {
      log(refusal, host: candidate.url.host())
      return .proceed
    }
    guard plan.recognizes(candidate) else { return .proceed }

    switch candidate.method {
    case .get:
      return .capture(.get(url: candidate.url))
    case .post:
      return .capture(.post(url: candidate.url, fields: candidate.fields))
    }
  }

  /// A host, never a URL. An unencrypted or credentialed target is worth a notice line
  /// because it is the one refusal a user might later ask about; a navigation still at
  /// the provider is most of a normal sign-in and would drown it.
  private static func log(_ refusal: CallbackEligibility.Refusal, host: String?) {
    guard refusal != .stillAtTheProvider, let host else {
      BridgeLog.navigation.debug(
        "allowed a navigation that is no candidate: \(refusal.rawValue, privacy: .public)"
      )
      return
    }
    BridgeLog.navigation.notice(
      "allowed \(host, privacy: .public): \(refusal.rawValue, privacy: .public)"
    )
  }
}
