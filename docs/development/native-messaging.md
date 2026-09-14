# Running the wire locally

How to get a locally built Bridge and a locally loaded Extension talking on this Mac. The release path is different and is described in [docs/spec/install.md](../spec/install.md).

## Register the Bridge with both browsers

```
packaging/build-app.sh --version 0.0.0
node tools/install-dev-native-host.mjs
```

The script writes one native-messaging host manifest per engine, each naming the absolute path of the executable inside `dist/Enterprise SSO Bridge.app` and the extension ID that engine will load:

- `~/Library/Application Support/net.imput.helium/NativeMessagingHosts/tech.maxanderson.enterprise_sso_bridge.json`, with `allowed_origins`
- `~/Library/Application Support/Mozilla/NativeMessagingHosts/tech.maxanderson.enterprise_sso_bridge.json`, with `allowed_extensions`

Both are user-level, and both engines read the user-level directory before the system-wide one. The release `.pkg` installs the system-wide pair under `/Library/Application Support/`, so a development manifest shadows an installed Bridge rather than colliding with it. `node tools/install-dev-native-host.mjs --remove` deletes both and hands control back to whatever the `.pkg` installed.

`--executable PATH` points the manifests somewhere else, such as `bridge/.build/debug/enterprise-sso-bridge`, which saves a release build on each iteration. The manifests carry an absolute path, so they need rewriting if the repository moves.

The Chromium extension ID in the Helium manifest is derived from the `key` committed in `extension/manifest.chromium.json`, not copied, so it cannot drift from what Helium computes.

## Load the Extension

```
cd extension && node build.mjs --version 0.0.0
```

In Helium, `chrome://extensions`, Developer mode, Load unpacked, and pick `extension/dist/chromium`. The ID shown must match the one in the Helium manifest; an unpacked load uses the committed `key`, so it will.

In Zen, `about:debugging#/runtime/this-firefox`, Load Temporary Add-on, and pick `extension/dist/gecko/manifest.json`. A temporary add-on keeps the ID from `browser_specific_settings`, which is the one the Zen manifest allows, and is gone at the next restart.

## Watch what happens

The Bridge's diagnostics are in the unified log, never on stdout:

```
command log stream --level info --predicate 'subsystem == "tech.maxanderson.enterprise-sso-bridge"'
```

`command` matters in zsh, which has a `log` builtin of its own. Lines carry methods, hosts, phases, and error codes; nothing carries a URL, a query string, a body, or a form field.

The Extension's side is in the background console: the three-dot inspect link on the extension card in Helium, or the Inspect button in Zen's debugging page.
