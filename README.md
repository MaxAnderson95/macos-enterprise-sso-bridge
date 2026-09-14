# Enterprise SSO Bridge

Lets third-party macOS browsers complete corporate single sign-on through the Mac's native Enterprise SSO path, which those browsers cannot reach on their own. You click the toolbar action in your browser, a small native app authenticates with the identity provider, and the sign-in finishes back in the tab you started from.

Without a working Enterprise SSO integration, a browser may be unable to use the Mac's existing work-account sign-in or present its device identity to Entra. That can mean extra authentication prompts or a Conditional Access block, even on a Mac that is already authenticated to the tenant.

## Requirements

- macOS 26 or newer, on Apple silicon.
- A Mac enrolled with an Enterprise SSO configuration profile for Microsoft Entra, whose `AppAllowList` includes this app. See [MDM setup](#mdm-setup); without it the Bridge is just a second browser.
- One of the supported browsers. The Bridge accepts only these two as callers, checked against their code-signing identities:

| Browser | Engine | Extension package |
| --- | --- | --- |
| [Helium](https://helium.computer) | Chromium | `.crx`, installed by the script below |
| [Zen](https://zen-browser.app) | Gecko | `.xpi`, installed by hand |

Entra is the only supported identity provider.

## Installing

Everything comes from one [release](https://github.com/MaxAnderson95/macos-enterprise-sso-bridge/releases): the `.pkg`, `install-chromium-extension.sh`, the `.crx`, and the `.xpi`. Download the ones you need for your browsers, keeping the script and the `.crx` in the same folder.

### 1. The Bridge

The package is not signed with an Apple Developer ID, so macOS refuses it on the first attempt and you approve it in System Settings.

1. Double-click `EnterpriseSSOBridge-<version>.pkg`. macOS blocks it.
2. Open System Settings, then Privacy and Security.
3. Scroll to the Security section, where a line about the blocked package appears, and click Open Anyway.
4. Authenticate, then double-click the package again and complete the installer.

That installs `/Applications/Enterprise SSO Bridge.app` and registers it with both browser engines. Nothing else runs: the package has no install scripts.

The dialogs on macOS 26 have not been checked step by step, so the wording above may not match exactly. If Open Anyway does not appear for the package, `sudo installer -pkg EnterpriseSSOBridge-<version>.pkg -target /` installs the same payload from the terminal. That path is untested against a freshly downloaded, quarantined package.

You never launch the app yourself. Opening it shows a window explaining what it is and which version is installed, and quits when you dismiss it.

### 2. The Helium extension

Run the script from the folder holding the `.crx`:

```sh
chmod +x install-chromium-extension.sh
./install-chromium-extension.sh
```

It needs no root. It copies the package into `~/Library/Application Support/tech.maxanderson.enterprise-sso-bridge/` and points Helium at it from `~/Library/Application Support/net.imput.helium/External Extensions/`.

The script also removes a user-level Bridge development registration when its target no longer exists, so it cannot hide the installed release. It preserves other user-level registrations and warns that they may override the release.

Restart Helium. It offers the extension once, as an item in the three-dot menu rather than a popup, and you accept it there. Helium disables any externally installed extension until you do, so the toolbar action will not appear before that click.

### 3. The Zen extension

Zen accepts unsigned add-ons, but only after you turn off the signature requirement.

1. Open `about:config`, accept the warning, search for `xpinstall.signatures.required`, and set it to `false`.
2. Open `about:addons`, click the gear, choose Install Add-on From File, and pick `enterprise-sso-bridge-<version>.xpi`.
3. Confirm the permission prompt.

The pref stays `false` for as long as the add-on is installed. Turning signature enforcement back on while an unsigned add-on is present would very likely disable it, since Gecko rechecks signatures periodically. [Uninstalling](#uninstalling) restores it.

### 4. Private browsing

The extension has no access to private windows until you grant it, and the sign-in it drives will not start there without it.

- **Helium:** open `chrome://extensions`, click Details on Enterprise SSO Bridge, and turn on Allow in Incognito.
- **Zen:** open `about:addons`, click Enterprise SSO Bridge, and set Run in Private Windows to Allow.

## MDM setup

The Enterprise SSO extension's payload must list this app in its `AppAllowList`:

```
tech.maxanderson.enterprise-sso-bridge
```

Without that entry the Bridge's web view never reaches the platform SSO path, so it authenticates like any other browser and the whole point is lost.

Nothing else here is fleet-deployable, by design. This tool ships outside the extension stores, without Apple signing, and without browser policies, so every step above is a person at a keyboard.

## Updating

Nothing updates itself. A new release means installing the new `.pkg`, running `install-chromium-extension.sh` against the new `.crx`, and installing the new `.xpi` through the same file picker. The script is the update path as well as the install path, and it overwrites both files it owns.

The Bridge's window shows its installed version, and each request carries a protocol version the Bridge either implements or refuses by name, so a genuinely incompatible pairing says so rather than failing obscurely. A stale but still compatible pairing is not detected.

## Uninstalling

Remove the extensions first, so restoring Zen's signature pref does not fight a still-installed add-on.

1. In Helium, open `chrome://extensions` and remove Enterprise SSO Bridge. In Zen, open `about:addons` and remove it.
2. In Zen's `about:config`, set `xpinstall.signatures.required` back to `true`. This one matters: leaving it off weakens add-on security for the whole profile, not just for this extension.
3. Delete the files:

```sh
sudo rm -rf "/Applications/Enterprise SSO Bridge.app"
rm -rf "$HOME/Library/Application Support/tech.maxanderson.enterprise-sso-bridge"
rm -f "$HOME/Library/Application Support/net.imput.helium/External Extensions/ddalcfdgiklpbglknegedadiaclfkncc.json"
sudo rm -f "/Library/Application Support/Chromium/NativeMessagingHosts/tech.maxanderson.enterprise_sso_bridge.json"
sudo rm -f "/Library/Application Support/Mozilla/NativeMessagingHosts/tech.maxanderson.enterprise_sso_bridge.json"
sudo pkgutil --forget tech.maxanderson.enterprise-sso-bridge
```

4. Remove `tech.maxanderson.enterprise-sso-bridge` from the Enterprise SSO extension's `AppAllowList` if nothing else needs it.

## Why this project exists

An enrolled Mac can be signed into its work account while a third-party browser on that same Mac cannot prove the device's identity to Entra. Depending on the organization's Conditional Access policies, that means extra authentication prompts or a blocked sign-in even though the device is managed and compliant. The missing piece is the browser's route to the Mac's Enterprise SSO extension.

### The older route: a Workplace Join certificate

In the traditional Workplace Join (WPJ) registration model, the Mac's device certificate and private key lived in the user's login Keychain. During an Entra sign-in, a browser could answer a TLS client-certificate challenge with that identity, subject to Keychain access permissions. The browser presented the certificate and used its private key to prove possession; Entra could then associate the sign-in with the registered device and evaluate device-based Conditional Access.

That certificate identified the device. It did not, by itself, replace the user's password, satisfy every MFA requirement, or guarantee access. Its useful property for third-party browsers was that ordinary client-certificate support could provide device identity without a browser-specific Microsoft SSO integration.

### Secure Enclave changes who can use the key

With hardware-backed device identity, the private key is protected by the Secure Enclave and cannot be exported. Possessing a copy of the public certificate is no help: a TLS client must also be able to perform the private-key operation. An arbitrary browser cannot use this Microsoft-managed identity through its old login-Keychain certificate picker. It needs the Enterprise SSO extension to provide the device authentication and SSO credentials through an authorized integration.

This also affects Macs without Platform SSO. In August 2025, Microsoft began making Secure Enclave the default storage for device identity keys on newly registered devices. A browser that relied on the old Keychain certificate path can therefore lose access to device identity even if the organization has never enabled Platform SSO.

### WebKit has an admin-configurable route

Microsoft's Enterprise SSO extension, shipped inside Company Portal on macOS, integrates with Apple's native networking and web views. When an eligible app loads an Entra sign-in through `WKWebView`, Apple's Enterprise SSO framework can route the request through that extension. The Enterprise SSO extension uses the Mac's existing work-account credential, including its Primary Refresh Token (PRT), to authenticate to Entra and supply device identity. This does not give the app the raw PRT or the private key.

Safari participates by default unless an admin blocks it. Other apps using Apple's networking or `WKWebView` can participate through the MDM-configured `AppAllowList`. For this project, a Mac admin adds `tech.maxanderson.enterprise-sso-bridge` to that list in the existing Enterprise SSO configuration. The Bridge's web view then has the native route it needs. The exact profile entry is in [MDM setup](#mdm-setup).

### Other browser engines need a separate integration

Chromium and Gecko (Firefox) have their own networking stacks, so their ordinary page requests do not automatically take WebKit's route. Supported browsers have explicit integration code that asks Microsoft's broker for browser SSO credentials and applies them to the sign-in. Historically, Chrome needed the Microsoft Single Sign On browser extension and its native-messaging component, BrowserCore. Microsoft now documents built-in Enterprise SSO support in Chrome 135 and newer, Edge's signed-in profile integration, and Firefox's `MicrosoftEntraSSO` policy. These paths obtain browser-usable SSO credentials, such as PRT-derived cookies, rather than exporting the PRT.

Having that code in a browser fork is not enough. Microsoft's browser SSO operation also checks the caller against a Microsoft-maintained, compiled-in set of browser-partner signing identities. During this project's investigation, the broker rejected Helium's Team ID even with Microsoft's browser extension installed. This is a separate gate from the native-app `AppAllowList`: an admin cannot add a new browser signing identity to it through the SSO profile. There is no supported MDM override that makes an arbitrary Chromium or Gecko fork an accepted browser partner; Microsoft must admit that identity for the direct integration to work.

### The handoff

The Bridge moves the Entra portion of a sign-in into an app that the admin can authorize:

```text
Helium / Zen                 Bridge: WKWebView               Entra
    |                              |                          |
    |--- original sign-in -------->|                          |
    |                        user approves                    |
    |                              |--- native SSO sign-in -->|
    |                              |<-- application callback --|
    |<-- captured callback --------|                          |
    |                              | exits                    |
    |--- callback to the application, in the original tab
```

The Application starts its normal login in the original browser, and the Extension remembers the Sign-in request. When the Entra sign-in page appears, the user clicks the Extension's toolbar button instead of entering credentials in that tab. After Approval, the Bridge replays the request in its allowed WebKit web view. When Entra sends the authentication response back toward the Application, the Bridge captures that Callback before WebKit delivers it and hands it to the Extension. The Extension delivers it from the original tab, where the Application can finish the login and establish its browser session.

Only that transaction's Callback crosses back. The Bridge does not export the device key, return the PRT, or copy its cookie store into the other browser. Entra still evaluates the sign-in and can require MFA or refuse access. The Application still validates its authentication response and transaction state.

Microsoft's documentation for the key-storage change, native-app allowlist, and supported browser integrations:

https://learn.microsoft.com/en-us/entra/identity-platform/apple-sso-plugin

## Architecture

The project has two runtime parts: a TypeScript browser Extension, built for Chromium and Gecko from one source tree, and a Swift/AppKit Bridge with a `WKWebView`. `BridgeCore` owns protocol decoding, caller authentication, Approval data, and Callback recognition. The executable connects those decisions to macOS windows and WebKit navigation delegates.

### One Handoff, one process, one connection

Each Handoff opens its own `runtime.connectNative("tech.maxanderson.enterprise_sso_bridge")` connection. The browser reads the installed native-messaging manifest and launches a fresh Bridge process with anonymous stdin/stdout pipes. That connection carries exactly one Sign-in request and at most one terminal response. A successful exchange returns one Callback and the Bridge exits.

The 1:1 relationship is between a Handoff and its Bridge process, rather than a permanent pairing between an installed Extension and one running app. Different tabs can have separate Handoffs and separate Bridge processes. Repeated clicks in the same tab cannot start another Handoff while its current one is active. There is no resident daemon, localhost HTTP server, shared request queue, or multiplexed connection, so the wire protocol needs no Handoff ID. The Extension keeps the association with the originating tab locally.

Cancel or closing an active Bridge window returns `declined` and exits. A navigation failure returns an error immediately but leaves the window open until the user closes it. The Extension deliberately leaves the native port open after a response so the browser does not kill that failure window. A disconnect without a response is a separate failure, covering a missing Bridge, a rejected Caller, or a crashed process. There is no authentication timeout: MFA and password changes can legitimately take minutes.

### The wire protocol

Both engines use the same native-messaging framing:

```text
4-byte unsigned payload length | that many bytes of UTF-8 JSON
```

The length is in native byte order, which is little-endian on the supported Apple silicon Macs, and counts JSON bytes rather than characters. Frames can arrive through multiple pipe reads; the Bridge reads until the complete prefix and body have arrived. stdout is reserved for protocol frames. Native diagnostics go to `os_log`.

The Extension sends protocol version `1`, the original URL, and an explicit HTTP method. A GET request has no `fields` member:

```json
{
  "version": 1,
  "url": "https://login.microsoftonline.com/example-tenant/oauth2/v2.0/authorize?client_id=example&redirect_uri=https%3A%2F%2Fapp.example.com%2Fcallback&response_type=code&state=example",
  "method": "GET"
}
```

A POST carries decoded form fields as pairs:

```json
{
  "version": 1,
  "url": "https://login.microsoftonline.com/example-tenant/saml2",
  "method": "POST",
  "fields": [["SAMLRequest", "..."], ["RelayState", "..."]]
}
```

Pairs preserve repeated field names, which a JSON object would lose. The Extension preserves the values exposed by the browser's form-data API; that API groups repeated names, so it cannot promise the original ordering between different names. The protocol transfers the URL, method, and form values, not the original request's headers, cookies, or byte-for-byte POST encoding.

The terminal response is one of these shapes:

```json
{"result":"callback","url":"https://app.example.com/callback?code=...&state=...","method":"GET"}
{"result":"callback","url":"https://app.example.com/sso/acs","method":"POST","fields":[["SAMLResponse","..."],["RelayState","..."]]}
{"result":"declined"}
{"result":"error","code":"navigation_failed","detail":"NSURLErrorDomain -1003"}
```

Swift enums and TypeScript discriminated unions describe those alternatives. The two implementations share JSON fixtures under `fixtures/protocol/`. An unsupported request version returns `unsupported_version` with an integer `bridgeVersion` naming the supported protocol version, not the app's release version. Other codes distinguish malformed input, an unsupported Sign-in request, an oversized Callback, navigation failure, and an internal error.

The Bridge caps inbound frame allocation at 1 MiB. For outgoing responses it serializes first and enforces a budget of 1 MiB minus 4 KiB, below the browser native-messaging limit. An oversized response becomes `callback_too_large`, avoiding a bare disconnect when a large SAML assertion exceeds the browser's limit. Broken framing, such as a truncated body or an excessive declared length, causes a nonzero exit without a response. A complete frame containing an invalid request can receive a structured error. The full message contract is in [the protocol specification](docs/spec/protocol.md).

### Capturing and replaying the Sign-in request

The Extension observes main-frame requests to the configured Entra entry origins with `webRequest.onBeforeRequest`. It records GET URLs and POST form values without blocking the navigation. The toolbar action requires the current tab to be at an entry origin and a captured request less than ten minutes old. This matters for SAML: the visible login-page URL alone may no longer contain the original `SAMLRequest` POST that started authentication.

Captures, per-tab claims, action state, and pending POST Callbacks live in memory-only `storage.session`, surviving Extension background restarts. A failed Handoff retains its capture for retry within the capture's age limit; successful delivery spends it. A locally active claim has no expiry while it waits for the Bridge. A claim inherited after a background restart can be reclaimed after thirty minutes. Closing a tab removes its stored state.

The Bridge checks that the request belongs to its Entra adapter and contains `redirect_uri` or `SAMLRequest`. For Approval, it first uses `redirect_uri`, then the SAML authentication request's `AssertionConsumerServiceURL`, with an HTTP(S) SAML issuer URL as a fallback display hint. An issuer identifies the Application and is not necessarily its actual Callback endpoint. The SAML reader handles base64 XML and the raw-DEFLATE form used by HTTP-Redirect, with external XML entities disabled. If it cannot derive a display destination, the prompt says so. Only after the user approves does the Bridge create the web view and load anything.

GET replay loads the captured URL. POST replay loads a generated HTML document that submits the captured fields as a form. The web view uses `WKWebsiteDataStore.default()` and leaves WebKit's user agent unchanged. Its website data can persist across Bridge invocations; one process per Handoff does not mean a fresh cookie store each time. It is the Bridge's WebKit data store, independent of the originating browser's normal or private cookie store.

### Recognizing and returning the Callback

The WebKit navigation delegate examines main-frame GET and POST navigations before they complete. A Callback candidate must use HTTPS, have no embedded URL credentials, and leave the hostname of the original identity-provider request. A POST must also have readable form fields. The Entra adapter then recognizes:

- A destination matching the original `redirect_uri` by scheme, hostname, effective port, and path. Query and fragment can carry the authentication response and are not part of that destination comparison.
- A `SAMLResponse` in the destination query, or a nonempty `SAMLResponse` in a POST body, even when the original request did not reveal the assertion-consumer URL.
- OIDC form responses with `code`, `id_token`, or `error` at the original `redirect_uri`.

For POST, the Bridge first tries WebKit's request body as `application/x-www-form-urlencoded`. If WebKit has not retained the body, it inspects the submitting document for a matching form and extracts its fields. An explicitly different content type, such as multipart, cannot use that fallback. Navigations that do not qualify continue in WebKit; these checks identify Callbacks and do not filter every destination in the authentication chain.

Once the Bridge recognizes a Callback, it cancels that WebKit navigation and sends the URL, method, and any form fields over native messaging. Cancellation is expected here and is not reported as a failed login. The Extension parses the response and independently checks that its destination is HTTPS without embedded credentials.

For GET, the Extension navigates the original tab directly to the Callback URL. For POST, it stores the fields against that tab and opens its own Relay page there. The Relay page reads and deletes the payload before building a hidden-input form and submitting it to the Application. Reloading the Relay page cannot resubmit the same stored assertion. This lets the Application receive the Callback in the browser that started the login, with that browser's existing transaction context and subject to its cookie policies. The Bridge does not redeem authorization codes or validate SAML assertions on the Application's behalf. The detailed rules are in [Callback recognition](docs/spec/callback-recognition.md).

### Caller identity and Approval

Microsoft's native-app allowlist authorizes the Bridge to use Enterprise SSO. The Bridge separately controls which browsers may ask it to perform a Handoff. Before reading stdin or creating an `NSApplication`, it captures its parent's audit token through `task_name_for_pid` and `task_info(TASK_AUDIT_TOKEN)`, resolves the running code with `SecCodeCopyGuestWithAttributes`, and checks the designated code-signing requirement for Helium or Zen with `SecCodeCheckValidityWithErrors`. Those requirements include the browser's bundle identifier, Team ID, and Apple signing chain.

The audit token pins a particular process incarnation, avoiding a bare-PID reuse race. This authenticates the parent process; anonymous pipes do not expose an authenticated peer identity, and an Extension ID passed in command-line arguments would be forgeable. Code executing inside an accepted browser is still inside that browser's identity. That is why every Handoff also requires Approval in the Bridge's own native window before any authentication begins. The guarantees and accepted gaps are recorded in [caller authentication](docs/adr/0001-caller-authentication-by-parent-audit-token.md) and [per-Handoff Approval](docs/adr/0002-user-approval-before-every-handoff.md).

Entra-specific entry origins and Callback rules live in a build-time Identity provider adapter. One checked-in origins file generates the Swift and TypeScript constants and the manifests' host permissions, keeping request capture and native validation aligned. There is no runtime provider configuration. See [the adapter decision](docs/adr/0003-build-time-identity-provider-adapter-seam.md) for that boundary.

## Repository

| Path | Contents |
| --- | --- |
| `CONTEXT.md` | The glossary. Every capitalized domain term is defined there. |
| `bridge/` | The native app: a `BridgeCore` library and a thin executable. |
| `extension/` | The browser extension, one source tree and two manifests. |
| `packaging/` | The app and package builds, and the Chromium install script. |
| `docs/spec/` | The v1 specification. |
| `docs/adr/` | Architecture decision records. |
| `docs/research/` | Findings behind the decisions, with sources. |
| `docs/development/` | Running the two halves locally. |
| `docs/testing/` | The manual acceptance checklist. |
| `fixtures/protocol/` | The wire shapes, read by both halves' tests. |
| `assets/` | Icon masters and the generator that produces them. |

Build it yourself with `packaging/build-pkg.sh` and `node extension/build.mjs`. Both default to version `0.0.0`; only a tagged release carries a real version.
