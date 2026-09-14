# Acceptance checklist

The manual end-to-end pass. Run it before tagging a release, and after any change to capture, recognition, or the Relay page.

Nothing here can run in CI: it needs Helium, Zen, a real Entra tenant, an Application, and a Mac whose Enterprise SSO extension allows the Bridge. Do not commit results, which would carry tenant and Application names.

## Before starting

- [ ] The installed `.pkg` version, both extension versions, and the tag under test all match.
- [ ] The Enterprise SSO configuration profile's `AppAllowList` includes `tech.maxanderson.enterprise-sso-bridge`.
- [ ] Private-browsing access is granted to the extension in both browsers.
- [ ] `log stream --predicate 'subsystem == "tech.maxanderson.enterprise-sso-bridge"'` is running, so each run's phase lines are visible.

## The matrix

Each cell is one Handoff, started from the Application's own login page: click the toolbar action on the provider page, approve, and expect the original tab to land signed in.

| Callback shape | Helium, normal | Helium, private | Zen, normal | Zen, private |
| --- | --- | --- | --- | --- |
| OIDC, GET redirect | | | | |
| OIDC, `form_post` | | | | |
| SAML, POST | | | | |

For every cell, check all of:

- [ ] The Approval names the correct Callback destination, the identity provider, and the browser you clicked in.
- [ ] No Bridge window content appears before the Approval, and the window grows only after approving.
- [ ] Entra completes without a password prompt in the common case, which is the whole point of the tool.
- [ ] The original tab, not a new one, ends up signed in to the Application.
- [ ] The toolbar badge returns to empty, and the Bridge process is gone (`pgrep -f "Enterprise SSO Bridge"` finds nothing).
- [ ] No URL, query string, body, or form field appears in the log stream.

For the two POST rows, also record which body-extraction path the Bridge used, from its `os_log` line: urlencoded `httpBody`, or the DOM-form fallback. That is the open question the first real run exists to answer.

## Failure and edge paths

Run these once per release, in either browser unless stated.

- [ ] **Decline.** Click Cancel on the Approval. The tab shows no error state; the title reads "Sign-in cancelled. Click to start again."
- [ ] **Close mid-navigation.** Approve, then close the Bridge window while Entra is loading. Same cancelled treatment, and the log names the phase.
- [ ] **Bridge not installed.** Move the `.app` aside and click the action. The popup says the Bridge did not respond, and Try again works once it is back.
- [ ] **Wrong page.** Click the action on any non-provider page. The popup sends you to the Application's login page.
- [ ] **Nothing replayable.** Navigate directly to the provider's sign-in host without coming from an Application, then click. The Bridge answers `unsupported_request` with no window shown, and the popup sends you back to the Application's login page.
- [ ] **Version skew.** Install a `.pkg` from a different release than the extensions. The popup says to install the matching release of both.
- [ ] **Caller authentication, negative.** Run the negative-test script, which spawns the built executable from a shell. It must exit non-zero, write nothing to stdout, and log the rejection with the parent's bundle identifier.
- [ ] **Relay page replay.** After a successful SAML POST Handoff, reload the tab. The Relay page must not resubmit the assertion; it says the sign-in has already been completed.
