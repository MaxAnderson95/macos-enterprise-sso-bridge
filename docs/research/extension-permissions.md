# Extension permissions for passive Sign-in request capture

Research for issue #8. Question: what is the minimum permission set the Extension needs to observe the Sign-in request to the identity provider entry origin before the user clicks the toolbar action, hold it per tab, hand it to the Bridge, and drive the original tab to the Callback and the Relay page.

Verified against Chromium source (`chromium/src` at `main`, fetched 2026-09-11 from chromium.googlesource.com), Firefox source (`mozilla-firefox/firefox` at `main`, commit `b14ad10e3f7593276d59cede793ffbdd4b3a7a11`, 2026-09-11), and the Chrome and MDN reference docs. Every claim below cites the file and line it came from. Where I could not verify something, the text says so.

## Summary

The spike's `host_permissions: ["https://*/*"]` is not needed. For a `main_frame` navigation, both engines check host permission against the target URL only and skip the initiator/document check, so `https://login.microsoftonline.com/*` alone is sufficient to receive `onBeforeRequest` with `requestBody.formData` for the Application's cross-site POST or redirect into Entra.

Load-bearing facts:

- **Initiator is not required for main-frame navigations.** Chromium's event router calls `CanExtensionAccessURL` with `REQUIRE_HOST_PERMISSION_FOR_URL_AND_INITIATOR`, but that mode returns early for frame resource types before consulting the initiator (`web_request_permissions.cc:137-146`). A unit test asserts exactly the case we depend on: denied initiator plus allowed URL yields `kAllowed` for `MAIN_FRAME` (`web_request_permissions_unittest.cc:558`). Gecko reaches the same result by a different route: `ChannelWrapper::Matches` checks the document URL only when there is one, and for a top-level load the loading principal is null (`ChannelWrapper.cpp:660-683`, `nsILoadInfo.idl:252-254`).
- **No blocking permission is needed.** We only observe. Chromium MV3 removed `webRequestBlocking` for non-policy extensions; Gecko requires `webRequestBlocking` only when `"blocking"`/`"asyncBlocking"` appear in `extraInfoSpec` (`ext-webRequest.js:77-99`).
- **`storage.session` is memory-only and 10 MB in both engines**, survives background suspension, and is reachable from the Relay page because extension pages are trusted contexts by default.
- **Gecko has no background service worker in release.** Ship `background.scripts` plus `background.service_worker` in one manifest and let each engine pick; that is the documented cross-browser form.
- **One real Gecko caveat:** during early browser startup, a non-blocking `webRequest` listener is deliberately not primed (`ext-webRequest.js:140-148`), so a Sign-in request issued before the event page has started once after a browser restart can be missed. See question 4.
- **Incognito/private browsing is the sharpest divergence.** In Chromium, `incognito: "spanning"` (the default) cannot load an extension page into the main frame of an incognito tab, which breaks the Relay page there; `"split"` can, at the cost of a second extension instance. Firefox does not support `"split"` at all and does not need it, but the user must explicitly allow the extension in private windows.

### Recommended minimal manifest (Chromium / Helium)

```json
{
  "manifest_version": 3,
  "permissions": ["webRequest", "storage", "nativeMessaging", "activeTab"],
  "host_permissions": ["https://login.microsoftonline.com/*"],
  "background": { "service_worker": "background.js" },
  "action": {},
  "incognito": "split"
}
```

`activeTab` covers reading `tab.url` in the action click handler. `tabs` is not required: `tabs.update` needs no permission, and `activeTab` grants the URL for the clicked tab. Drop `"incognito": "split"` to `"spanning"` if the Handoff is not expected to work in incognito; see question 7 for the trade-off.

### Recommended minimal manifest (Gecko / Zen)

```json
{
  "manifest_version": 3,
  "permissions": ["webRequest", "storage", "nativeMessaging", "activeTab"],
  "host_permissions": ["https://login.microsoftonline.com/*"],
  "background": { "scripts": ["background.js"] },
  "action": {},
  "browser_specific_settings": { "gecko": { "id": "..." } }
}
```

No `incognito` key: the default is `"spanning"`, which in Firefox does allow extension pages as a tab's main frame. Omit the key rather than setting `"split"`, which Firefox downgrades to `"not_allowed"` (`Schemas.sys.mjs:354-373`). `browser_specific_settings.gecko.id` is required because the native-messaging host manifest lists extension IDs in `allowed_extensions`.

