# Enterprise SSO Bridge: v1 specification

What v1 is, in enough detail to build it. Every decision here was settled on a ticket under the [wayfinder map](https://github.com/MaxAnderson95/macos-enterprise-sso-bridge/issues/1); each document links back to the ticket that holds the reasoning, and the three choices that are hard to reverse are recorded as ADRs under `docs/adr/`.

`CONTEXT.md` at the repo root is the glossary. The capitalized terms used throughout these documents (Bridge, Extension, Handoff, Sign-in request, Callback, Relay page, Caller, Allowed browser, Approval, Identity provider adapter, Application) are defined there and nowhere else.

## The documents

| Document | Covers |
| --- | --- |
| [architecture.md](architecture.md) | The parts, one Handoff end to end, the trust model, and the logging invariant |
| [protocol.md](protocol.md) | The native-messaging messages, error codes, size limit, and process lifetime |
| [bridge.md](bridge.md) | The Bridge's lifecycle from `main` to exit, its window states, and the Callback capture |
| [caller-authentication.md](caller-authentication.md) | How the Bridge decides its parent is an Allowed browser |
| [callback-recognition.md](callback-recognition.md) | What counts as a Callback, and what the Bridge does with everything else |
| [identity-provider-adapter.md](identity-provider-adapter.md) | The adapter interface and where provider knowledge lives |
| [extension.md](extension.md) | Capture, the toolbar action, every user-facing state and its copy, and the Relay page |
| [install.md](install.md) | The package, both extension installs, MDM setup, updates, and uninstall |
| [build.md](build.md) | Repository layout, toolchains, generated constants, versioning, and CI |
| [testing.md](testing.md) | What is unit-tested, what runs in CI, and what only a real Mac can check |

## Scope

v1 supports Entra as the only identity provider, behind an adapter seam that a second provider could fill without touching the Extension. It ships two Allowed browsers, Helium and Zen, and treats that pair as the v1 set rather than as the design: another Chromium or Gecko browser joins by adding its designated requirement to the table plus whatever its install story needs.

Out of scope for v1, each ruled out deliberately: Developer ID signing and notarization, Microsoft BrowserCore integration, copying cookies or keys between browsers, Safari, Windows, Linux, a resident background process, and any identity provider other than Entra.
