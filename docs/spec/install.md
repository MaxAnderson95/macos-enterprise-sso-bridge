# Install, update, and MDM setup

Settled in [issue #11](https://github.com/MaxAnderson95/macos-enterprise-sso-bridge/issues/11) under a standing constraint: no extension stores, no Apple signing or notarization, no enterprise policies, no automatic extension installation. This is a personal tool with one rollout target, and the steps live in the README. The supporting research is in `docs/research/extension-distribution.md`.

## Identifiers

| Thing | Value |
| --- | --- |
| Bundle ID | `tech.maxanderson.enterprise-sso-bridge` |
| Native-messaging host name | `tech.maxanderson.enterprise_sso_bridge` |
| Gecko add-on ID | `enterprise-sso-bridge@maxanderson.tech` |
| Chromium extension ID | Derived from the `key` field committed in `manifest.chromium.json` |

The host name deliberately differs from the bundle ID, because both engines reject hyphens: Chromium enforces `[a-z0-9._]` (`native_messaging_host_manifest.cc:22-40`) and Gecko enforces `^\w+(\.\w+)*$` in its `native_manifest.json` schema.

Both extension IDs are contracts with the native-messaging manifests, which name them in `allowed_origins` and `allowed_extensions` respectively.

## The package

An unsigned, payload-only `.pkg` with no postinstall script, installing exactly three things:

- `/Applications/Enterprise SSO Bridge.app`
- `/Library/Application Support/Chromium/NativeMessagingHosts/tech.maxanderson.enterprise_sso_bridge.json`
- `/Library/Application Support/Mozilla/NativeMessagingHosts/tech.maxanderson.enterprise_sso_bridge.json`

Both manifest directories are root-writable and system-wide, so no postinstall script, no console-user resolution, and no per-user placement is needed.

Helium's system-wide Chromium path is the unbranded literal `/Library/Application Support/Chromium/NativeMessagingHosts`, not a product-name-derived path (`chrome/common/chrome_paths.cc:453-478`). Its `scan-chrome-native-messaging-hosts.patch` adds two Google Chrome fallback directories to the search order; v1 does not write to them. A branded Chromium joining the Allowed browser set later would add that path.

## Installing the Chromium extension

`install-chromium-extension.sh`, committed to the repo and published as a release asset. It needs no root: it places the downloaded `.crx` under `~/Library/Application Support/`, then writes the external-prefs JSON to `~/Library/Application Support/net.imput.helium/External Extensions/<extension-id>.json` naming that resolved absolute path with a matching `external_version`.

The script exists because that JSON requires an absolute path and JSON has no variable expansion, so a committed file would otherwise hardcode one machine's home directory. It is idempotent, and it is the update path as well as the install path.

A user-level native-messaging registration takes precedence over the system-wide release registration. The script removes Helium's user-level manifest only when its name and development-build description match the Bridge, its target is an absolute path that no longer exists, and neither the manifest nor the target is a symlink. Other user-level registrations remain in place with a warning.

Helium performs the install at next launch and the user accepts it once. That click is unavoidable: `prompt_for_external_extensions` defaults enabled on macOS, and `ExtensionRegistrar` returns `DISABLE_EXTERNAL_EXTENSION` for any external install that has not been acknowledged. The acceptance UI is `MENU_ALERT`, a three-dot menu item rather than a bubble (`external_install_manager.cc:111-120`).

This was verified empirically against an isolated user-data-dir: a locally packed CRX referenced by an external-prefs JSON installed and unpacked into the profile with `location=2` (`EXTERNAL_PREF`) and `disable_reasons=[8192]`, which is `1 << 13`, `DISABLE_EXTERNAL_EXTENSION` (`extensions/browser/disable_reason.h:42`). That contradicts Google's documentation, which says local-CRX external installs were blocked on macOS in Chrome 44. No such enforcement exists in trunk; the modern equivalent is `InstallVerifier`, which is gated on `GOOGLE_CHROME_BRANDING` and therefore compiled out of Helium (`install_verifier.cc:68-75`).

## Installing the Gecko extension

Fully manual, no script. Set `xpinstall.signatures.required` to `false` in `about:config`, then `about:addons`, Install Add-on From File, and pick the `.xpi`.

Zen permits this because it builds with `MOZ_REQUIRE_SIGNING` empty, which leaves the pref live and unlocked. The pref stays `false` permanently: restoring signature enforcement while an unsigned add-on is installed would very likely disable it, since `isUsableAddon` rechecks `mustSign && !isCorrectlySigned` and signatures are reverified periodically.

Disk sideloading does not work at all in Zen: `MOZ_ALLOW_ADDON_SIDELOAD` is false in the shipped build, which freezes `AddonSettings.SCOPES_SIDELOAD` to `SCOPE_PROFILE`. The enterprise-policy route was proven to work from the plain user defaults domain with no MDM, but the no-policies constraint excludes it; it also shares a channel with any MDM-authored policy, and `CombinedProvider.mergePolicies` merges at whole-policy-name granularity with the plist provider outranking `policies.json`, so writing `ExtensionSettings` could silently clobber an administrator's entire extension policy.

## Updates

Nothing automatic on either half. A new release means installing the new `.pkg`, re-running the script, and re-installing the `.xpi` through the file picker.

The Bridge shows its version in the user-launch window, which links to the README rather than claiming any install status it cannot verify. Wire-level skew is caught by the protocol's `version` field; a stale-but-compatible pairing is not detected, which is accepted.

Sparkle was evaluated and rejected. It does work for an ad-hoc signed app, since its validator accepts an EdDSA-only match and explicitly supports ad-hoc signing, but its flow ends in quit-and-relaunch, which is meaningless for a process spawned per Handoff that exits immediately, and it would add an EdDSA private key to protect for the life of the project. Homebrew cask is closed on two independent grounds: `brew audit` runs a real Gatekeeper assessment on cask artifacts, and the notability floor for self-submission is 225 stars.

## What the README covers

The GUI install path leads, with the unsigned-package Gatekeeper refusal explained rather than hidden: roughly seven actions on a fresh Mac, because macOS 15 removed the Control-click override and the recovery path is System Settings, Privacy and Security, Open Anyway. `sudo installer -pkg ... -target /` appears as a note for anyone who prefers it.

Also covered: enabling private-browsing access for the extension in both browsers, and a full uninstall section listing every path, `pkgutil --forget` for the receipt, removal of both extensions, and explicitly restoring `xpinstall.signatures.required` to `true`, since that pref is a security-relevant change that would otherwise outlive the tool.

## MDM setup

One real requirement: the Enterprise SSO extension's `AppAllowList` must include `tech.maxanderson.enterprise-sso-bridge`. Without it the Bridge's `WKWebView` never reaches the platform SSO path and the Handoff is just a second browser.

Nothing else is fleet-deployable by design. Writing fleet instructions for a configuration that deliberately excludes stores, signing, and policies would be documenting something that cannot be deployed to a fleet.

## Carried as unverified

`sudo installer -pkg` on an unsigned quarantined package is an inference, not an observation: `pkgutil --expand-full` and `installer -pkginfo` both ran clean on one as a normal user, but sudo could not prompt for a password in the environment where this was investigated. The exact macOS 26 refusal dialog, and whether the Open Anyway row appears for a `.pkg` specifically, were not observed. Whether restoring `xpinstall.signatures.required` disables the Zen add-on was not tested.