A single shared source tree with two manifests is the practical shape: `background.scripts` and `background.service_worker` can coexist in one manifest (Firefox uses the document, Chrome uses the worker), but `incognito` and `browser_specific_settings` differ, so two build outputs are cleaner.

## 1. Chromium: does `onBeforeRequest` with `["requestBody"]` fire for main-frame POSTs under a single host permission?

**Yes, and the initiator's host does not need to be permitted.**

The permission gate for every webRequest listener is `WebRequestEventRouter::ListenerMatchesRequest`, which calls:

```cpp
PermissionsData::PageAccess access =
    WebRequestPermissions::CanExtensionAccessURL(
        PermissionHelper::Get(&browser_context), listener.id.extension_id,
        request.url, request.frame_data.tab_id, crosses_incognito,
        WebRequestPermissions::
            REQUIRE_HOST_PERMISSION_FOR_URL_AND_INITIATOR,
        request.initiator, request.web_request_type);
```

(`extensions/browser/api/web_request/extension_web_request_event_router.cc:3110-3130`)

The name of that mode is misleading. Inside `CanExtensionAccessURLInternal`, the `REQUIRE_HOST_PERMISSION_FOR_URL_AND_INITIATOR` branch computes access for the target URL and then returns immediately for frame navigations:

```cpp
PermissionsData::PageAccess request_access =
    GetHostAccessForURL(*extension, url, tab_id);

bool is_navigation_request =
    web_request_type && IsWebRequestResourceTypeFrame(*web_request_type);

// Only require access to the initiator for sub-resource (non-navigation)
// requests. See crbug.com/41433450.
if (is_navigation_request) {
  return request_access;
}
```

(`extensions/browser/api/web_request/web_request_permissions.cc:133-146`; `IsWebRequestResourceTypeFrame` returns true for `MAIN_FRAME` and `SUB_FRAME`, same file lines 73-77)

The unit test pins this behavior. With host permissions for `google.com` (granted) and `example.com` (withheld), and `yahoo.com` denied:

```cpp
{kDeniedOrigin, kAllowedUrl, PageAccess::kDenied, PageAccess::kAllowed},
```

The two trailing values are `expected_access_subresource` and `expected_access_navigation`; the test then asserts the navigation value for both `SUB_FRAME` and `MAIN_FRAME` (`extensions/browser/api/web_request/web_request_permissions_unittest.cc:542-587`). So a main-frame navigation from an unpermitted `app.example.com` to a permitted `login.microsoftonline.com` is visible.

