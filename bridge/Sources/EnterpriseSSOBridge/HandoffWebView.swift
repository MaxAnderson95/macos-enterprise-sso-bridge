import BridgeCore
import Foundation
import WebKit

/// The webview's half of a Handoff: replay the Sign-in request into it, watch its
/// main-frame navigations, and report the first Callback or the failure that ends it.
///
/// All the WebKit mechanics and none of the judgment. Turning a `WKNavigationAction`
/// into a `(url, method, fields)` value is this type's work; deciding what that value
/// is belongs to `CallbackCapture`, which is why the recognition rules are testable
/// without a webview or a network.
@MainActor
final class HandoffWebView: NSObject, WKNavigationDelegate {
  enum Outcome {
    /// Recognized, and its navigation cancelled: the Application receives its Callback
    /// from the original browser, not from here.
    case captured(Callback)
    /// The `WKWebView` could not load, with the underlying error for `detail`.
    case failed(detail: String)
  }

  /// A `WKWebView` configured for the only job it has. The persistent default data
  /// store is the one that matters: the Enterprise SSO extension's credential and the
  /// cookies derived from it live in the shared store, and a non-persistent store would
  /// leave the Bridge as just another anonymous browser. Nothing overrides the user
  /// agent, because Entra reads it and the SSO extension appends to it.
  static func makeWebView() -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    return WKWebView(frame: .zero, configuration: configuration)
  }

  private let webView: WKWebView
  private let request: SignInRequest
  private let plan: HandoffPlan
  private let identityProviderHost: String
  private let onOutcome: (Outcome) -> Void
  private var finished = false

  init(
    webView: WKWebView,
    request: SignInRequest,
    plan: HandoffPlan,
    onOutcome: @escaping (Outcome) -> Void
  ) {
    self.webView = webView
    self.request = request
    self.plan = plan
    // The adapter claimed this origin, so the request's own host is the provider's.
    self.identityProviderHost = request.url.host() ?? ""
    self.onOutcome = onOutcome
  }

  /// Replays the Sign-in request exactly as captured.
  func start() {
    webView.navigationDelegate = self
    switch request {
    case .get(let url):
      webView.load(URLRequest(url: url))
    case .post(let url, let fields):
      // A form submission rather than a `URLRequest` with an `httpBody`, for the
      // reasons in `FormSubmissionDocument`. No base URL: the action is absolute, so
      // there is nothing to resolve against, and a base would give this document an
      // origin it has no claim to.
      webView.loadHTMLString(
        FormSubmissionDocument.html(action: url, fields: fields), baseURL: nil)
    }
    BridgeLog.navigation.info("replaying \(self.request.logSummary, privacy: .public)")
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
  ) {
    guard !finished, navigationAction.targetFrame?.isMainFrame == true,
      let url = navigationAction.request.url,
      let method = navigationAction.request.httpMethod.flatMap(HTTPMethod.init(rawValue:))
    else {
      decisionHandler(.allow)
      return
    }

    guard method == .post else {
      decide(CandidateNavigation(url: url, method: method), decisionHandler)
      return
    }
    // A POST is decided on its fields, so the extraction has to finish before the
    // verdict. Deferring the decision is what lets path 2 read the submitting form:
    // until this handler answers, the document in the webview is still the one whose
    // form is being submitted.
    Task {
      let fields = await self.extractFields(from: navigationAction, target: url, in: webView)
      self.decide(CandidateNavigation(url: url, method: method, fields: fields), decisionHandler)
    }
  }

  /// The two paths from docs/spec/callback-recognition.md, in order, and the one line
  /// that says which of them answered. That line is what the first end-to-end run
  /// against a real tenant reads to decide which path to delete, so it names the path
  /// and the number of fields and never a name or a value.
  private func extractFields(
    from navigationAction: WKNavigationAction,
    target: URL,
    in webView: WKWebView
  ) async -> [FormField] {
    let request = navigationAction.request
    if let extraction = CallbackBody.fromHTTPBody(
      request.httpBody, contentType: request.value(forHTTPHeaderField: "Content-Type"))
    {
      BridgeLog.navigation.info(
        "callback body source: \(extraction.logSummary, privacy: .public)")
      return extraction.fields
    }

    // The DOM fallback is for a body WebKit did not keep, not for one it is sending
    // under another media type. A submit button's `formenctype` changes what goes on the
    // wire without changing the `form.enctype` the fallback reads, so consulting the
    // document here would let a multipart POST be captured after the request already
    // said it is not urlencoded.
    let contentType = request.value(forHTTPHeaderField: "Content-Type")
    if CallbackBody.declaresOtherMediaType(contentType) {
      BridgeLog.navigation.info("callback body source: none, request is not urlencoded")
      return []
    }

    let script = CallbackBody.matchingFormScript(action: target)
    let answer = try? await webView.evaluateJavaScript(script)
    guard let extraction = CallbackBody.fromDOMForm(answer as? String) else {
      BridgeLog.navigation.info(
        "callback body source: none, no urlencoded httpBody and no matching DOM form")
      return []
    }
    BridgeLog.navigation.info("callback body source: \(extraction.logSummary, privacy: .public)")
    return extraction.fields
  }

  private func decide(
    _ candidate: CandidateNavigation,
    _ decisionHandler: @MainActor @Sendable (WKNavigationActionPolicy) -> Void
  ) {
    guard !finished else {
      decisionHandler(.allow)
      return
    }
    switch CallbackCapture.verdict(
      for: candidate, plan: plan, identityProviderHost: identityProviderHost)
    {
    case .proceed:
      decisionHandler(.allow)
    case .capture(let callback):
      finished = true
      decisionHandler(.cancel)
      let summary = "\(callback.method.rawValue) \(callback.url.host() ?? "?")"
      BridgeLog.navigation.info("captured the callback: \(summary, privacy: .public)")
      onOutcome(.captured(callback))
    }
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: any Error
  ) {
    fail(error)
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: any Error
  ) {
    fail(error)
  }

  /// Cancelling the Callback's navigation is how a Handoff succeeds, and WebKit reports
  /// that cancellation as a load failure, so the successful case arrives here too.
  /// Treating it as `navigation_failed` would report a failure the user never had.
  private func fail(_ error: any Error) {
    let error = error as NSError
    guard !finished, !Self.isCancellation(error) else { return }
    finished = true
    let detail = "\(error.domain) \(error.code)"
    BridgeLog.navigation.error("the webview could not load: \(detail, privacy: .public)")
    onOutcome(.failed(detail: detail))
  }

  private static func isCancellation(_ error: NSError) -> Bool {
    switch error.domain {
    case NSURLErrorDomain:
      return error.code == NSURLErrorCancelled
    case "WebKitErrorDomain":
      // WebKitErrorFrameLoadInterruptedByPolicyChange, which is what a `.cancel` from
      // the policy decision produces. The constant is not exposed to Swift.
      return error.code == 102
    default:
      return false
    }
  }
}
