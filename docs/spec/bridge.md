# The Bridge

A macOS 26 application, Swift and AppKit, ad-hoc signed, spawned per Handoff and gone again. No resident process, no menu bar item, no login item.

## Lifecycle

1. **Authenticate the Caller.** `try CallerAuthentication.verify() -> AllowedBrowser` at the top of `main`, before `NSApplication` and before a byte of stdin. See [caller-authentication.md](caller-authentication.md).
2. **Read one request frame.** Length prefix, body, decode. Broken framing exits non-zero without writing; a parseable frame that is not a valid request answers `malformed_request`. See [protocol.md](protocol.md).
3. **Plan the Handoff.** Match the request's origin against each adapter's entry origins, then ask the adapter for a plan. No matching adapter, or no plan, answers `unsupported_request` and exits, with no window ever shown.
4. **Ask for Approval.** Show the window. Nothing is loaded and no `WKWebView` exists until the user confirms. Declining or closing answers `declined`.
5. **Replay.** Create the `WKWebView`, grow the window, and replay the Sign-in request verbatim: a GET as a plain request, a POST as a form submission carrying the captured fields in order.
6. **Capture the Callback.** The navigation delegate inspects each main-frame navigation and asks the plan's `recognizes` closure. See [callback-recognition.md](callback-recognition.md).
7. **Answer and exit.** Assemble the response, check its encoded size against the 1 MiB cap, write one frame, terminate.

Any termination path sends a terminal response first, including the user closing the window mid-navigation.

## The window

Settled by the prototype in [issue #10](https://github.com/MaxAnderson95/macos-enterprise-sso-bridge/issues/10). Plate: https://agentdrop.gucu.org/a/0mgxOqOaPuNPlfwTgl0vo0/bridge-window-states.png

Two shapes. The Approval is a 540 pt panel that reads as a question. On approval the window grows to 900 x 520 to hold the `WKWebView`, and that resize is the visible signal that the Handoff started. The alternative, a single fixed 900 x 520 window with a prompt floating in the middle, reads as a page rather than a decision.

The title is fixed: "Enterprise SSO Bridge". The body already carries the destination and the requesting browser, so a per-state title would be motion without information. The window has no menu bar beyond the system minimum.

### States

1. **Waiting for approval.** The only thing on screen before anything loads. The heading names the Callback destination derived from the Sign-in request; the body names the identity provider and the requesting browser, taken from the `AllowedBrowser` caller authentication already matched. Sign In is the default button. Cancel and the close button both produce `declined`.
2. **Waiting for approval, destination undeterminable.** The same panel when the adapter returns a plan whose `destination` is nil. It says so plainly rather than guessing, and leans on recency: the user clicked the toolbar action a second ago, so an unexpected prompt is the signal to cancel.
3. **Authenticating.** The `WKWebView` carries the real Entra page. A footer keeps the destination visible, which is the only place it remains on screen once the provider's page is up, and offers Cancel. Cancel and closing the window are the same `declined` path.
4. **Returning the Callback.** The same window with the footer text swapped, usually on screen for well under a second. There is no separate confirmation window.
5. **Failure.** Shown in the window with a Close button, so a Handoff that fails while the user is looking at it says what happened instead of vanishing. The Extension's badge carries its own copy for when attention has moved back to the tab. A rejected Caller still shows nothing at all.
6. **Opened from Finder.** The user-launch carve-out: a window explaining that the Bridge runs when a browser needs it, showing the installed version, linking to the README, and offering Quit.

### Focus

The Bridge activates and takes focus when the prompt appears. The user clicked the toolbar action a second earlier, so the focus change is expected, and a prompt nobody sees is not an Approval.

## Approval

Required for every Handoff. Recorded as [ADR 0002](../adr/0002-user-approval-before-every-handoff.md), settled in [issue #4](https://github.com/MaxAnderson95/macos-enterprise-sso-bridge/issues/4).

**What it defends.** Caller authentication proves the parent is an Allowed browser and explicitly does not cover code running inside one. A hostile extension can call `connectNative` with any Sign-in request, and platform SSO is built not to prompt, so without an Approval the Bridge is a silent token minter for arbitrary relying parties. Entra's UI does not fill this gap, and neither does the toolbar click, which happens inside the process being distrusted.

**Why a button and not Touch ID.** Browser-resident code cannot press a button in another process's window without TCC accessibility rights, which is a far deeper compromise than the threat being defended against. LocalAuthentication was probed on this Mac from an ad-hoc-signed app on macOS 26: `deviceOwnerAuthentication` is available, but `deviceOwnerAuthenticationWithBiometrics` returns unavailable with `LAError -4` while docked with the lid closed, even though `biometryType` reports Touch ID. A biometric gate would therefore demand the account password on most Handoffs. Touch ID stays available as a later upgrade if the threat model grows; it is not built behind a flag now.

**What it shows.** The identity provider host and the Callback destination the adapter derived from the Sign-in request itself. Derived values are truthful by construction because they describe where the response actually goes. Anything the Extension asserts alongside the request is attacker-controlled and is not displayed, so no claimed Application name appears.

**Ordering.** Window and prompt first; no `WKWebView` is instantiated until the Approval is given. Nothing is loaded, so no web content and no process-level SSO surface exists while the prompt is up. This ordering is pinned by a test, not just by prose: see [testing.md](testing.md).

**Prompt spam is accepted.** A hostile extension can spawn Bridges in a loop, each taking focus with a prompt. No Handoff completes without a click, so this costs attention rather than tokens. Rate-limiting would need cross-process state that v1 has nowhere to keep, and would give an attacker a way to suppress a genuine prompt.

## Replay and capture

The Bridge core owns all the WebKit mechanics: the navigation delegate, the main-frame, HTTPS, and no-credentials checks, body extraction, the size check, and response assembly. The adapter sees values only. That split is what makes the recognition rules unit-testable without a webview, and it is specified in [identity-provider-adapter.md](identity-provider-adapter.md).

The Sign-in request is replayed exactly as captured. There is no provider-specific replay hook in v1: Entra needs none, and a hook with no caller is the extension point this project's rules say not to build.

## Logging

`os_log` only, and stdout carries protocol frames and nothing else.

Lines carry hosts, methods, phases, error codes, the matched browser's name, and for a rejected Caller the parent's bundle identifier, executable path, and `OSStatus`. They never carry URLs, query strings, bodies, form fields, tokens, or assertions.

Two lines exist specifically to answer open questions during implementation: which body-extraction path a real Entra POST Callback took (see [callback-recognition.md](callback-recognition.md)), and which phase a `declined` came from.
