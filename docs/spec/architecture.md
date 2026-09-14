# Architecture

## The problem

macOS authenticates a user to Entra through the Enterprise SSO extension, using credentials and keys held by the platform. Safari and native apps reach that path. A third-party browser cannot: the platform SSO extension answers `get_sso_cookies` only to callers Microsoft's own allowlist recognizes, so Helium and Zen have no way to obtain a Primary Refresh Token or the cookies derived from it, and their users type a password and answer an MFA prompt on every sign-in.

The Bridge is a native macOS application that can reach that path. It performs the sign-in on the browser's behalf inside a `WKWebView`, captures the Callback the identity provider produces, and hands it back to the browser, which delivers it to the Application in the tab where the user started.

## The parts

**Bridge.** A macOS application at `/Applications/Enterprise SSO Bridge.app`, ad-hoc signed, no resident process. The browser spawns it per Handoff over native-messaging stdio, and it exits after one terminal response. It owns caller authentication, the Approval, the `WKWebView`, Callback capture, and the Identity provider adapter.

**Extension.** One TypeScript source tree producing a Chromium build and a Gecko build. It observes the Sign-in request, offers the toolbar action, speaks the protocol to the Bridge, and drives the original tab to the Callback destination. It owns all user-facing copy on the browser side.

**Identity provider adapter.** A Bridge-owned definition of one identity provider: its entry origins, what it can say about a Sign-in request's destination, and the rules recognizing a Callback. Entra is the only implementation in v1. See [identity-provider-adapter.md](identity-provider-adapter.md).

## One Handoff, end to end

1. The user is on the Application's login page and is redirected to `login.microsoftonline.com`. The Extension's `webRequest` listener sees that main-frame navigation and stores it as the Sign-in request, keyed by tab: the URL, the method, and for a POST the form fields as `[name, value]` pairs.
2. The user clicks the toolbar action. The Extension checks the active tab's origin against the generated entry origins, reads the stored capture (bounded to ten minutes), and calls `connectNative`.
3. The browser spawns the Bridge. Before reading a byte of stdin, the Bridge validates its parent's audit token against each Allowed browser's designated requirement. A parent that is not one exits non-zero having written nothing. See [caller-authentication.md](caller-authentication.md).
4. The Extension sends one request frame carrying the Sign-in request. See [protocol.md](protocol.md).
5. The Bridge selects the adapter whose entry origins match the request's origin and asks it for a Handoff plan. No plan means nothing replayable, answered as `unsupported_request`, and the Bridge exits before any window exists.
6. The Bridge shows the Approval: its own focused window naming the identity provider, the requesting browser, and the Callback destination the adapter derived from the Sign-in request itself. No `WKWebView` exists yet. Declining, or closing the window, sends `declined`.
7. On approval the window grows to hold a `WKWebView`, which replays the Sign-in request verbatim. The platform SSO extension satisfies the authentication without a password prompt in the common case.
8. The Bridge's navigation delegate inspects each main-frame navigation. The first one the adapter recognizes as a Callback is captured, including its POST body, and the navigation is not allowed to complete. See [callback-recognition.md](callback-recognition.md).
9. The Bridge checks the encoded response against the 1 MiB native-messaging cap, sends it, and exits.
10. The Extension re-validates the returned URL (HTTPS, no embedded credentials), then either navigates the original tab (GET) or loads the Relay page in it to submit the form (POST). The Application receives the Callback in the tab where the user started.

## Trust model

The Bridge does not trust the browser's contents. Caller authentication proves the parent process is an Allowed browser and explicitly does not prove anything about what runs inside it: a hostile extension can call `connectNative` with any Sign-in request it likes, and platform SSO is built not to prompt. The Approval is what stands between that and a silent token minter for arbitrary relying parties, which is why it is required for every Handoff, why the destination it shows is derived from the Sign-in request rather than asserted alongside it, and why nothing is loaded before it. See ADR 0001 and ADR 0002.

The Extension does not fully trust the Bridge either. It re-validates the Callback URL before navigating, because it is the party that actually drives the user's tab and a swapped binary should not be able to point that tab at `http://` or a credentialed URL.

Two gaps stay open in v1, both recorded in ADR 0001: a launcher that `exec`s a browser binary after spawning the Bridge, and code injected into a legitimately signed browser.

## Logging invariant

The Bridge logs to `os_log` and writes nothing but protocol frames to stdout. Log lines carry hosts, methods, phases, error codes, and the matched browser's name. They never carry URLs, query strings, bodies, form fields, tokens, or assertions.

The protocol's `error` responses may carry a `detail` string. That string is an unlocalized diagnostic for the console, never shown to the user, and it obeys the same rule: an `OSStatus`, an `NSURLError` domain and code, or a phase name, not the data that failed.
