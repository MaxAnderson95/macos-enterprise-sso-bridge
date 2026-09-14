import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { renderManifest } from "../build.mjs";

// Chromium derives the extension ID from the `key` field: the first 16 bytes of
// SHA-256 over the DER public key, hex-encoded, with 0-f remapped to a-p. Both
// native-messaging manifests name that ID, so a key change is a breaking change
// and this test is the tripwire for one.
const chromiumExtensionId = "ddalcfdgiklpbglknegedadiaclfkncc";

function deriveExtensionId(key: string) {
  const digest = createHash("sha256").update(Buffer.from(key, "base64")).digest();
  return [...digest.subarray(0, 16).toString("hex")]
    .map((c) => String.fromCharCode(c.charCodeAt(0) + (c >= "a" ? 10 : 49)))
    .join("");
}

describe.each(["chromium", "gecko"])("the %s manifest", (engine) => {
  const manifest = renderManifest(engine, "1.2.3");

  it("takes the version from the build argument", () => {
    expect(manifest.version).toBe("1.2.3");
  });

  it("asks for exactly the permissions the spec allows", () => {
    expect(manifest.permissions).toEqual(["webRequest", "storage", "nativeMessaging", "activeTab"]);
    expect(manifest.host_permissions).toEqual(["https://login.microsoftonline.com/*"]);
  });

  it("keeps form-action in the extension-pages CSP for the Relay page", () => {
    expect(manifest.content_security_policy.extension_pages).toContain("form-action https:");
  });

  it("gives the action an icon and no popup, so onClicked fires", () => {
    expect(manifest.action.default_icon["16"]).toBe("icons/icon-16.png");
    expect(manifest.action).not.toHaveProperty("default_popup");
  });

  it("rejects a version that is not dotted numeric", () => {
    expect(() => renderManifest(engine, "v1.2.3")).toThrow(/dotted numeric/);
  });
});

describe("the engine-specific keys", () => {
  const chromium = renderManifest("chromium", "0.0.0");
  const gecko = renderManifest("gecko", "0.0.0");

  it("pins the Chromium extension ID through the committed key", () => {
    expect(deriveExtensionId(chromium.key)).toBe(chromiumExtensionId);
  });

  it("splits incognito in Chromium and leaves Gecko on the default", () => {
    expect(chromium.incognito).toBe("split");
    expect(gecko).not.toHaveProperty("incognito");
  });

  it("pins the Gecko add-on ID, which the native manifest names", () => {
    expect(gecko.browser_specific_settings.gecko.id).toBe("enterprise-sso-bridge@maxanderson.tech");
    expect(gecko.browser_specific_settings.gecko.strict_min_version).toBe("115.0");
    expect(chromium).not.toHaveProperty("browser_specific_settings");
  });

  it("uses a service worker in Chromium and a background script in Gecko", () => {
    expect(chromium.background).toEqual({ service_worker: "background.js" });
    expect(gecko.background).toEqual({ scripts: ["background.js"] });
  });
});