This contradicts the general statement in the Chrome docs that "an extension will be able to intercept a request only if it has host permissions to both the requested URL and the request initiator" (https://developer.chrome.com/docs/extensions/reference/api/webRequest). That sentence is accurate for sub-resources and wrong for frame navigations; the source and its test are the authority.

`requestBody` itself carries no additional permission check. The body is parsed when the `WebRequestInfo` is constructed, for any `POST` or `PUT` (`web_request_info.cc:133-174`, `:291-294`), and is only attached to the event payload when the listener asked for it:

```cpp
if ((extra_info_spec & ExtraInfoSpec::REQUEST_BODY) && request_body_) {
  result.Set(keys::kRequestBodyKey, request_body_->Clone());
```

(`web_request_event_details.cc:255-256`)

Parsing order is form-first, raw-second: `ParsedDataPresenter` runs before `RawDataPresenter`, and whichever succeeds first wins the `formData` or `raw` key (`web_request_info.cc:143-167`). The form parser is selected from the `Content-Type` header and accepts `application/x-www-form-urlencoded` and `multipart/form-data`; a missing `Content-Type` is treated as urlencoded (`form_data_parser.cc:312-345`). An Entra SAML POST with `SAMLRequest` and `RelayState` in a urlencoded body therefore lands in `requestBody.formData` as `{SAMLRequest: ["..."], RelayState: ["..."]}`.

One documented value-type caveat: per the `FormDataItem` type, urlencoded values arrive as strings when the data is valid UTF-8 and as `ArrayBuffer` otherwise; multipart values are always `ArrayBuffer` (https://developer.chrome.com/docs/extensions/reference/api/webRequest, "FormDataItem", Chrome 66+). Treat `formData` values as `string | ArrayBuffer` in the shared TypeScript types.

Additionally, `HideRequest` blanket-hides some requests regardless of permissions (WebUI renderers, Webstore, Safe Browsing, browser-initiated non-navigation requests) (`web_request_permissions.cc:248-408`). None of those categories cover `login.microsoftonline.com`.

## 2. Gecko: same questions

**Also yes, and also without initiator permission.** The mechanism is different.

Gecko's single gate is `ChannelWrapper::Matches`, called from `WebRequest.sys.mjs:895` for every registered listener:

```cpp
if (aExtension) {
  // Verify extension access to private requests
  if (isPrivate && !aExtension->PrivateBrowsingAllowed()) {
    return false;
  }
  if (!aExtension->CanAccessURI(urlInfo, false, false)) {
    return false;
  }
  if (!aOptions.mIsProxy || !aExtension->HasPermission(nsGkAtoms::proxy)) {
    if (!CanModify()) {
      return false;
    }
    auto origin = DocumentURLInfo();
    if (origin && !aExtension->CanAccessURI(*origin, false, false, true)) {
      return false;
    }
  }
}
```

(`toolkit/components/extensions/webrequest/ChannelWrapper.cpp:653-684`)

The `origin &&` guard is what saves us. `DocumentURLInfo()` derives from `GetDocumentURI()`, which reads `loadInfo->GetLoadingPrincipal()` (`ChannelWrapper.cpp:560-571, 619-628`), and the load-info contract states: "For `<iframe>` and `<frame>` loads, the LoadingPrincipal is the principal of the parent document. For top-level loads, the LoadingPrincipal is null." (`netwerk/base/nsILoadInfo.idl:251-254`). For a `main_frame` navigation the pointer is null, the initiator check is skipped, and only `CanAccessURI(FinalURLInfo())` matters. This matches MDN's note that `documentUrl` is undefined for a top-level document (https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/webRequest/onBeforeRequest).

Note that this is narrower than MDN's general guidance, which says an extension must hold host permissions for both the resource and the main page ("To intercept resources loaded by a page ... the extension must have the host permission for the resource as well as for the main page requesting the resource", https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/webRequest). That describes sub-resources; the source shows top-level navigations are exempt.

**`webRequestBlocking` is not needed.** Firefox gates it precisely on the `extraInfoSpec` strings, and silently drops them if the permission is absent:

```js
let blockingAllowed =
  eventName == "onAuthRequired"
    ? extension.hasPermission("webRequestBlocking") ||
      extension.hasPermission("webRequestAuthProvider")
    : extension.hasPermission("webRequestBlocking");
```

(`toolkit/components/extensions/parent/ext-webRequest.js:77-99`)

Since we pass only `["requestBody"]`, `webRequestBlocking` is unnecessary. `webRequestFilterResponse` is likewise irrelevant; it gates `filterResponseData`.

**`formData` decoding differs from Chromium in three ways worth knowing:**

1. Firefox decodes urlencoded bodies in JS with `decodeURIComponent` after replacing `+` with space, producing plain strings rather than Chromium's `string | ArrayBuffer`:

   ```js
   for (let part of getParts(stream, "&")) {
     let [name, value] = part
       .replace(/\+/g, " ")
       .split("=")
       .map(decodeURIComponent);
     formData.get(name).push(value);
   }
   ```

   (`toolkit/components/extensions/webrequest/WebRequestUpload.sys.mjs:365-377`)

   The destructuring discards anything after a second literal `=`. Correctly serialized form data percent-encodes `=` inside values as `%3D`, so base64 `SAMLRequest` padding is safe, but a hand-rolled body with a raw `=` in a value would be truncated. I did not test this against a live Entra POST.

2. When form parsing fails, Firefox returns `raw` plus a non-standard `lenientFormData` field that Chromium does not have, and truncates raw chunks at the `webextensions.webRequest.requestBodyMaxRawBytes` pref (`WebRequestUpload.sys.mjs:505-537`). I did not find that pref's default value.

3. Form parsing requires a seekable stream; non-seekable upload streams yield `null` and fall through to `raw` (`WebRequestUpload.sys.mjs:195-199` and the `createFormData` doc comment at `:410-414`).

Content-type selection mirrors Chromium for our case, handling `multipart/form-data` and `application/x-www-form-urlencoded` (`WebRequestUpload.sys.mjs:387-394`), except that Firefox has no "missing Content-Type implies urlencoded" fallback.

One operational note: Firefox logs a console error if the listener's URL filter does not overlap the extension's host permissions (`ext-webRequest.js:49-63`). Keep the `urls` filter at `https://login.microsoftonline.com/*` to stay inside the granted origins.

## 3. `storage.session`

**Chromium.** The schema declares it in-memory with a 10 MB quota:

```json
"session" : {
  "description": "Items in the <code>session</code> storage area are stored in-memory and will not be persisted to disk.",
  "properties": { "QUOTA_BYTES": { "value": 10485760, ... } }
}
```

(`extensions/common/api/storage.json:284-293`)

The backing store is `SessionStorageManager`, "manages the content stored in memory by" extensions, keyed per browser context with a per-extension quota (`extensions/browser/api/storage/session_storage_manager.h:23`, `:50`, `:200-201`; `storage_frontend.cc:330-341` dispatches the session namespace to it). Because it hangs off the `BrowserContext` and never touches disk, it dies with the browser process and survives service worker suspension. The docs state the clearing rules explicitly: "The storage is cleared if the extension is disabled, reloaded, updated, and when the browser restarts" and it is recommended for service workers (https://developer.chrome.com/docs/extensions/reference/api/storage).

**Gecko.** Same 10 MB number, held in a `WeakMap` of `QuotaMap` (a `Map` subclass) per extension:

```js
class QuotaMap extends Map {
  static QUOTA_BYTES = 10485760;
```

```js
export var extensionStorageSession = {
  buckets: new DefaultWeakMap(_extension => new QuotaMap()),
```

(`toolkit/components/extensions/ExtensionStorage.sys.mjs:528-529`, `:585-587`)

The quota is reported as 10 MB but **enforcement is off by default**, gated on `webextensions.storage.session.enforceQuota` defaulting to `false` (`ExtensionStorage.sys.mjs:13-16`, `:559`). The comment at `:592-594` says the getter reports "the future default of 10MB" even when unenforced. So in Firefox today a Handoff record larger than 10 MB would be stored rather than rejected; do not rely on the quota as a guard. The schema description confirms the lifetime: "kept in memory, and only until the either browser or extension is closed or reloaded" (`toolkit/components/extensions/schemas/storage.json:263-272`). MDN adds "When the browser stops, all session storage is cleared. When the extension is uninstalled, its associated session storage is cleared."

**Reachable from the Relay page.** Both engines gate `storage.session` on the trusted/untrusted context split, not on page-versus-background. Chromium's default access level is `TRUSTED_CONTEXTS`, defined as "contexts originating from the extension itself", and the docs say `storage.session` is "by default ... not exposed to content scripts", changeable with `setAccessLevel()` (https://developer.chrome.com/docs/extensions/reference/api/storage). An extension page such as the Relay page is a trusted context, so it can read and write without any change. MDN states the same default for Firefox. Firefox additionally marks the area `"allowedContexts": ["devtools"]` (`schemas/storage.json:264`), which widens rather than narrows access.

The `storage` permission is required in both engines to use any storage area.

## 4. Gecko event page versus Chromium service worker

**Firefox has no background service worker in release.** MDN: "`background.service_worker` is not supported (see Firefox bug 1573659)"; Firefox uses `background.scripts` or `background.page` (https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/background). The source reads `service_worker` only behind `WebExtensionPolicy.backgroundServiceWorkerEnabled` (`Extension.sys.mjs:1590-1596`), and when both a worker and a document are declared without `preferred_environment`, the document wins and Firefox logs a warning (`Extension.sys.mjs:1917-1930`). The documented cross-browser manifest declares both keys and lets each engine pick.

**`persistent` is rejected in MV3.** The Firefox manifest schema marks `background.persistent` `"max_manifest_version": 2` (`toolkit/components/extensions/schemas/manifest.json:155-160`), matching MDN's "Setting to `true` in Manifest V3 results in an error." Non-persistent is the only MV3 shape, so do not include the key.

**Yes, `onBeforeRequest` wakes a suspended event page.** `webRequest` is an `ExtensionAPIPersistent` whose `PERSISTENT_EVENTS` include `onBeforeRequest` (`ext-webRequest.js:139-160`). While the background is stopped, listeners are re-primed; a primed listener firing queues the event and emits `background-script-event`:

```js
let fireEvent = (...args) =>
  new Promise((resolve, reject) => {
    ...
    primed.pendingEvents.push({ args, resolve, reject });
    extension.emit("background-script-event");
  });
```

(`ExtensionCommon.sys.mjs:2562-2584`; the surrounding comment at `:2556-2558` confirms re-priming happens "because the event page has suspended")

That event starts the background page once a browser window has painted:

```js
extension.once("background-script-event", async () => {
  await ExtensionParent.browserPaintedPromise;
  extension.emit("start-background-script");
});
```

(`toolkit/components/extensions/parent/ext-backgroundPage.js:1006-1009`)

After the background stops, `primeBackground(false)` re-arms everything (`ext-backgroundPage.js:534-537`, `:600`), and `isInStartup = false` means the webRequest module primes non-blocking listeners normally. The idle timeout that suspends the page defaults to 30 s (`extensions.background.idle.timeout`, `ext-backgroundPage.js:27-35`).

**The early-startup gap.** During browser startup the webRequest module refuses to prime non-blocking listeners:

```js
primeListener(event, fire, params, isInStartup) {
  // During early startup if the listener does not use blocking we do not prime it.
  if (
    !isInStartup ||
    params[1]?.some(v => v === "blocking" || v === "asyncBlocking")
  ) {
    return super.primeListener(event, fire, params, isInStartup);
  }
}
```

(`ext-webRequest.js:140-148`)

Startup priming is further limited to modules flagged `startupBlocking` (`ExtensionCommon.sys.mjs:2533-2541`). Full priming is restored after `browserStartupPromise` resolves, when Firefox clears and re-primes all listeners with `isInStartup = false` (`ext-backgroundPage.js:1185-1219`). Practical consequence for the Bridge: immediately after a Firefox/Zen restart with session restore, a Sign-in request issued before that point can be missed. Since the user must click the toolbar action anyway, the recovery path is to detect a missing stored Sign-in request for the tab and ask the user to retry the sign-in, rather than to assume capture always succeeded.

MDN describes the blocking-listener variant of this as a feature ("Requests at browser startup": a blocking listener registered at startup starts the extension early). We do not want a blocking listener, so we accept the gap.

**Zen.** I could not verify anything Zen-specific. Zen is a Firefox fork and I found no evidence of changes to `WebRequest.sys.mjs`, `ChannelWrapper.cpp`, or the background-page lifecycle; treat all Gecko findings as applying to Zen until tested on a Zen build. Same for Helium and Chromium: Helium is an ungoogled-chromium-derived patch set (`~/.btca/agent/sandbox/helium` is a patch repo over `chromium_version.txt`), and I did not audit its patches for extension-API changes.

## 5. `activeTab` versus a host permission for `tabs.update` and `tab.url`

**`tabs.update` needs no permission in either engine.**

Chromium: `TabsUpdateFunction::Run` looks up the tab and navigates; there is no host-permission or API-permission check in the path (`chrome/browser/extensions/api/tabs/tabs_api.cc:2622-2700`). The URL is vetted by `ExtensionTabUtil::PrepareURLForNavigation`, which rejects `javascript:`, kill URLs, `devtools:`, `chrome-untrusted:`, and `file:` without file access, and does nothing permission-related for `https:` (`chrome/browser/extensions/extension_tab_util.cc:1116-1175`).

Gecko: `tabs.update` resolves the URL against the extension's own URI and loads it with the extension's principal, checking only `context.checkLoadURL` (`browser/components/extensions/parent/ext-tabs.js:871-895`). MDN documents the scheme restrictions (no `chrome:`, `javascript:`, `data:`, `file:`, privileged `about:`).

**Navigating the tab to the Relay page needs no `web_accessible_resources` in Chromium**, because the navigation throttle short-circuits on same-origin initiators: "An extension can initiate navigations to any of its resources" when `initiator_origin == target_origin`, and browser-initiated navigations with no initiator origin proceed unconditionally (`extensions/browser/extension_navigation_throttle.cc:352-394`). I did not verify the equivalent Firefox rule in source; MDN's `tabs.update` page documents loading a packaged page by absolute extension-relative URL, which implies it is supported.

**Reading `tab.url` is where the permission matters.** Chromium scrubs `url`, `title`, and `favIconUrl` unless one of four conditions holds:

```cpp
if (extension->origin().IsSameOriginWith(url)) {
  has_permission = true;                       // own origin
} else if (permissions->HasAPIPermission(APIPermissionID::kTab)) {
  has_permission = true;                       // "tabs" permission
} else if (tab_id != api::tabs::TAB_ID_NONE &&
           permissions->HasAPIPermissionForTab(tab_id, APIPermissionID::kTab) &&
           permissions->HasTabPermissionsForSecurityOrigin(tab_id, url)) {
  has_permission = true;                       // activeTab, matching origin
} else if (permissions->active_permissions().HasExplicitAccessToOrigin(url)) {
  has_permission = true;                       // explicit host permission
}
if (!has_permission) {
  return ExtensionTabUtil::kScrubTabFully;
}
```

(`chrome/browser/extensions/extension_tab_util.cc:148-187`, applied by `ScrubTabForExtension` at `:508-534`)

So in the action click handler, either `activeTab` or the `https://login.microsoftonline.com/*` host permission we already hold is enough to read `tab.url` while the tab is on the identity provider. `activeTab` is the better choice because it also covers the case where the tab has navigated somewhere else we do not have a host permission for. Note the third branch requires the tab-specific grant to match the URL's origin, so `activeTab` alone does not let us read a URL the grant does not cover.

Gecko is the same in shape: MDN's `permissions` page lists `activeTab`'s extra privileges as "Access to the privileged parts of the tabs API for the current tab: `Tab.url`, `Tab.title`, and `Tab.faviconUrl`", and `tabs.update`'s return value "doesn't contain `url`, `title` and `favIconUrl` unless matching host permissions or the `"tabs"` permission has been requested". MDN also warns that the grant is scoped to the moment of interaction: "Your extension can only access the tab or data that existed when the user interaction occurred ... When the active tab navigates away ... the extension no longer has permission to access the tab." Read `tab.url` synchronously at the start of the click handler rather than after an await on the Bridge.

I did not verify Gecko's `activeTab` URL-scoping in source; the two claims above come from MDN.

## 6. Native messaging

**`nativeMessaging` is the only permission needed, in both engines.**

Chromium: the permission is declared in the manifest `permissions` array; the docs for native messaging state the extension must declare `"nativeMessaging"` and the host manifest must list the extension in `allowed_origins`. Gecko enforces it in the schema directly:

```json
{
  "name": "connectNative",
  "type": "function",
  "description": "Connects to a native application in the host machine.",
  "allowedContexts": ["content"],
  "permissions": ["nativeMessaging"],
```

(`toolkit/components/extensions/schemas/runtime.json:541-545`)

MDN lists `nativeMessaging` among the API permissions available in MV2 and above, so there is no MV3-specific change.

**The differences that matter for a per-Handoff host process are in the host manifest and in background lifetime, not in the API.**

- Host manifest shape and location differ: Firefox lists `allowed_extensions` as an array of add-on IDs, Chrome lists `allowed_origins` as `chrome-extension://` URLs, and the manifest files live in different directories (https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging). This is why the Gecko build needs `browser_specific_settings.gecko.id` pinned.
- Firefox spawns the host with `Subprocess.call` per `NativeApp` instance (`toolkit/components/extensions/NativeMessaging.sys.mjs:49`, `:130-138`), so one `connectNative` port equals one host process, which fits a per-Handoff Bridge invocation.
- Firefox exempts the event page from idle termination while a native port is open:

  ```js
  // Similar to what happens in recent Chrome version for MV3 extensions, extensions non-persistent
  // background scripts with a nativeMessaging port still open or a sendNativeMessage request still
  // pending an answer are exempt from being terminated when the idle timeout expires.
  if (
    !disableResetIdleForTest &&
    extension.backgroundContext?.hasActiveNativeAppPorts
  ) {
    extension.emit("background-script-reset-idle", { reason: "nativeapp" });
    return;
  }
  ```

  (`ext-backgroundPage.js:887-900`)

  That comment asserts Chrome does the same for MV3, which is consistent with the Chrome service-worker lifetime docs, but **I did not verify the Chromium-side keep-alive in Chromium source.** Treat "an open `connectNative` port keeps the Chromium service worker alive" as unverified; if the Handoff can exceed the service-worker idle timeout, keep the port open and re-read state from `storage.session` after any restart rather than assuming in-memory state survives.

## 7. Incognito and private browsing

**Chromium.** The `incognito` key parses to `spanning` by default for extensions (`extensions/common/manifest_handlers/incognito_info.cc:54-62`). The documented consequence is decisive for the Relay page:

> The default mode is "spanning", which means that the extension will run in a single shared process. ... Because incognito tabs cannot use this shared process, an extension using the "spanning" incognito mode will not be able to load pages from its extension package into the main frame of an incognito tab.

(https://developer.chrome.com/docs/extensions/reference/manifest/incognito)

So under `spanning`, `tabs.update(tabId, { url: relayPageUrl })` cannot work in an incognito tab. Under `split`, "all pages in an incognito window will run in their own incognito process", including the background page, with a separate memory-only cookie store and no communication between the two instances. The same doc's rule of thumb is explicit: "if your extension needs to load a tab in an incognito browser, use split incognito behavior."

`split` costs us a second background instance with its own `storage.session` (in-memory areas are per browser context, per `SessionStorageManager::GetForBrowserContext`, `session_storage_manager.cc:251-254`), so a Handoff started in incognito must complete entirely within the incognito instance. The webRequest permission layer also refuses to cross the boundary: `CanExtensionAccessURLInternal` returns `kDenied` when `crosses_incognito && !CanCrossIncognito(extension)` (`web_request_permissions.cc:102-105`). In all cases the user must enable the extension in incognito; that is user-controlled, not manifest-controlled.

**Gecko.** Firefox does not implement `split` and rejects it rather than approximating it. The schema postprocess explains the reasoning and, usefully, confirms the Relay page works under `spanning`:

```js
incognitoSplitUnsupportedAndFallback(value, context) {
  if (value === "split") {
    // incognito:split has not been implemented (bug 1380812). There are two
    // alternatives: "spanning" and "not_allowed".
    //
    // "incognito":"split" is required by Chrome when extensions want to load
    // any extension page in a tab in Chrome. In Firefox that is not required,
    // so extensions could replace "split" with "spanning".
    // Another (poorly documented) effect of "incognito":"split" is separation
    // of some state between some extension APIs. Because this can in theory
    // result in unwanted mixing of state between private and non-private
    // browsing, we fall back to "not_allowed", which prevents the user from
    // enabling the extension in private browsing windows.
    value = "not_allowed";
```

(`toolkit/components/extensions/Schemas.sys.mjs:354-373`; the schema default is `"spanning"`, `schemas/manifest.json:122-128`)

So an extension page can be the main frame of a private tab in Firefox under the default `spanning`, and shipping `"incognito": "split"` in the Gecko build would silently disable private-window support. Omit the key.

Private-window access is user-granted in Firefox ("By default, extensions do not run in private browsing windows. Whether an extension can access private browsing windows is under user control", https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/incognito). Until the user grants it, webRequest sees nothing from private windows: `ChannelWrapper::Matches` returns false when `isPrivate && !aExtension->PrivateBrowsingAllowed()` (`ChannelWrapper.cpp:654-657`). `extension.isAllowedIncognitoAccess` is the runtime check if the Extension wants to explain the failure to the user.

MDN's privacy note applies to us directly: under `spanning`, data captured in a private tab and sent onward from the background shares the main browsing session's context. The Sign-in request leaves the browser to the Bridge over native messaging rather than over the network, so the specific `fetch()` credential leak MDN describes does not apply, but the Bridge does authenticate natively using the machine's identity, which is a different trust statement than a private window implies. That is a product decision, not a permission question.

## Sources

Chromium source, `chromium/src` at `main`, fetched 2026-09-11 via chromium.googlesource.com:

- `extensions/browser/api/web_request/web_request_permissions.cc` (https://chromium.googlesource.com/chromium/src/+/main/extensions/browser/api/web_request/web_request_permissions.cc)
- `extensions/browser/api/web_request/web_request_permissions_unittest.cc` (https://chromium.googlesource.com/chromium/src/+/main/extensions/browser/api/web_request/web_request_permissions_unittest.cc)
- `extensions/browser/api/web_request/extension_web_request_event_router.cc` (https://chromium.googlesource.com/chromium/src/+/main/extensions/browser/api/web_request/extension_web_request_event_router.cc)
- `extensions/browser/api/web_request/web_request_info.cc` (https://chromium.googlesource.com/chromium/src/+/main/extensions/browser/api/web_request/web_request_info.cc)
- `extensions/browser/api/web_request/web_request_event_details.cc` (https://chromium.googlesource.com/chromium/src/+/main/extensions/browser/api/web_request/web_request_event_details.cc)
- `extensions/browser/api/web_request/form_data_parser.cc` (https://chromium.googlesource.com/chromium/src/+/main/extensions/browser/api/web_request/form_data_parser.cc)
- `extensions/browser/api/web_request/upload_data_presenter.cc` (https://chromium.googlesource.com/chromium/src/+/main/extensions/browser/api/web_request/upload_data_presenter.cc)
- `extensions/browser/api/storage/session_storage_manager.h` (https://chromium.googlesource.com/chromium/src/+/main/extensions/browser/api/storage/session_storage_manager.h)
- `extensions/browser/api/storage/storage_frontend.cc` (https://chromium.googlesource.com/chromium/src/+/main/extensions/browser/api/storage/storage_frontend.cc)
- `extensions/common/api/storage.json` (https://chromium.googlesource.com/chromium/src/+/main/extensions/common/api/storage.json)
- `extensions/common/manifest_handlers/incognito_info.cc` (https://chromium.googlesource.com/chromium/src/+/main/extensions/common/manifest_handlers/incognito_info.cc)
- `extensions/browser/extension_navigation_throttle.cc` (https://chromium.googlesource.com/chromium/src/+/main/extensions/browser/extension_navigation_throttle.cc)
- `chrome/browser/extensions/api/tabs/tabs_api.cc` (https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/extensions/api/tabs/tabs_api.cc)
- `chrome/browser/extensions/extension_tab_util.cc` (https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/extensions/extension_tab_util.cc)

Firefox source, `mozilla-firefox/firefox` at `main`, commit `b14ad10e3f7593276d59cede793ffbdd4b3a7a11` (2026-09-11):

- `toolkit/components/extensions/webrequest/ChannelWrapper.cpp` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/webrequest/ChannelWrapper.cpp)
- `toolkit/components/extensions/webrequest/WebRequest.sys.mjs` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/webrequest/WebRequest.sys.mjs)
- `toolkit/components/extensions/webrequest/WebRequestUpload.sys.mjs` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/webrequest/WebRequestUpload.sys.mjs)
- `toolkit/components/extensions/parent/ext-webRequest.js` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/parent/ext-webRequest.js)
- `toolkit/components/extensions/parent/ext-backgroundPage.js` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/parent/ext-backgroundPage.js)
- `toolkit/components/extensions/parent/ext-storage.js` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/parent/ext-storage.js)
- `toolkit/components/extensions/ExtensionCommon.sys.mjs` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/ExtensionCommon.sys.mjs)
- `toolkit/components/extensions/ExtensionStorage.sys.mjs` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/ExtensionStorage.sys.mjs)
- `toolkit/components/extensions/Extension.sys.mjs` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/Extension.sys.mjs)
- `toolkit/components/extensions/Schemas.sys.mjs` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/Schemas.sys.mjs)
- `toolkit/components/extensions/NativeMessaging.sys.mjs` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/NativeMessaging.sys.mjs)
- `toolkit/components/extensions/schemas/manifest.json` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/schemas/manifest.json)
- `toolkit/components/extensions/schemas/storage.json` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/schemas/storage.json)
- `toolkit/components/extensions/schemas/runtime.json` (https://github.com/mozilla-firefox/firefox/blob/main/toolkit/components/extensions/schemas/runtime.json)
- `browser/components/extensions/parent/ext-tabs.js` (https://github.com/mozilla-firefox/firefox/blob/main/browser/components/extensions/parent/ext-tabs.js)
- `netwerk/base/nsILoadInfo.idl` (https://github.com/mozilla-firefox/firefox/blob/main/netwerk/base/nsILoadInfo.idl)

Reference documentation:

- https://developer.chrome.com/docs/extensions/reference/api/webRequest
- https://developer.chrome.com/docs/extensions/reference/api/storage
- https://developer.chrome.com/docs/extensions/reference/manifest/incognito
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/webRequest
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/webRequest/onBeforeRequest
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/storage/session
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/background
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/permissions
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/incognito
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/tabs/update
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging

## What I could not verify

- Helium and Zen specifics. I inspected neither fork's patch set for changes to the extension APIs above. All Chromium findings are assumed to hold for Helium and all Gecko findings for Zen.
- Whether an open `runtime.connectNative` port keeps a Chromium MV3 service worker alive. Firefox's source asserts Chrome does this, but I did not confirm it in Chromium source.
- The default value of Firefox's `webextensions.webRequest.requestBodyMaxRawBytes` pref, which bounds `requestBody.raw`.
- Firefox's rule for loading an extension page as a tab's main frame at the source level. The `Schemas.sys.mjs` comment says `split` is not required for it and MDN documents the `tabs.update` usage, but I did not read the navigation-side check.
- Gecko's `activeTab` URL-scoping behavior in source; that claim rests on MDN.
- Live behavior. Nothing here was run against a real browser or a real Entra sign-in. The claim that an Entra SAML POST arrives as `requestBody.formData` with a `SAMLRequest` key follows from the content type and the parsers, not from an observed request.
