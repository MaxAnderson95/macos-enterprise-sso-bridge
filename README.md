# Enterprise SSO Bridge

> [!WARNING]
> This project is a work in progress. It is still being built and is not ready for use.

Lets third-party macOS browsers complete corporate single sign-on through the Mac's native Enterprise SSO path, which those browsers cannot reach on their own. The browser starts the login, a native app authenticates, and the login finishes back in the original browser tab.

Without it, a browser outside Apple's and Microsoft's allowlist has no route to a Primary Refresh Token, so every sign-in means a password and an MFA prompt even on a Mac that is already authenticated to the tenant.

## Status

Specified, not yet built. The v1 specification is in [docs/spec/](docs/spec/README.md); the decisions behind it were worked ticket by ticket under the [wayfinder map](https://github.com/MaxAnderson95/macos-enterprise-sso-bridge/issues/1), with the hard-to-reverse ones recorded as ADRs in [docs/adr/](docs/adr/).

Install instructions, supported browsers, and MDM setup land here when there is something to install. What that will say is already settled in [docs/spec/install.md](docs/spec/install.md).

## Repository

| Path | Contents |
| --- | --- |
| `CONTEXT.md` | The glossary. Every capitalized domain term is defined there. |
| `docs/spec/` | The v1 specification. |
| `docs/adr/` | Architecture decision records. |
| `docs/research/` | Findings behind the decisions, with sources. |
| `docs/testing/` | The manual acceptance checklist. |
| `assets/` | Icon masters and the generator that produces them. |
