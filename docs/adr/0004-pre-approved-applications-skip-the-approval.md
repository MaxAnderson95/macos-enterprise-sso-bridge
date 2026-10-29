# Pre-approved Applications skip the Approval

Clicking the toolbar action and then Sign In on every Handoff became friction once the Bridge was in daily use, mostly for the same few Applications. The Bridge therefore reads a list of Pre-approved Application origins from its own preferences domain (`tech.maxanderson.enterprise-sso-bridge`, key `PreApprovedApplications`, an array of HTTPS origins) and skips the Approval when the destination its adapter derived from the Sign-in request has an exactly matching origin. The Extension starts a Handoff on its own as soon as it captures a Sign-in request and marks it automatic; the Bridge answers an automatic Handoff whose destination is not pre-approved with `approval_required` and no window, so the Extension stays idle and the toolbar action works as before. This partly supersedes ADR 0002, which rejected "Approval remembered per Application".

## Why this is acceptable now

ADR 0002 framed the threat as a hostile extension in an Allowed browser. The browser narrows that further than the ADR said: both engines refuse `connectNative` to the Bridge from any extension not named in the host manifest's `allowed_origins` / `allowed_extensions`. The callers left are this Extension compromised (a malicious build, a supply-chain change) and native code inside the browser process. Both can already read the session cookies and storage of every Application the user is signed into in that browser, which is the same Applications a user would pre-approve.

What a pre-approval adds for such a caller is a fresh Callback (a SAML assertion or an authorization code) for a listed Application, without a click, returned over stdout to the caller rather than to the Application. The list bounds which Applications that applies to. It does not bound who receives the Callback, and nothing on the Bridge side can, because the caller is the delivery path.

## Considered options

- Keep the Approval on every Handoff (ADR 0002 unchanged): rejected for the friction above, given the narrowed threat.
- A list in extension storage, set from an options page: Extension code could write the list it is trusted by, and each browser would need its own copy kept in step by hand.
- The Extension asserting that a request is pre-approved: the Extension is the distrusted party, so the claim is not evidence. The automatic marker it does send can only make the Bridge stricter (fail quietly instead of prompting), never skip the Approval.
- Matching on origin plus path, or on host suffix wildcards: origin is what the user recognises and what the Approval already shows; wildcards would pre-approve hosts the user never named.
- Matching on Entra `client_id` or SAML issuer instead of destination: more precise about which registration is signing in, but not something a user can read off a login page or would know to list.

## Consequences

The list is keyed on the Callback's origin, not on the client registration. A Sign-in request for a different client whose registered redirect URI sits on a listed origin also passes without an Approval; Entra's consent prompt and the tenant's consent policy are what stop an unknown client, and a consent prompt needs interaction in the Bridge window.

A plan whose destination is nil is never pre-approved, so some SAML Applications always need the toolbar action and the Approval.

The preferences file is not writable by Extension code. Native code in the browser process could write it, which adds nothing for an actor that can already read the sessions the list protects.

An automatic start means one Bridge process per captured Sign-in request, including for Applications that are not pre-approved. Those exit after planning without a window.
