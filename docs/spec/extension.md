# The Extension

One TypeScript source tree, two builds: Chromium (Helium) and Gecko (Zen). Manifest V3 in both. States and copy settled in [issue #14](https://github.com/MaxAnderson95/macos-enterprise-sso-bridge/issues/14); capture and Relay page rules in [issue #6](https://github.com/MaxAnderson95/macos-enterprise-sso-bridge/issues/6); permissions research in `docs/research/extension-permissions.md`.

## Permissions

`webRequest`, `storage`, `nativeMessaging`, `activeTab`, plus `host_permissions` of the generated entry origins, which today is `https://login.microsoftonline.com/*` alone.

That single origin is sufficient because main-frame navigations skip the initiator permission check in both engines. `activeTab` covers reading `tab.url` in the click handler, so the broad `tabs` permission is not needed; `tabs.update` needs no permission at all.

The Chromium build sets `"incognito": "split"`, which it must, because the default `spanning` cannot load an extension page as the main frame of an incognito tab and that breaks the Relay page there. The Gecko build omits the key entirely, because Firefox downgrades `split` to `not_allowed`.

## Capturing the Sign-in request

A `webRequest.onBeforeRequest` listener with `{ urls: <generated entry origins>, types: ["main_frame"] }` and `["requestBody"]`.

For a POST it reads `requestBody.formData`, decoding Chromium's `ArrayBuffer` values to strings and flattening repeated names into `[name, value]` pairs; if only `raw` is present it decodes and parses the body as urlencoded. For a GET it keeps the URL. The result is written to `storage.session` keyed by tab, with the capture time.

`storage.session` rather than a module-level `Map`, because the Chromium MV3 service worker can be evicted between the navigation and the click.

One known gap, from the permissions research: Gecko can miss a Sign-in request issued immediately after a browser restart, before the listener is primed. The user-facing path for that is `unsupported_request`, whose copy sends them back to the Application's login page.

## The toolbar action

No `default_popup` in either manifest, because setting one stops `action.onClicked` from firing and starting a Handoff is the button's job.

On click:

1. Ignore the click if a Handoff is already in flight for this tab.
2. Check the active tab's origin against the generated entry origins. A mismatch is the "wrong page" state.
3. Read the capture for this tab, bounded to ten minutes. Anything older is ignored, so an attempt abandoned an hour ago never replays.
4. `connectNative` and send the request frame.
5. On the terminal response, re-validate any returned URL (HTTPS, no embedded credentials), then navigate.

Handoff claims live in `storage.session`. The background instance also tracks the claims it acquired, which never expire while that instance is waiting for the Bridge. After a background restart, a click may replace an inherited claim once its `startedAt` is more than thirty minutes old. This gives an abandoned claim a recovery path while allowing time for MFA or a password change before an inherited claim is replaced. It does not time out the native-messaging exchange or extend the capture's ten-minute lifetime: an expired capture still sends the user back to the Application's login page. Finishing a Handoff or closing its tab releases the claim; navigation only clears the action state.

The capture's `storage.session` key is deleted only on a terminal success. On any failure it survives, so the popup's Try again button replays the same Sign-in request without sending the user back through the Application's login page. That is deliberately the opposite of the Relay page's consume-once rule: replaying a Sign-in request starts a fresh authentication, while resubmitting an assertion is a replay of a credential.

The spike's path heuristic, which guessed from a `/saml2` path that the capture had been missed, is not carried forward. That judgment belongs to the adapter and arrives as `unsupported_request`.

## Delivering the Callback

A GET Callback goes straight to `tabs.update` with the URL.

A POST Callback is written to `storage.session` keyed by tab and the tab is sent to the Relay page, which reads it once and submits it as a form.

## Per-tab state

Three states, carried by the badge and the title:

- idle: empty badge;
- Handoff in flight: `…`;
- needs attention: `!` on red.

There is no success badge, because the tab navigating to the Application is the success signal. Per-tab state lives in `storage.session` keyed by tab, for the same eviction reason as the capture, and clears when the tab navigates away or closes.

## Errors that need a sentence

The Bridge shows its own failures in its own window until dismissed, so for `navigation_failed`, `callback_too_large`, and `internal` the user has already read an explanation and the Extension sets only the badge and title.

For everything else nothing else spoke, so the Extension attaches a popup to that tab with `action.setPopup({ tabId, popup })`. The next click opens the explanation instead of starting a Handoff; the popup's Try again button clears the popup and the badge and starts a fresh Handoff with the surviving capture. The popup is cleared on retry, on the tab navigating away, and on the tab closing.

Note that `unsupported_request` is decided before any Approval, so the Bridge exits without ever showing a window. That is why its copy lives here.

## Copy

User-facing copy says "Enterprise SSO Bridge" on first mention and "the Bridge" after. No error code names, no `OSStatus` values, nothing the user cannot act on; the protocol's `detail` field stays in the console.

| State | Badge | Title | Popup |
| --- | --- | --- | --- |
| Idle | (empty) | Sign in with Enterprise SSO Bridge | none |
| Handoff in flight | `…` | Sign-in is open in Enterprise SSO Bridge. | none |
| Wrong page at click time | `!` | Open the application's Microsoft sign-in page first. | Open the application's Microsoft sign-in page first, then click this button. |
| Disconnect with no reply | `!` | Enterprise SSO Bridge did not respond. | Enterprise SSO Bridge did not respond. Install it from the release page, or check that it is installed in /Applications. |
| `unsupported_version` | `!` | Version mismatch with Enterprise SSO Bridge. | Enterprise SSO Bridge is a different version than this extension. Install the matching release of both. |
| `unsupported_request` | `!` | This sign-in could not be started. | This sign-in could not be started. Go back to the application's login page and start again from there. |
| `malformed_request` | `!` | The sign-in request could not be read. | The sign-in request could not be read. Start again from the application's login page. |
| `callback_too_large`, `navigation_failed`, `internal` | `!` | Sign-in failed. Enterprise SSO Bridge has the details. | none |
| Unknown code | `!` | Sign-in failed for an unrecognized reason. | Sign-in failed for an unrecognized reason. Check that Enterprise SSO Bridge and this extension are the same version. |
| Rejected callback URL | `!` | The sign-in response pointed somewhere unexpected. | The sign-in response pointed somewhere unexpected and was not opened. |
| `declined` | (cleared) | Sign-in cancelled. Click to start again. | none |

A declined Approval is not a failure: no `!`, no red, no popup. The user clicked Cancel a second earlier and already knows what happened, and a cancellation that looks like an error teaches them to distrust the red badge.

## Relay page

An extension page whose only job is submitting a POST Callback to the Application from the original tab.

It reads the Callback from `storage.session` for its tab and deletes the key on read, so a page reload cannot resubmit the assertion. The existing `tabs.onRemoved` cleanup covers the key if the tab closes first.

On screen it is one quiet unstyled line, "Returning you to the application", because the page exists for about the length of a form submission and a flash of styled content is worse than a flash of text. When the key is already consumed or missing, or the `securitypolicyviolation` listener fires, that line is replaced with "This sign-in has already been completed or has expired. Start again from the application's login page."

The extension-pages CSP keeps `form-action https:`, and its limits are worth stating plainly. Per w3c/webappsec-csp issue 8 the engines are not interoperable: Chromium and WebKit check every redirect target in the chain against `form-action`, while Firefox checks only the initial submission. So Helium blocks a 307 or 308 from the Application to a non-HTTPS location and Zen does not. And because the value is `https:`, it never constrains which HTTPS host receives the assertion. It is worth keeping because it blocks a plaintext submission target and the violation listener turns a silent block into a readable message, but it is not the control that keeps the assertion safe.

A body-preserving redirect after the Relay page's POST is the Application's business. It re-sends the assertion to a new location, which is exactly what happens in a normal browser sign-in with no Bridge involved, and nothing available to an extension page could stop it short of proxying the request.

## Private windows

Supported, and user-granted in both engines.

A Handoff started in a private window completes entirely inside that instance, which has its own `storage.session`. The Chromium build gets that isolation from `"incognito": "split"`; the Gecko build works under the default `spanning`.

When private-browsing access has not been granted the extension does not run in private windows at all, so the toolbar button is absent or inert there and the Extension has no context in which to display guidance. Enabling it is documented in the README rather than detected at runtime: warning from a normal window about a capability the user may never want is noise.

## Configuration

There is none. No options page, no configuration file, no policy.

Entry origins are build-time constants, the install decisions rule out policies and files, and nothing in v1 has a setting worth exposing. An empty options page added to fill a slot in the manifest is the extension point this project's rules say not to build.
