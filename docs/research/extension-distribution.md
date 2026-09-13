# Extension distribution for Helium and Zen without an Apple Developer ID

Research for issue #9. Question: how can the Extension be delivered to users of Helium (Chromium fork) and Zen (Gecko fork) with a **fixed** extension ID, given that the Bridge's native-messaging host manifests hard-code that ID in `allowed_origins` / `allowed_extensions`, and the developer will not buy an Apple Developer ID. This document covers the browser-extension side only; Bridge code signing is out of scope.

Every claim below is tied to a file path in an upstream clone, a path on this Mac, or an official Mozilla/Google doc URL. Clones live under `~/.btca/agent/sandbox/` (`helium`, `helium-macos`, `desktop` = zen-browser/desktop, `firefox-sparse` = mozilla-firefox/firefox, `chromium-sparse` = chromium/chromium), all fetched 2026-09-11.

## Summary

Load-bearing facts:

1. **Zen does not require signed add-ons.** Zen's build turns off `MOZ_REQUIRE_SIGNING`, and the installed 1.22b app confirms it: `modules/AppConstants.sys.mjs` in its `omni.ja` contains `MOZ_REQUIRE_SIGNING: false`. With that build flag off, Firefox's `AddonSettings.REQUIRE_SIGNING` becomes a live preference getter on `xpinstall.signatures.required`, which Zen ships defaulting to `true` but **unlocked**. A user can set it to `false` in `about:config` and then install an unsigned `.xpi`. Zen is effectively an unbranded-equivalent build for add-on purposes while still looking like a release build.
2. **AMO unlisted signing is free, needs no Apple involvement, and pins the add-on ID.** Mozilla signs unlisted (self-distributed) XPIs through AMO; the signing certificate's common name *is* the add-on ID, which Gecko verifies on install. So `browser_specific_settings.gecko.id` is locked by the signature itself. Automated validation, typically under 24 hours.
3. **Helium's product directory on macOS is `net.imput.helium`, not `Helium`.** The spike's documented path `~/Library/Application Support/Helium/NativeMessagingHosts/` is wrong. `helium-macos` patches Chromium's `ProductDirNameForBundle` to return the literal string `net.imput.helium`, and the live profile on this Mac is at `~/Library/Application Support/net.imput.helium/` (that directory already contains an empty `NativeMessagingHosts/`).
4. **Zen uses Firefox's brand-independent Mozilla path** for native-messaging manifests: `~/Library/Application Support/Mozilla/NativeMessagingHosts/`. The string `Mozilla` is hard-coded in `nsXREDirProvider.cpp`, not derived from branding, so no Zen-specific path exists.
5. **Chromium blocks off-store CRX installs on macOS unless the Mac is MDM-managed.** Policy-driven off-store install works, but `FilterSensitivePolicies` rewrites any `ExtensionInstallForcelist` entry (or `ExtensionSettings` force/normal-installed entry) whose update URL is not the Chrome Web Store URL into a `[BLOCKED]` entry when `base::IsManagedOrEnterpriseDevice()` is false. On macOS that means MDM enrollment (checked via `/usr/bin/profiles status -type enrollment`) or AD/OD domain join. Official docs say it plainly: "Linux is the only platform where Chrome users can install extensions that are hosted outside of the Chrome Web Store."
6. **Unpacked (developer-mode) extensions in Chromium persist across restarts but require developer mode to stay ON.** `InstalledLoader::LoadAllExtensions` reloads them from prefs at startup, but `kExtensionDisableUnsupportedDeveloper` is `FEATURE_ENABLED_BY_DEFAULT` and `IsAllowedByUnpackedDeveloperModePolicy` disables any unpacked extension with `DISABLE_UNSUPPORTED_DEVELOPER_EXTENSION` the moment `extensions.ui.developer_mode` goes false.
7. **Chromium extension IDs are deterministic from the manifest `key`.** ID = first 16 bytes of SHA-256 over the DER public key, hex-encoded, with `0-f` remapped to `a-p`. Keep `key` in `manifest.json` and the ID is identical whether loaded unpacked, packed as `.crx`, or installed from the Web Store item that owns that key.

### Realistic options, ranked by user friction

**Zen (Gecko), best first:**

| Option | User steps | Cost | ID fixed by |
| --- | --- | --- | --- |
| AMO **unlisted** signed `.xpi`, hosted on your own site, installed by clicking the link in Zen | 1 click plus the install prompt; survives restarts; auto-updates if you ship `update_url` | Free AMO account | `browser_specific_settings.gecko.id`, enforced by the signing cert CN |
| AMO unlisted signed `.xpi` downloaded, then `about:addons` -> gear -> **Install Add-on From File** | 4 or 5 clicks; survives restarts | Free | same |
| Unsigned `.xpi` after the user flips `xpinstall.signatures.required` to `false` in `about:config` | `about:config` warning page, pref edit, then install; works because Zen builds with `MOZ_REQUIRE_SIGNING` off | Free | manifest ID only; nothing enforces it |
| `ExtensionSettings` policy with `install_url` (managed Macs) | Zero, once the profile is delivered; needs `EnterprisePoliciesEnabled` plus a managed plist for `app.zen-browser.zen` | Free | policy pins the ID it expects |
| `about:debugging` **Load Temporary Add-on** | Re-done after **every** browser restart | Free | manifest ID, but state is temporary |

