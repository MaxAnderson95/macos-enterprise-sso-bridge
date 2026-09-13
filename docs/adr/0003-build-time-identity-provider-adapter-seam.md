# Build-time identity provider adapter seam

Entra is the only identity provider v1 implements, but provider-shaped knowledge (entry origins, `redirect_uri` extraction, the `SAMLResponse` / `code` / `id_token` / `error` field names) would otherwise smear across the Bridge's navigation delegate and the Extension's capture filter. It lives behind one protocol instead: `static var entryOrigins: [URL]` plus `func plan(_ request: SignInRequest) -> HandoffPlan?`, where the returned plan carries the destination to show in the Approval prompt and a closure that recognizes a candidate navigation as the Callback. Adapters see only `(url, method, fields)` values, never WebKit or native-messaging types, so they are unit-testable without a webview, and the seam is resolved at build time: no runtime plugin loading, no user-editable provider configuration.

## Consequences

Entry origins appear in four places that must agree: the adapter, both extension manifests' `host_permissions`, the `webRequest` listener filter, and the Extension's click-time origin check. A mismatch does not fail loudly; it simply never captures a Sign-in request. So one checked-in data file is the source of truth and both builds generate their constants from it, which is the opposite of the choice made for the protocol schema, where hand-written types on each side are fine because a structural mismatch fails on the first message.

Adding a provider means adding origins to that file, writing a type that conforms to the protocol, and registering it; the Extension needs no TypeScript change. It also means rebuilding and reinstalling both halves, which is the accepted cost of not having a runtime plugin mechanism.

There is no provider-specific replay hook. The core replays the Sign-in request verbatim because Entra needs nothing else, and the second adapter that genuinely needs one can add it.
