// The identifiers that tie the two halves together: both extension IDs and the
// native-messaging host name. Read from the committed manifests rather than repeated,
// because they are contracts with the native-messaging manifests that name them.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

function readManifest(engine) {
  return JSON.parse(readFileSync(join(root, "extension", `manifest.${engine}.json`), "utf8"));
}

/**
 * Chromium derives the extension ID from the `key` field: the first 16 bytes of
 * SHA-256 over the DER public key, hex-encoded, with 0-f remapped to a-p.
 */
export function deriveChromiumExtensionId(key) {
  const digest = createHash("sha256").update(Buffer.from(key, "base64")).digest();
  return [...digest.subarray(0, 16).toString("hex")]
    .map((character) =>
      String.fromCharCode(character.charCodeAt(0) + (character >= "a" ? 10 : 49)),
    )
    .join("");
}

export const chromiumExtensionId = deriveChromiumExtensionId(readManifest("chromium").key);

export const geckoAddonId = readManifest("gecko").browser_specific_settings.gecko.id;

/**
 * Deliberately not the bundle identifier: both engines reject a hyphen in a host
 * name. Chromium enforces [a-z0-9._] and Gecko enforces ^\w+(\.\w+)*$.
 */
export const nativeMessagingHostName = "tech.maxanderson.enterprise_sso_bridge";
