# Enterprise SSO Bridge

Lets third-party macOS browsers complete corporate single sign-on through the Mac's native Enterprise SSO path, which those browsers cannot reach on their own. The browser starts the login, the Bridge authenticates natively, and the login finishes back in the original browser tab.

## Language

**Bridge**:
The native macOS application that authenticates with the identity provider on the browser's behalf.
_Avoid_: helper, probe, host app

**Extension**:
The browser extension that offers the sign-in action and talks to the Bridge. One per browser engine (Chromium build, Gecko build), sharing source.
_Avoid_: add-on, plugin

**Identity provider**:
The service that authenticates the user and issues the response the application consumes. Entra is the only supported identity provider.
_Avoid_: IdP (in prose), login provider, Microsoft (as a synonym for the provider)

**Enterprise SSO extension**:
The macOS platform component that authenticates the Mac to the identity provider, configured by a profile that names which applications may use it. Always written in full, never shortened to "the extension", which is the browser half of this project.
_Avoid_: SSO extension, PSSO, the extension

**Identity provider adapter**:
The Bridge-owned definition of one identity provider: its sign-in entry origins, what it can say about where a Sign-in request will send the user, and the rules that recognize a Callback leaving it. The Extension receives only the entry origins it needs, derived from the same definition.
_Avoid_: provider plugin, provider config

**Application**:
The web application the user is signing into. It receives the Callback in the original browser.
_Avoid_: site, relying party, service provider

**Handoff**:
One sign-in transaction, from the user's toolbar click to the Callback being delivered to the original tab.
_Avoid_: session, flow, request

**Approval**:
The user's confirmation, given in the Bridge's own window, that a Handoff should proceed. Nothing is loaded before it.
_Avoid_: consent, confirmation dialog, prompt

**Sign-in request**:
The Application's original request to the identity provider (URL, method, and any form fields such as a SAMLRequest), observed by the Extension and replayed by the Bridge to begin a Handoff.
_Avoid_: sign-in URL, login URL, auth URL, input URL, initial request

**Callback**:
The navigation that leaves the identity provider and returns to the Application, carrying the authentication response. Either a GET redirect or a POST form submission.
_Avoid_: redirect, return URL, response

**Relay page**:
The Extension-owned page loaded in the original tab to submit a POST Callback to the Application.
_Avoid_: finish page, response page, form page

**Caller**:
The process that launched the Bridge's native-messaging endpoint. Only an allowed browser is a legitimate Caller.
_Avoid_: parent, client, launcher

**Allowed browser**:
A browser whose code-signing identity the Bridge accepts as a Caller. The set is fixed at build time.
_Avoid_: whitelist, supported browser, trusted browser
