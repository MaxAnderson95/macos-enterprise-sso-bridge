# Identity provider adapter

Settled in [issue #7](https://github.com/MaxAnderson95/macos-enterprise-sso-bridge/issues/7) and recorded as [ADR 0003](../adr/0003-build-time-identity-provider-adapter-seam.md).

## The interface

One static property and one method:

```swift
protocol IdentityProviderAdapter {
    static var entryOrigins: [URL] { get }
    func plan(_ request: SignInRequest) -> HandoffPlan?
}

struct HandoffPlan {
    let destination: URL?
    let recognizes: (CandidateNavigation) -> Bool
}
```

`plan` returning nil means nothing in this Sign-in request is replayable, which the Bridge answers with `unsupported_request`. A plan whose `destination` is nil means the Handoff is replayable but its destination could not be derived, and the Approval says so plainly instead of guessing.

The plan closes over the Sign-in request, so the core never passes it back on every navigation, and the whole per-Handoff contract is created once at the start of the Handoff. The depth is in that: two questions the core needs answered, what to tell the user and whether this navigation is the Callback, arrive through one call.

`SignInRequest` and `CandidateNavigation` are both `(url, method, fields)` values. The adapter never sees a `WKNavigationAction`, a `WKWebView`, or a native-messaging frame, which is what makes it unit-testable without a webview.

## What the Entra adapter owns

- `https://login.microsoftonline.com` as its entry origin.
- `redirect_uri` extraction from the Sign-in request's query, and matching a candidate against it on scheme, host, port, and path.
- For SAML, deriving the destination by inflating and parsing the `SAMLRequest` to reach the ACS URL or issuer.
- The recognized field names `SAMLResponse`, `code`, `id_token`, and `error`.
- The judgment that a request carrying neither a `redirect_uri` nor a `SAMLRequest` is not replayable.

The Bridge core owns everything mechanical: selecting the adapter, replaying the Sign-in request verbatim, the navigation delegate, the main-frame, HTTPS, and no-credentials checks, urlencoded body extraction with the DOM fallback, the 1 MiB response check, and assembling the protocol response.

No provider-specific replay hook exists in v1. Entra needs none, and a hook with no caller is the sort of extension point this project's rules say not to build. A second adapter that genuinely needs one adds it then.

## Adapter selection

The Bridge matches the Sign-in request's origin against each adapter's `entryOrigins` and uses the first match; no match is `unsupported_request`. With one adapter the registry is a one-element array.

This check is not redundant with the Extension's capture filter. The Extension is untrusted under the threat model in ADR 0002, so the Bridge validates the origin itself.

## Keeping the Extension in step

The entry origins exist in three more places on the Extension side: `host_permissions` in each manifest, the `webRequest` listener's `urls` filter, and the click-time origin check on the active tab. If any of those drifts from the adapter, capture fails silently, which is the worst failure this system can have.

So the origins are not written in four places. One checked-in data file, `identity-providers/entra.json`, lists each provider's entry origins and is the single source of truth. The Bridge's Swift constant and the Extension's TypeScript constant are generated from it, and both manifests' `host_permissions` are templated from it at build time. The mechanics are in [build.md](build.md).

This is deliberately different from the protocol schema, where the types are hand-written on both sides. There the two definitions are structural and a mismatch fails loudly at the first message; here they are a value, and a mismatch fails silently by simply never capturing anything.

The origins are compiled into the Bridge rather than read from a bundled resource at runtime, for the same reason the Allowed browsers table is a Swift constant: an ad-hoc-signed bundle's resources are writable by anyone who can reach the `.app`, and an editable entry-origin list sitting in `/Applications` is exactly what the Bridge must not have.

## Adding a second adapter

Add its origins to the data file and add a type conforming to `IdentityProviderAdapter`, then register it. The Extension's origins, manifest permissions, and filter regenerate from the same file with no TypeScript changes.

The seam is build-time. There is no runtime plugin loading, no configuration file the user edits, and no way to add a provider without rebuilding both halves.