**Helium (Chromium), best first:**

| Option | User steps | Cost | ID fixed by |
| --- | --- | --- | --- |
| Chrome Web Store **unlisted** item, installed from its CWS URL | 1 click; auto-updates. Requires the store to work in Helium, which is *not* verified (see section 2) | One-time CWS developer registration fee; full policy review even when unlisted | CWS item ID; mirror it into `manifest.json` `"key"` for dev builds |
| Load unpacked from a directory you ship (a folder inside the Bridge's payload) | Enable Developer mode, "Load unpacked", pick the folder; persists across restarts but developer mode must stay on forever | Free | `"key"` in `manifest.json` |
| `ExtensionInstallForcelist` / `ExtensionSettings` with a self-hosted update manifest, via `/Library/Managed Preferences/<user>/net.imput.helium.plist` | Zero, but **only works on an MDM-managed Mac** | Free | policy entry names the ID |
| Hand the user a `.crx` to drag onto `chrome://extensions` | Blocked on macOS: `CrxInstaller` returns `OFFSTORE_INSTALL_DISALLOWED` unless `ExtensionInstallSources` allows the origin, which is itself a policy | Free | n/a |

The asymmetry is the headline: Zen can be served a signed XPI from your own web server with one click and no MDM, while Helium's only no-MDM, no-store option is "load unpacked and never turn off developer mode".

## 1. Zen and Gecko add-on signing

### `xpinstall.signatures.required` is not enforced at build level, and the user can flip it

Zen's shared mozconfig turns the signing requirement off, outside any `ZEN_RELEASE` conditional (the `if test "$ZEN_RELEASE"` block closes before these lines):

```sh
# ~/.btca/agent/sandbox/desktop/configs/common/mozconfig:96
ac_add_options --with-unsigned-addon-scopes=app,system
...
# lines 105-107
# Allow loading unsigned extensions
export MOZ_REQUIRE_SIGNING=
mk_add_options MOZ_REQUIRE_SIGNING=
```

Firefox's add-on code branches on exactly that:

```js
// firefox-sparse/toolkit/mozapps/extensions/internal/AddonSettings.sys.mjs
const PREF_SIGNATURES_REQUIRED = "xpinstall.signatures.required";
...
if (AppConstants.MOZ_REQUIRE_SIGNING && !Cu.isInAutomation) {
  makeConstant("REQUIRE_SIGNING", true);
} else {
  XPCOMUtils.defineLazyPreferenceGetter(
    AddonSettings, "REQUIRE_SIGNING", PREF_SIGNATURES_REQUIRED, false);
}
```

`makeConstant` defines a non-writable property; the `else` branch makes it track the pref at runtime. The enforcement points consume it through `XPIDatabase.mustSign` (`XPIDatabase.sys.mjs:2639-2648`), and `XPIInstall.sys.mjs:1666-1673` refuses the install when `signedState <= AddonManager.SIGNEDSTATE_MISSING`.

Verified against the **installed** app rather than just the repo. Extracting `omni.ja` from `/Applications/Zen Browser.app/Contents/Resources/`:

- `modules/AppConstants.sys.mjs` line 113-115: `MOZ_REQUIRE_SIGNING: false,` and `MOZ_UNSIGNED_APP_SCOPE: true,`
- `greprefs.js:1153`: `pref("xpinstall.signatures.required", false);`
- and from `Contents/Resources/browser/omni.ja`, `defaults/preferences/firefox.js:29` and `:1646`: `pref("xpinstall.signatures.required", true);`

So the app-level default wins and ships as `true`, with no `locked` flag, so `about:config` can override it. Zen's repo records the same intent declaratively in `prefs/firefox/extensions.yaml` (`- name: xpinstall.signatures.required` / `value: true`), and its pref generator only emits a locked pref when the YAML entry says `locked: true` (`tools/ffprefs/src/main.rs:222-227`); this entry does not.

Practical answer: **Zen release builds do not enforce signing at the build level, and a user can turn the requirement off in `about:config`.** Zen is not branded "unbranded" (it builds with `MOZILLA_OFFICIAL=1` per `configs/common/mozconfig`), but for add-ons it behaves like Mozilla's unbranded/Developer-Edition builds.

### AMO unlisted self-distribution

From Mozilla's Extension Workshop:

- Unlisted is the self-distribution channel: "Self-distributed add-ons are sometimes referred to as 'unlisted' extensions because they cannot be publicly viewed or installed from AMO."
- Signing route: web upload through the AMO Developer Hub, `web-ext sign`, or the AMO submission APIs. All are available for unlisted.
- Timing: "all add-ons undergo automated validation before they are signed. It can take up to 24 hours for your submission to be signed and published, or longer if your submission is selected for manual review." Unlisted add-ons remain subject to manual review at any time after submission.
- Install by file: `about:addons` -> settings cog -> **Install Add-on From File** -> pick the `.xpi` -> **Add**. Documented step-by-step on the "Installing self-distributed extensions" page.
- Install by web download: the server must send `Content-Type: application/x-xpinstall`; then clicking a plain link installs it. `InstallTrigger` is gone as of Firefox 144, so use a plain link.
- Prepare-for-file-install step 1 is literally "Include an ID in the extension's `manifest.json`" under `browser_specific_settings.gecko.id`.

An AMO developer account is required to submit. The pages I read describe no registration fee (unlike the Chrome Web Store, which states one explicitly). I did not find a fee page for AMO, so treat "free" as inferred from the absence of any fee in the submission docs, not as a quoted fact.

### Does AMO signing pin the add-on ID?

Yes, and Gecko enforces it cryptographically rather than by convention:

```js
// firefox-sparse/toolkit/mozapps/extensions/internal/XPIInstall.sys.mjs:864-877
function getSignedStatus(aRv, aCert, aAddonID) {
  let expectedCommonName = aAddonID;
  if (aAddonID && aAddonID.length > 64) {
    expectedCommonName = computeSha256HashAsString(aAddonID);
  }
  switch (aRv) {
    case Cr.NS_OK:
      if (expectedCommonName && expectedCommonName != aCert.commonName) {
        return AddonManager.SIGNEDSTATE_BROKEN;
      }
```

The signing certificate AMO issues carries the add-on ID as its common name. Change `browser_specific_settings.gecko.id` after signing and the package is `SIGNEDSTATE_BROKEN`. This is the property the Bridge wants: the `allowed_extensions` entry in the native manifest cannot drift from what is actually installed.

### Enterprise policies, and whether Zen honors them

Firefox's policy engine is compiled in unless `--disable-system-policies` is passed (`firefox-sparse/toolkit/moz.configure:4288-4293`); Zen's mozconfigs do not pass it. Two providers matter on macOS:

- **`policies.json`**, read from `XREAppDist` + `policies.json`, i.e. `<App>.app/Contents/Resources/distribution/policies.json` (`EnterprisePoliciesParent.sys.mjs:694-723`, and Mozilla's policy-templates README says the same for Mac). That directory does not exist in the shipped Zen bundle, so it would have to be created inside `/Applications/Zen Browser.app`, which breaks the app's own code signature. Not attractive.
- **macOS managed preferences**, read through `nsIMacPreferencesReader`:

```objc
// firefox-sparse/xpcom/base/nsMacPreferencesReader.mm
nsMacPreferencesReader::PoliciesEnabled(bool* aPoliciesEnabled) {
  NSString* policiesEnabledStr =
      [NSString stringWithUTF8String:ENTERPRISE_POLICIES_ENABLED_KEY];
  *aPoliciesEnabled = [[NSUserDefaults standardUserDefaults]
                          boolForKey:policiesEnabledStr] == YES;
```

`ENTERPRISE_POLICIES_ENABLED_KEY` is `"EnterprisePoliciesEnabled"` (`xpcom/base/nsIMacPreferencesReader.idl`). `standardUserDefaults` is the running app's own preference domain, so for Zen that is **`app.zen-browser.zen`** (confirmed: `CFBundleIdentifier` of `/Applications/Zen Browser.app` is `app.zen-browser.zen`), layered with `/Library/Managed Preferences/<user>/app.zen-browser.zen.plist`. Keys are flattened with `__` and unflattened by `macOSPoliciesParser.unflatten`.

The two install-capable policies:

- `Extensions.Install` takes a list of file paths or URLs; it tries `FileUtils.File(location)` first and falls back to `Services.io.newURI`, then calls `installAddonFromURL` (`Policies.sys.mjs:1708-1739`). It runs once per modification of the policy value.
- `ExtensionSettings` with `installation_mode: force_installed` or `normal_installed` plus `install_url` also routes to `installAddonFromURL`, and `force_installed` additionally calls `disallowFeature("disable-extension:<id>")` (`Policies.sys.mjs:1809-1841`). `installAddonFromURL` verifies the downloaded add-on's ID equals the expected ID and cancels otherwise (`PoliciesHelpers.sys.mjs:553-561`).

Both go through `AddonManager.getInstallForURL`, so they are still subject to `mustSign`. A policy does not bypass signing; it bypasses the *user prompt*. Mozilla's own enterprise guidance agrees: use AMO unlisted signing, or deploy ESR/unbranded and flip `xpinstall.signatures.required`.

**Not verified:** that Zen actually applies a policy delivered in `/Library/Managed Preferences/<user>/app.zen-browser.zen.plist` on this machine. The code path is brand-independent and nothing in the Zen repo disables it, but I did not install a profile and observe `about:policies`. That is a 10-minute empirical check if the policy route matters.

Also note `extensions.autoDisableScopes` ships as `15` (Zen's `browser/omni.ja`, `defaults/preferences/firefox.js:23`), so sideloaded add-ons in non-profile scopes arrive disabled and need user approval. Combined with `--with-unsigned-addon-scopes=app,system`, the unsigned exemption applies to app/system scopes, not the profile scope, which is one more reason the plain `xpinstall.signatures.required` route is the meaningful one for unsigned builds.

## 2. Helium and Chromium install paths

### Unpacked / developer mode

- **Persistence:** unpacked extensions are recorded in the profile's extension prefs and reloaded on startup by `InstalledLoader::LoadAllExtensions` (`chromium-sparse/chrome/browser/extensions/installed_loader.cc:347-360`), which iterates `extension_prefs_->GetInstalledExtensionsInfo()` and handles `mojom::ManifestLocation::kUnpacked` (line 612). So a "Load unpacked" install survives restarts as long as the source directory still exists at the same path.
- **Developer mode must stay on:**

```cpp
// chromium-sparse/chrome/browser/extensions/extension_management.cc:375-395
bool ExtensionManagement::IsAllowedByUnpackedDeveloperModePolicy(
    const Extension& extension) {
  if (!base::FeatureList::IsEnabled(
          extensions_features::kExtensionDisableUnsupportedDeveloper)) return true;
  if (!extension.is_extension()) return true;
  if (extension.location() != mojom::ManifestLocation::kUnpacked) return true;
  if (extension.creation_flags() & extensions::Extension::INSTALLED_VIA_CDP) return true;
  bool in_developer_mode =
      profile_->GetPrefs()->GetBoolean(prefs::kExtensionsUIDeveloperMode);
  return in_developer_mode;
}
```

`kExtensionDisableUnsupportedDeveloper` is `BASE_FEATURE(..., base::FEATURE_ENABLED_BY_DEFAULT)` (`extensions/common/extension_features.cc:129-130`), and `ExtensionService::CheckManagementPolicy` adds `disable_reason::DISABLE_UNSUPPORTED_DEVELOPER_EXTENSION` when the check fails (`chrome/browser/extensions/extension_service.cc:596-600`). The reason is documented in `extensions/browser/disable_reason.h:60-62`: "Disabled because the extension is a 'developer extension' (for example, an unpacked extension) while the developer mode is OFF."

- **The old "Disable developer mode extensions" startup bubble:** I could not find it in current Chromium. Listing `chrome/browser/extensions`, `chrome/browser/ui/extensions`, `extensions/browser`, and `chrome/browser/ui` for filenames matching `dev_mode|developer` returns only the `developer_private` API files; there is no `dev_mode_bubble_delegate.cc` in trunk. This is a negative search result, not proof of removal history, but the modern behavior is the hard gate above rather than a nag bubble. `ExtensionDeveloperModeSettings` (policy, Chrome 128+) can forbid the user from enabling developer mode at all, which would kill the unpacked route on a locked-down fleet.

### Does Helium still support off-store CRX via policy?

Helium does not touch the policy machinery. Grepping all of `helium/patches` for `chrome_browser_policy_connector`, `policy_loader_mac`, `policy_loader_common`, and `BaseBundleID` finds no hits in any extension/policy file, and the only `policy`-named patches in `patches/series` are `helium/core/sync/datatype-policy.patch` and `helium/core/webrtc-default-handling-policy.patch`. `helium-macos/patches` contains nothing policy-related either.

Helium's webstore changes are narrowly scoped to the store's own URLs:

- `patches/helium/core/proxy-extension-downloads.patch` replaces `kChromeWebstoreUpdateURL` with a domain-substituted placeholder and routes webstore update traffic through Helium's own service (`prefs::kHeliumExtProxyEnabled`, default true).
- The same patch adds `extension_urls::CanPatchUpdateUrl`, which returns true **only** when the URL's host equals `clients2.google.com`:

```cpp
// helium/patches/helium/core/proxy-extension-downloads.patch (new file manifest_url_patcher.cc)
bool CanPatchUpdateUrl(const GURL& url) {
    GURL chrome_webstore = GetOriginalWebstoreUpdateUrl();  // clients2.google.com/service/update2/crx
    return chrome_webstore.host() == url.host();
}
```

So a **self-hosted** `update_url` is passed through untouched. `patches/ungoogled-chromium/disable-webstore-urls.patch` additionally makes `ChromeContentVerifierDelegate::IsFromStore` return false for anything the `InstallVerifier` does not consider in-store, which removes the "extensions must match a Google-signed manifest" content-verification path rather than adding restrictions.

Conclusion: Helium keeps Chromium's enterprise-policy install mechanism intact, including self-hosted update manifests, and removes Chrome Web Store *dependence* for updates rather than the store code paths themselves.

### The current Chromium rule for off-store installs

Two separate gates:

1. **Manual `.crx` install.** `CrxInstaller` starts with `off_store_install_allow_reason_(OffStoreInstallDisallowed)` (`extensions/browser/crx_installer.cc:169`) and returns `CrxInstallErrorDetail::OFFSTORE_INSTALL_DISALLOWED` for a user-downloaded, non-gallery install (lines ~408-418). The escape hatch is the `ExtensionInstallSources` policy, consumed by `ExtensionManagement::IsOffstoreInstallAllowed`, which "disallow[s] by default" when no install sources are set (`chrome/browser/extensions/extension_management.cc:309-324`) and requires both the CRX URL and its referrer to match a configured pattern. Google's own policy description says the pre-Chrome-21 click-to-install flow is otherwise gone.
2. **Policy-driven install on an unmanaged Mac gets filtered.** This is the decisive constraint:

```cpp
// chromium-sparse/components/policy/core/common/policy_loader_common.cc
// FilterSensitiveExtensionsInstallForcelist():
    // Only allow custom update urls in enterprise environments.
    if (!base::EqualsCaseInsensitiveASCII(entry.substr(pos + 1),
                                          kChromeWebstoreUpdateURL)) {
      policy_list_value->GetList()[i] =
          base::Value(kBlockedExtensionPrefix + entry);   // "[BLOCKED]" + entry
```

`FilterSensitiveExtensionSettings` does the same for `ExtensionSettings` entries whose `installation_mode` is `force_installed`/`normal_installed` and whose `update_url` is not the Web Store URL. `PolicyLoaderMac::Load` calls `FilterSensitivePolicies` when the device is not managed:

```objc
// components/policy/core/common/policy_loader_mac.mm:38-44, 146-161
bool ShouldHonorPolicies() {
  return base::IsManagedOrEnterpriseDevice();
}
...
  bool should_filter;
  if (base::FeatureList::GetInstance() &&
      base::FeatureList::IsEnabled(features::kUseManagementServiceForSensitivePolicies)) {
    should_filter = ShouldFilterSensitivePolicies();
  } else {
    should_filter = !ShouldHonorPolicies();
  }
  if (should_filter) FilterSensitivePolicies(&chrome_policy);
```

On macOS, "managed" means MDM enrollment or domain join, determined by shelling out to `profiles`:

```objc
// chromium-sparse/base/enterprise_util_mac.mm
bool IsManagedDevice() {
  base::MacDeviceManagementState mdm_state = base::IsDeviceRegisteredWithManagement();
  return mdm_state == kLimitedMDMEnrollment || kFullMDMEnrollment || kDEPMDMEnrollment;
}
...
    std::vector<std::string> profiles_argv{"/usr/bin/profiles", "status", "-type", "enrollment"};
```

The policy documentation states the same rule in prose: "On macOS instances, apps and extensions from outside the Chrome Web Store can only be force installed if the instance is managed via MDM, joined to a domain via MCX or enrolled in Chrome Enterprise Core" (`ExtensionInstallForcelist.yaml`). And the Chrome docs: "Linux is the only platform where Chrome users can install extensions that are hosted outside of the Chrome Web Store."

Practical consequence for this project: the off-store-hosting route works on Max's Jamf-managed corporate Mac, and does **not** work for an unmanaged personal Mac. Any public release notes for Helium need to say that.

### macOS policy domain for Helium

Chromium reads policies from the app's own `CFPreferences` domain, except for Google-branded builds which force `com.google.Chrome`:

```cpp
// chromium-sparse/chrome/browser/policy/chrome_browser_policy_connector.cc:323-341
#if BUILDFLAG(GOOGLE_CHROME_BRANDING)
  CFStringRef bundle_id = CFSTR("com.google.Chrome");
#elif BUILDFLAG(GOOGLE_CHROME_FOR_TESTING_BRANDING)
  CFStringRef bundle_id = CFSTR("com.google.ChromeForTesting");
#else
  base::apple::ScopedCFTypeRef<CFStringRef> bundle_id_scoper =
      base::SysUTF8ToCFStringRef(base::apple::BaseBundleID());
  CFStringRef bundle_id = bundle_id_scoper.get();
#endif
  auto loader = std::make_unique<PolicyLoaderMac>(..., PolicyLoaderMac::GetManagedPolicyPath(bundle_id),
      std::make_unique<MacPreferences>(), bundle_id);
```

and the watched file is:

```cpp
// components/policy/core/common/policy_loader_mac.mm:178-195
base::FilePath PolicyLoaderMac::GetManagedPolicyPath(CFStringRef bundle_id) {
  ... NSLibraryDirectory ... "Managed Preferences" / getlogin() /
      (base::SysCFStringRefToUTF8(bundle_id) + ".plist");
```

Helium is not Google-branded (its `flags.gn` sets no branding flags; `patches/helium/core/change-chromium-branding.patch` rewrites `chrome/app/theme/chromium/BRANDING` with `MAC_BUNDLE_ID=net.imput.helium` and `MAC_TEAM_ID=S4Q33XPHB4`), and the installed app confirms `CFBundleIdentifier = net.imput.helium`. So:

- Policy domain: **`net.imput.helium`**
- Managed plist: **`/Library/Managed Preferences/<username>/net.imput.helium.plist`**
- Helium does **not** rename or redirect the policy domain; it inherits the unbranded `BaseBundleID()` behavior.

Mandatory vs recommended still follows `AppValueIsForced` (`policy_loader_mac.mm:126-135`), so a configuration-profile-delivered (forced) key is `POLICY_LEVEL_MANDATORY`.

### Chrome Web Store unlisted

- Registration: "you must register as a CWS developer and pay a one-time registration fee." The registration page does not state the amount, so I am not quoting one.
- Visibility: **Unlisted** "does not create a listing on the Chrome Web Store, but does allow anyone to install your item if they know its Chrome Web Store URL." There is no review shortcut: "All visibility settings have the same policy requirements and will go through the same review process."
- ID stability: the CWS item ID is assigned at first upload and is stable for that item. To make local/unpacked builds share it, copy the item's public key from the dashboard's Package tab -> "View public key" into `manifest.json` as `"key"`, which is exactly what Google's `key` documentation prescribes.

**Not verified:** whether a Helium user can actually install from a Chrome Web Store URL. Helium's `patches/ungoogled-chromium/disable-webstore-urls.patch` and `patches/helium/core/fixups-chrome-webstore-script.patch` modify webstore integration, and `proxy-extension-downloads.patch` reroutes update traffic through Helium's service. I read the patches but did not run Helium against a CWS item page, so I cannot claim the CWS install button works there. This needs an empirical test before treating CWS-unlisted as the Helium answer.

## 3. Extension ID stability

**Chromium.** The ID is derived from the public key, and the `key` manifest field supplies that key:

```cpp
// chromium-sparse/extensions/common/extension.cc:159-179
  if (const base::Value* public_key = manifest.Find(keys::kPublicKey)) {
    std::string public_key_bytes;
    if (!public_key->is_string() ||
        !Extension::ParsePEMKeyBytes(public_key->GetString(), &public_key_bytes)) { ... }
    *extension_id = crx_file::id_util::GenerateId(public_key_bytes);
    return true;
  }
  ...
  *extension_id = crx_file::id_util::GenerateIdForPath(path);
```

```cpp
// chromium-sparse/components/crx_file/id_util.cc
// First 16 bytes of SHA256 hashed public key.
constexpr size_t kIdSize = 16;
std::string GenerateId(base::span<const uint8_t> input) {
  return GenerateIdFromHash(crypto::hash::Sha256(input));
}
std::string GenerateIdFromHash(base::span<const uint8_t> hash) {
  std::string result = base::HexEncode(hash.first(kIdSize));
  ConvertHexadecimalToIDAlphabet(&result);   // '0'-'f' -> 'a'-'p'
  return result;
}
```

So: **with `key` present, unpacked and packed installs get the same 32-character ID**; without it, an unpacked load falls back to hashing the *directory path*, so the ID changes if the folder moves. The spike already relies on this: its `extension/manifest.json` carries a `key`, and the resulting ID `kdiebicpjepfecbnbpcdonoabecbecml` is what the spike's native manifest lists in `allowed_origins`.

Derivation recipe: base64-decode the `key` value to DER bytes, SHA-256 them, take the first 16 bytes, hex-encode lowercase, then map each hex digit `0-f` to `a-p`.

**Gecko.** The ID comes from `browser_specific_settings.gecko.id` (Mozilla's install-from-file instructions make it step 1), and after AMO signing it is additionally pinned by the certificate CN check in `getSignedStatus` shown in section 1. Email-address-style IDs are recommended. The spike uses `sso-handoff-probe@maxanderson.local`.

## 4. Native-messaging host manifest locations on macOS

### Helium

Chromium's user-level manifest directory is `DIR_USER_DATA` + `NativeMessagingHosts`, and `DIR_USER_DATA` on macOS is `~/Library/Application Support/` + `ProductDirName()`. `ProductDirName()` reads `CrProductDirName` from the outer bundle's `Info.plist` and otherwise falls back to a build-flag default (`chromium-sparse/chrome/common/chrome_paths_mac.mm:26-70`). The installed Helium `Info.plist` has **no** `CrProductDirName` key, but `helium-macos` patches the fallback directly:

```diff
--- a/chrome/common/chrome_paths_mac.mm
+++ b/chrome/common/chrome_paths_mac.mm
     if (!product_dir_name) {
-#if BUILDFLAG(GOOGLE_CHROME_FOR_TESTING_BRANDING)
-      product_dir_name = "Google/Chrome for Testing";
-#elif BUILDFLAG(GOOGLE_CHROME_BRANDING)
-      product_dir_name = "Google/Chrome";
-#else
-      product_dir_name = "Chromium";
-#endif
+      product_dir_name = "net.imput.helium";
     }
```
(`~/.btca/agent/sandbox/helium-macos/patches/helium/macos/change-product-dir-name.patch`)

Confirmed on this Mac: `~/Library/Application Support/net.imput.helium/` holds the live profile (`Local State`, `Default/`, modified during this session) and already contains an empty `NativeMessagingHosts/` directory.

Helium also patches the lookup to fall back to Chrome's directories, "since [third-party applications] might not know about our fork" (`helium/patches/helium/core/scan-chrome-native-messaging-hosts.patch`). The resulting search order in `LaunchContext::FindManifest` is:

1. `~/Library/Application Support/net.imput.helium/NativeMessagingHosts/<name>.json` (user-level, if user-level hosts are allowed)
2. `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/<name>.json` (Helium addition, `DIR_CHROME_USER_NATIVE_MESSAGING`)
3. `/Library/Application Support/Chromium/NativeMessagingHosts/<name>.json` (upstream `DIR_NATIVE_MESSAGING` for non-Google branding, `chrome_paths.cc:453-464`; `helium-macos` does not patch this)
4. `/Library/Google/Chrome/NativeMessagingHosts/<name>.json` (Helium addition, `DIR_CHROME_NATIVE_MESSAGING`)

**The spike's documented `~/Library/Application Support/Helium/NativeMessagingHosts/` is incorrect.** `~/scratch/macbook-migration/experiments/sso-handoff/README.md` does not actually name a Helium-side manifest path; it names only the Gecko one. Wherever the `Helium` spelling came from, the Bridge installer must write to `net.imput.helium`. Slot 2 (`Google/Chrome`) is an interesting alternative: one manifest there would serve Chrome, Helium, and other Chromium forks that adopt the same fallback, at the cost of registering with browsers the Bridge may not want as Callers.

### Zen

Gecko resolves the directory from two brand-independent dir-service keys, then appends a platform-specific slug:

```js
// firefox-sparse/toolkit/components/extensions/NativeManifests.sys.mjs:13-20, 36-43
const DASHED = AppConstants.platform === "linux";
const TYPES = { stdio: DASHED ? "native-messaging-hosts" : "NativeMessagingHosts", ... };
...
        let dirs = [
          Services.dirsvc.get("XREUserNativeManifests", Ci.nsIFile).path,
          Services.dirsvc.get("XRESysNativeManifests", Ci.nsIFile).path,
        ];
```

and both keys hard-code `Mozilla` on macOS:

```cpp
// firefox-sparse/toolkit/xre/nsXREDirProvider.cpp:417-426
  else if (!strcmp(aProperty, XRE_SYS_NATIVE_MANIFESTS)) {
    rv = ::GetSystemParentDirectory(getter_AddRefs(file));   // /Library/Application Support/Mozilla
  } else if (!strcmp(aProperty, XRE_USER_NATIVE_MANIFESTS)) {
    // Keep forcing the legacy path for compatibility
    rv = GetUserDataDirectoryHome(getter_AddRefs(file), false, /* aForceLegacy */ true);
    ...
    rv = file->AppendNative("Mozilla"_ns);     // ~/Library/Application Support/Mozilla
```

The comment on `GetSystemParentDirectory` states it outright: "On OSX this is /Library/Application Support/Mozilla". Nothing in the Zen repo overrides these. So:

- User: `~/Library/Application Support/Mozilla/NativeMessagingHosts/<name>.json`
- System: `/Library/Application Support/Mozilla/NativeMessagingHosts/<name>.json`

This matches the spike, which states "Gecko native messaging uses the manifest under `~/Library/Application Support/Mozilla/NativeMessagingHosts/`". On this Mac `~/Library/Application Support/Mozilla/NativeMessagingHosts/` exists and is populated, and Zen's own profile data lives separately at `~/Library/Application Support/zen/`.

Caveat worth writing down: because Zen shares Firefox's `Mozilla` path, one manifest registers the Bridge with **every** Gecko browser on the machine that reads that path, Firefox included. The `allowed_extensions` list is the only thing narrowing that, and the Bridge's Caller check is what actually has to enforce browser identity.

## 5. Browser-specific gotchas for a toolbar-action extension distributed off-store

**Chromium / Helium**

- Extension state is per profile. An unpacked install in one Helium profile does not exist in another; the toolbar action must be pinned per profile too. The spike hit the related incognito case and had to set `"incognito": "split"` and ask the user to enable "Allow in incognito".
- Developer mode is a permanent dependency for the unpacked route (section 2). If the user ever turns it off, the Extension is disabled with `DISABLE_UNSUPPORTED_DEVELOPER_EXTENSION`, and re-enabling requires turning developer mode back on. A managed `ExtensionDeveloperModeSettings: 1` policy would make the route impossible.
- Unpacked installs are pinned to a filesystem path. Move or delete the directory and the extension breaks; without `key` in the manifest, moving it also changes the ID and silently breaks the native manifest's `allowed_origins`. Always ship `key`.
- `manifest.json` for an off-store-hosted CRX must contain `update_url`, and the hosting server must not send `X-Content-Type-Options: nosniff` (Chrome's self-host doc lists the exact acceptable content types). This matters only if the MDM-policy route is used.
- Native messaging registration is per browser product directory, so the Bridge's installer needs one manifest per Chromium fork it supports unless it relies on Helium's `Google/Chrome` fallback.

**Gecko / Zen**

- `about:debugging` "Load Temporary Add-on" is gone on restart. Mozilla documents the limitation, and the spike's own README says "Temporary installation lasts until browser restart". It is fine for development, unusable for distribution.
- A temporary add-on without an explicit ID also gets a generated ID, which would break `allowed_extensions`. The spike's Zen manifest sets `browser_specific_settings.gecko.id` for exactly this reason.
- If the user flips `xpinstall.signatures.required` to `false`, that weakens add-on security for their whole profile, not just for this Extension. A signed unlisted XPI avoids asking users to do that.
- Sideloaded (non-profile-scope) add-ons land disabled because Zen ships `extensions.autoDisableScopes = 15`; they need explicit user enablement in `about:addons`.
- Private-browsing access is a separate per-add-on grant in Gecko, the analogue of Chromium's incognito setting.

**Both**

- The Extension ID is in the Bridge's native manifest, so any change to distribution channel that changes the ID is a breaking change for the Bridge installer. Pin `key` (Chromium) and `browser_specific_settings.gecko.id` (Gecko) from the start, before the first release, and treat them as part of the wire contract.

## Sources

Local clones (all fetched 2026-09-11):

- `~/.btca/agent/sandbox/helium` at `52d17a26f29b6a86dde7730e49e825cc98437a3c` (`chromium_version.txt` = 153.0.8010.36)
  - `patches/helium/core/change-chromium-branding.patch`, `patches/helium/core/scan-chrome-native-messaging-hosts.patch`, `patches/helium/core/proxy-extension-downloads.patch`, `patches/ungoogled-chromium/disable-webstore-urls.patch`, `flags.gn`, `patches/series`
- `~/.btca/agent/sandbox/helium-macos` (depth-1 `main`)
  - `patches/helium/macos/change-product-dir-name.patch`, `sign_and_package_app.sh`
- `~/.btca/agent/sandbox/desktop` (zen-browser/desktop, `22961e97d85e9bd487ad2fce0807f54ef421ae6e`, branch `dev`)
  - `configs/common/mozconfig`, `configs/macos/mozconfig`, `prefs/firefox/extensions.yaml`, `tools/ffprefs/src/main.rs`, `surfer.json`
- `~/.btca/agent/sandbox/chromium-sparse` (chromium/chromium, `3a70ba4712669bc045c08fee0363fa679f336f6a`)
  - `chrome/common/chrome_paths_mac.mm`, `chrome/common/chrome_paths.cc`, `chrome/browser/policy/chrome_browser_policy_connector.cc`, `components/policy/core/common/policy_loader_mac.mm`, `components/policy/core/common/policy_loader_common.cc`, `base/enterprise_util_mac.mm`, `components/crx_file/id_util.cc`, `extensions/common/extension.cc`, `extensions/browser/crx_installer.cc`, `extensions/browser/install_verifier.cc`, `extensions/browser/disable_reason.h`, `chrome/browser/extensions/extension_management.cc`, `chrome/browser/extensions/extension_service.cc`, `chrome/browser/extensions/installed_loader.cc`, `extensions/common/extension_features.cc`, `components/policy/resources/templates/policy_definitions/Extensions/{ExtensionInstallForcelist,ExtensionInstallSources,ExtensionDeveloperModeSettings}.yaml`
- `~/.btca/agent/sandbox/firefox-sparse` (mozilla-firefox/firefox, depth-1 `main`)
  - `toolkit/mozapps/extensions/internal/AddonSettings.sys.mjs`, `.../XPIInstall.sys.mjs`, `.../XPIDatabase.sys.mjs`, `toolkit/components/extensions/NativeManifests.sys.mjs`, `toolkit/xre/nsXREDirProvider.cpp`, `toolkit/components/enterprisepolicies/{EnterprisePoliciesParent,macOSPoliciesParser,PoliciesHelpers}.sys.mjs`, `browser/components/enterprisepolicies/Policies.sys.mjs`, `xpcom/base/{nsMacPreferencesReader.mm,nsIMacPreferencesReader.idl}`, `toolkit/moz.configure`

On this Mac (read-only inspection):

- `/Applications/Helium.app/Contents/Info.plist` (`CFBundleIdentifier = net.imput.helium`, version 0.16.6.1, framework 152.0.7977.82; no `CrProductDirName` key)
- `/Applications/Zen Browser.app/Contents/Info.plist` (`CFBundleIdentifier = app.zen-browser.zen`, version 1.22b); no `Contents/Resources/distribution/` directory
- `/Applications/Zen Browser.app/Contents/Resources/omni.ja` -> `modules/AppConstants.sys.mjs` (`MOZ_REQUIRE_SIGNING: false`, `MOZ_UNSIGNED_APP_SCOPE: true`), `greprefs.js:1153`
- `/Applications/Zen Browser.app/Contents/Resources/browser/omni.ja` -> `defaults/preferences/firefox.js:23,29,1646`
- `~/Library/Application Support/net.imput.helium/` (live Helium profile, contains empty `NativeMessagingHosts/`), `~/Library/Application Support/Mozilla/NativeMessagingHosts/`, `~/Library/Application Support/zen/`
- `~/scratch/macbook-migration/experiments/sso-handoff/` (`README.md`, `extension/manifest.json`, `zen/manifest.json`, `net.maxanderson.sso_handoff_probe.json`)

Official documentation:

- https://extensionworkshop.com/documentation/publish/signing-and-distribution-overview/
- https://extensionworkshop.com/documentation/publish/self-distribution/
- https://extensionworkshop.com/documentation/publish/install-self-distributed/
- https://extensionworkshop.com/documentation/enterprise/enterprise-distribution/
- https://mozilla.github.io/policy-templates/
- https://developer.chrome.com/docs/extensions/reference/manifest/key
- https://developer.chrome.com/docs/extensions/how-to/distribute/host-on-linux
- https://developer.chrome.com/docs/webstore/cws-dashboard-distribution
- https://developer.chrome.com/docs/webstore/register

## What I could not verify

1. **Chrome Web Store installs inside Helium.** Helium patches webstore URLs and proxies extension downloads; I read the patches but never loaded a CWS item page in Helium. Until someone tries it, "CWS unlisted" is a hypothesis for Helium, not a route.
2. **Zen honoring a macOS configuration profile.** The code path (`EnterprisePoliciesEnabled` in the `app.zen-browser.zen` domain) is brand-independent and not disabled anywhere in Zen's tree, but I did not install a profile and check `about:policies` in Zen.
3. **AMO developer-account cost.** The submission docs I read mention no fee. I found no page stating "free", so I am reporting an absence rather than a confirmed fact.
4. **The Chrome Web Store registration fee amount.** The official registration page says "one-time registration fee" without a number.
5. **Whether the "Disable developer mode extensions" bubble was removed or merely relocated.** My filename search across `chrome/browser/extensions`, `chrome/browser/ui`, `chrome/browser/ui/extensions`, and `extensions/browser` found no such implementation in trunk; I did not trace the commit that removed it.
6. **Actual AMO signing turnaround for this specific Extension.** Mozilla documents "up to 24 hours"; a `nativeMessaging` + `webRequest` + `https://*/*` add-on that drives an authentication handoff is a plausible candidate for manual review, which could take longer.
