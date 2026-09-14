# Enterprise SSO Bridge

> [!WARNING]
> This project is a work in progress. It is still being built and is not ready for use.

Lets third-party macOS browsers complete corporate single sign-on through the Mac's native Enterprise SSO path, which those browsers cannot reach on their own. You click the toolbar action in your browser, a small native app authenticates with the identity provider, and the sign-in finishes back in the tab you started from.

Without it, a browser outside Apple's and Microsoft's allowlist has no route to a Primary Refresh Token, so every sign-in means a password and an MFA prompt even on a Mac that is already authenticated to the tenant.

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
