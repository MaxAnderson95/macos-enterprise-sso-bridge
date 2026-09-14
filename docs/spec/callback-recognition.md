# Callback recognition

Settled in [issue #6](https://github.com/MaxAnderson95/macos-enterprise-sso-bridge/issues/6), adopting the v0.4.0 spike's rules with `SAMLart` dropped and the body rule stated positively. No ADR; this sits next to the protocol schema.

## The rules

A candidate Callback is a main-frame navigation whose target is HTTPS, carries no embedded credentials, and whose host is not the identity provider's.

It is a Callback when any of these holds:

- it matches the Sign-in request's `redirect_uri` on scheme, host, port, and path; or
- it carries a `SAMLResponse` query parameter; or
- it is a POST whose `application/x-www-form-urlencoded` body has a nonempty `SAMLResponse`, or, at the `redirect_uri`, a nonempty `code`, `id_token`, or `error`.

The first candidate that matches ends the Handoff. The navigation is not allowed to complete: the Application receives its Callback from the original browser, not from the `WKWebView`.

## Boundaries

**`SAMLart` is not recognized.** Entra does not support HTTP-Artifact binding at all. Microsoft's own answer on the B2C question is that Entra ID and Azure AD B2C support only HTTP-POST and HTTP-Redirect bindings, and `AADSTS75003` is what an application gets for requesting any other response binding. Recognizing `SAMLart` would be untestable dead code for the only identity provider v1 implements.

The `SAMLResponse` query parameter stays. It is nearly as unlikely from Entra, but it is a field name already parsed and costs one set member, so an odd redirect-bound response is not a silent dead end.

**Only urlencoded bodies are recognized.** Both bindings that matter, SAML 2.0 HTTP POST and OAuth `form_post`, submit ordinary HTML forms, which default to urlencoded. A multipart or JSON POST leaving the provider is not a Callback under anything Entra implements, so it is allowed to proceed and is never captured. This is a positive rule, not the spike's `multipart/` exclusion.

**Non-HTTPS and credentialed targets are never Callbacks, and the Bridge lets those navigations proceed.** It captures Callbacks; it is not a security proxy for the provider's redirect chain, and cancelling mid-flow navigations would break legitimate flows without changing what is handed back. The host is logged at notice level.

**Nothing replayable is the Bridge's call.** A Sign-in request with neither a `redirect_uri` nor a `SAMLRequest` gets `{"result": "error", "code": "unsupported_request"}`. Recognition knowledge stays in the adapter rather than being half-duplicated as a path heuristic in the Extension, which is the untrusted process. The cost is one process spawn to learn the answer; no Approval prompt appears, because the plan fails before the window is shown.

## Body extraction

`WKWebView` commonly hands over a form submission with `httpBody` nil. So the Bridge tries two paths in order:

1. Parse `httpBody` as urlencoded.
2. Fall back to the DOM: find the form whose action matches the navigation target and read its `FormData`.

Both paths stay in v1, and the `os_log` line naming which one produced the fields stays with them. Nobody has evidence about which path real Entra POST Callbacks take, and the DOM fallback is what makes SAML POST Callbacks work at all when `httpBody` is nil. The first end-to-end run against a real tenant answers it, and the losing path is deleted then.

## Adapter versus core

The Bridge core owns the navigation delegate and all WebKit mechanics: the main-frame, HTTPS, and credential checks, body extraction, the size check, and response assembly. It then asks the adapter a value-shaped question: given this Sign-in request and this candidate `(url, method, fields)`, is this a Callback?

The adapter owns the entry origins, `redirect_uri` extraction and matching, and the field names `SAMLResponse`, `code`, `id_token`, and `error`. It never sees a `WKNavigationAction`, which is what keeps these rules testable without a webview.
