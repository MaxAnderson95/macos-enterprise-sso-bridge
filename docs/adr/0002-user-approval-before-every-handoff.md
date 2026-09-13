# User approval before every Handoff

Caller authentication proves the Bridge's parent is an Allowed browser and deliberately says nothing about what is running inside it, so a hostile extension in an Allowed browser could ask for any Sign-in request and get back a real token or SAML assertion with no interaction, because platform SSO is designed not to prompt. The Bridge therefore requires an explicit approval in its own window, outside the browser's trust domain, before it instantiates a WKWebView or loads anything: the prompt names the identity provider and the Callback destination derived from the Sign-in request itself, and declining sends a structured decline back over the protocol and exits.

## Considered options

- No approval, relying on caller authentication and Entra: rejected because it leaves silent token minting for arbitrary relying parties available to any code inside an Allowed browser, with no user-visible trace.
- Approval remembered per Application: rejected because the case worth catching is an unrequested Handoff to an Application the user has signed into before, which is exactly the case a remembered approval waves through, and v1 otherwise keeps no persistent state.
- Treating the Extension's toolbar click as the approval: the click happens inside the process being distrusted, so it is not evidence.
- LocalAuthentication `deviceOwnerAuthentication` (Touch ID, password fallback): it defends against a local attacker who can already synthesize clicks, which requires TCC accessibility rights and therefore a much deeper compromise than the threat here. It also degrades badly on this hardware: probed on macOS 26 from an ad-hoc-signed `.app`, `deviceOwnerAuthenticationWithBiometrics` reported unavailable (LAError -4) while the lid was shut, so a docked Mac would demand the account password on every Handoff.
- Displaying the Application origin as reported by the Extension: it is the field a malicious extension would lie about, and it would read as verified. The prompt shows only what the Bridge derives from the Sign-in request, which is truthful by construction because it describes where the token will actually go.

## Consequences

The Identity provider adapter must be able to describe a Sign-in request's destination before replaying it, and must be able to report that it cannot determine one; the prompt says so plainly rather than guessing. That obligation is recorded on the adapter-interface ticket.

A hostile extension can still spawn Bridges in a loop, each taking focus with a prompt. No Handoff completes without a click, so this is a denial of attention, not a token leak, and v1 accepts it: rate-limiting would need cross-process state and a lock protocol that v1 has nowhere to keep, and would hand an attacker a way to suppress a genuine prompt.
