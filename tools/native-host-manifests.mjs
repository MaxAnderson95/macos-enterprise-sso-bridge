// Writes the two system-wide native-messaging host manifests the .pkg installs.
// Usage: node tools/native-host-manifests.mjs --root DIR
//
// These are the /Library pair. tools/install-dev-native-host.mjs writes the ~/Library
// pair, which both engines read first, so a development build shadows an installed one.
//
// Helium's Chromium directory is the unbranded literal rather than anything derived
// from a product name, and Gecko hardcodes Mozilla regardless of fork branding; both
// are established in docs/research/extension-distribution.md.
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromiumExtensionId, geckoAddonId, nativeMessagingHostName } from "./extension-ids.mjs";

export const installedExecutable =
  "/Applications/Enterprise SSO Bridge.app/Contents/MacOS/enterprise-sso-bridge";

export const systemManifests = {
  chromium: {
    directory: "Library/Application Support/Chromium/NativeMessagingHosts",
    callers: { allowed_origins: [`chrome-extension://${chromiumExtensionId}/`] },
  },
  mozilla: {
    directory: "Library/Application Support/Mozilla/NativeMessagingHosts",
    callers: { allowed_extensions: [geckoAddonId] },
  },
};

export function hostManifest(engine) {
  return {
    name: nativeMessagingHostName,
    description: "Enterprise SSO Bridge",
    path: installedExecutable,
    type: "stdio",
    ...systemManifests[engine].callers,
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [flag, root] = process.argv.slice(2);
  if (flag !== "--root" || !root) {
    throw new Error("usage: native-host-manifests.mjs --root DIR");
  }
  for (const [engine, { directory }] of Object.entries(systemManifests)) {
    const file = join(root, directory, `${nativeMessagingHostName}.json`);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, `${JSON.stringify(hostManifest(engine), null, 2)}\n`);
    console.log(`${engine}: ${file}`);
  }
}
