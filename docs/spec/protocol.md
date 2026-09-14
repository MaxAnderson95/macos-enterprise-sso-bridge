# Native-messaging protocol

Settled in [issue #5](https://github.com/MaxAnderson95/macos-enterprise-sso-bridge/issues/5). One request in, one terminal response out, then the Bridge exits. There is no ADR: this is a schema, and the `version` field is how it changes.

Framing is whatever the engines already do: a 32-bit native-endian length prefix followed by that many bytes of UTF-8 JSON, on stdin and stdout.

## Request

Extension to Bridge, exactly one message:

```json
{ "version": 1, "url": "https://login.microsoftonline.com/...", "method": "GET" }
```

```json
{ "version": 1, "url": "https://login.microsoftonline.com/...", "method": "POST", "fields": [["SAMLRequest", "..."], ["RelayState", "..."]] }
```

`method` is required. `fields` is present only for POST and is an array of `[name, value]` pairs rather than an object, because a form can repeat a name and an object would silently drop one. The Extension decodes Chromium's `ArrayBuffer` form values to strings before sending.

There is no Handoff identifier. One process serves one Handoff, so there is nothing to route.

## Response

Bridge to Extension, exactly one message, tagged on `result`:

```json
{ "result": "callback", "url": "https://app.example.com/sso/acs", "method": "GET" }
{ "result": "callback", "url": "https://app.example.com/sso/acs", "method": "POST", "fields": [["SAMLResponse", "..."], ["RelayState", "..."]] }
{ "result": "declined" }
{ "result": "error", "code": "navigation_failed", "detail": "NSURLErrorDomain -1003" }
```

A discriminated union, not a bag of optionals: a Swift enum with associated values on one side and a TypeScript discriminated union on the other, so neither side can build a half-populated response and both get exhaustiveness checking. The types are hand-written against this document on each side. Three message shapes do not justify a JSON Schema and two generators in a build that is SwiftPM plus a bundler; a structural mismatch fails loudly at the first message, which is the opposite of the silent-failure risk that makes the entry origins generated (see [build.md](build.md)).

## Error codes

A closed set:

| Code | Meaning |
| --- | --- |
| `unsupported_version` | The Bridge does not implement the request's `version`. Carries `bridgeVersion` as an integer. |
| `malformed_request` | The frame arrived and parsed as JSON, but is not a valid request. |
| `unsupported_request` | Nothing in the Sign-in request is replayable: the adapter returned no plan. |
| `callback_too_large` | The assembled Callback exceeds the host-to-browser cap. |
| `navigation_failed` | The `WKWebView` failed to load, with the underlying error in `detail`. |
| `internal` | Anything else the Bridge cannot complete. |

The Bridge sends the code and an optional `detail`. All user-facing copy lives in the Extension, next to the badge and title it sets, and an unrecognized code falls back to generic copy so an older Extension survives a newer Bridge. The copy for each code is in [extension.md](extension.md).

## Version skew

The Extension sends `version: 1`. A Bridge that does not implement that version replies `{"result": "error", "code": "unsupported_version", "bridgeVersion": N}` and exits, so the Extension can say "install the matching release of both" instead of showing a parse failure. The field is an integer, bumped only on a breaking change.

This matters because the two halves are installed by hand and independently: nothing stops a new `.pkg` from meeting last month's extension.

## Size limit

Both engines cap a host-to-browser message at exactly 1 MiB: Chromium's `kMaximumNativeMessageSize` (`native_message_process_host.cc:45`), which logs and closes the port with an IO error, and Gecko's `MAX_READ` (`NativeMessaging.sys.mjs:17`), which throws an ExtensionError. Either way the Extension sees a bare disconnect that reads exactly like a crash.

So the Bridge serializes its response, checks the encoded size against 1 MiB less a small margin, and sends `callback_too_large` instead when it does not fit. A SAML assertion fat with group claims is the realistic trigger.

Browser-to-host is effectively unbounded (Gecko's `MAX_WRITE` is `0xffffffff`), so the request direction needs no check.

## Lifetime and failure

One process, one Handoff. After the terminal response the Bridge terminates, and any further stdin input is ignored rather than starting a second Handoff. That keeps "no resident process" true and means a Handoff cannot outlive its window.

Closing the Bridge window sends `declined`, whether it happens before the Approval or during the navigation afterwards: one user-visible concept, sign-in cancelled, and one code path. The `os_log` line records which phase it was in.

No timers on either side. The Bridge always sends a terminal response, including on termination, and `onDisconnect` covers a crash or a kill, so neither side waits forever without a signal. Entra can legitimately take minutes for MFA or a password change, so any fixed timeout would be either too short for that or too long to be useful.

Malformed input splits on whether the channel is usable. If the length prefix and body arrived but the payload is not a valid request, the Bridge replies `malformed_request`, because the port is alive and the Extension deserves a coded error. If the framing itself is broken (a short read, an absurd length, EOF mid-frame), there is nothing worth writing to: `os_log` and exit non-zero, the same posture as a rejected Caller.

stdout carries the protocol and nothing else. All Bridge diagnostics go to `os_log`.

## Extension-side re-check

Before navigating, the Extension re-validates the Bridge's `url`: HTTPS only, no embedded credentials. This duplicates part of the Bridge's Callback recognition on purpose. The Extension is the party that drives the original tab, and a Bridge bug or a swapped binary should not be able to point that tab at `http://` or a credentialed URL. It rejects with its own copy and does not navigate.
