# Testing

Settled in [issue #13](https://github.com/MaxAnderson95/macos-enterprise-sso-bridge/issues/13).

One fact shapes all of it: caller authentication runs at the top of `main`, before a byte of stdin, so any harness that spawns the shipped binary from a shell is rejected by construction. A single script cannot be both the positive wire-format test and the negative caller-authentication test, because rejection is the only result it can ever get.

## No bypass

Nothing that skips caller authentication is ever compiled, including into a test-only target. There is no second binary whose purpose is defeating the gate, and no environment variable to discover in the shipped one.

The wire format is exercised in-process against a real `Pipe` through `BridgeCore`'s framing seam, which is the same code path the executable feeds from stdin.

## Frameworks

Bridge: Swift Testing, which the toolchain ships and SwiftPM runs with no added dependency. Parameterized cases suit the codec and recognition tables, and no UI test exists in v1, so XCTest buys nothing.

Extension: Vitest, which runs TypeScript directly and works whichever bundler is in use.

## Bridge unit tests, through `BridgeCore`

- Framing round-trips against a real `Pipe`, including split frames, short reads, an absurd length prefix, and EOF mid-frame, each asserting that broken framing writes nothing to stdout.
- Request decode, including a POST whose `fields` repeat a name.
- Response encode for all four shapes: `callback` GET, `callback` POST, `declined`, `error`.
- The 1 MiB pre-flight check, asserting that a response just over the cap becomes `callback_too_large` rather than a frame nobody can read.
- The Entra adapter's `plan`, parameterized over OIDC and SAML Sign-in requests: a derivable destination, a replayable request whose `destination` is nil, and a request with neither `redirect_uri` nor `SAMLRequest` returning nil.
- The returned plan's `recognizes` closure over a table of candidates: a `redirect_uri` match on scheme, host, port, and path; a `SAMLResponse` query parameter; a urlencoded POST body with each recognized field name; a multipart POST that is correctly not a Callback; a non-HTTPS target; a credentialed target.

## The Approval ordering test

The rule that no `WKWebView` exists before the Approval is pinned by a unit test, not by prose.

The Handoff state machine in `BridgeCore` takes a webview-factory closure. The test injects a spy and asserts the factory is never called before the Approval is given, and is called exactly once after.

## Extension unit tests

- The `webRequest` capture normalizing into a Sign-in request, including Chromium's `ArrayBuffer` form values decoded to strings and a form that repeats a field name.
- The response parse as a discriminated union, with an unknown `code` falling back to generic copy.
- The callback URL re-check rejecting `http:` and embedded credentials before any navigation.
- The `storage.session` consume-once behaviour, asserting that a second read finds nothing.

Both layers are pure functions over values, which is what the adapter and Relay page decisions were shaped for. No browser automation, and fakes only where a function genuinely needs a `browser.storage` surface.

## CI

On `macos-26`: `swift build`, `swift test`, the Extension's typecheck, lint, and Vitest run, the generated-constants drift check, and a packaging build producing the `.pkg`, `.crx`, and `.xpi`.

No coverage gate. A threshold on a project this size measures diligence in the wrong units.

## Local checks

A GitHub Actions runner has no Helium, no Zen, no Entra tenant, and no Enterprise SSO extension, so it can prove rejection of a shell parent but never acceptance of a real browser, which is the half that matters.

**Caller authentication, negative.** A shell script spawns the built `.app`'s executable directly, so the parent is the shell, and asserts a non-zero exit and empty stdout. This is ADR 0001's required test. The script keeps its assertions to exit code and stdout, since a shell script cannot observe whether a webview was instantiated.

**End-to-end Handoff.** A checked-in manual checklist at `docs/testing/acceptance.md` covering two browsers, three Callback shapes (OIDC GET redirect, OIDC `form_post`, SAML POST), and normal versus private windows, with the expected observable at each step.

It runs before each release tag, and after any change to capture, recognition, or the Relay page. Per pull request was rejected as a rule that a one-person project will skip and then trust anyway. Browser automation against a live tenant was rejected for v1: neither engine's native messaging plus a real Entra login automates cheaply, and it would put tenant credentials in the loop.

Results are not committed, since they would carry tenant and Application names that this repo deliberately keeps out.

## What the first end-to-end run settles

Which body path a real Entra POST Callback takes: urlencoded `httpBody`, or the DOM-form fallback. The `os_log` line naming the source is what answers it, and the losing path is deleted once it does.
