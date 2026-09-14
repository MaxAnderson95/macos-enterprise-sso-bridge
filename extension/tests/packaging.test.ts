import { createPublicKey, createVerify, generateKeyPairSync } from "node:crypto";
import { describe, expect, it } from "vitest";
import { deriveChromiumExtensionId } from "../../tools/extension-ids.mjs";
import { hostManifest, systemManifests } from "../../tools/native-host-manifests.mjs";
import { packCrx } from "../../tools/pack-crx.mjs";

// Release signing uses the committed key, which is not in the repository. The format
// is what these assert, so a throwaway key exercises the packer in CI.
const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const privateKeyPem = privateKey.export({ type: "pkcs8", format: "pem" }) as string;
const publicKeyDer = createPublicKey(privateKey).export({ type: "spki", format: "der" });

const archive = Buffer.from("PK\u0003\u0004 not really a zip, but the signature covers it");
const crx = packCrx(archive, privateKeyPem);
const headerLength = crx.readUInt32LE(8);
const header = crx.subarray(12, 12 + headerLength);

/** The length-delimited fields of one protobuf message, which is all CRX3 uses. */
function protobufFields(message: Buffer): Map<number, Buffer> {
  const fields = new Map<number, Buffer>();
  let offset = 0;
  const varint = () => {
    let value = 0;
    for (let shift = 0; ; shift += 7) {
      const byte = message[offset++]!;
      value |= (byte & 0x7f) << shift;
      if (!(byte & 0x80)) return value;
    }
  };
  while (offset < message.length) {
    const number = varint() >>> 3;
    const length = varint();
    fields.set(number, message.subarray(offset, offset + length));
    offset += length;
  }
  return fields;
}

const headerFields = protobufFields(header);
const proof = protobufFields(headerFields.get(2)!);
const signedHeaderData = headerFields.get(10000)!;

describe("the packed CRX", () => {
  it("starts with the CRX3 prologue and ends with the archive unchanged", () => {
    expect(crx.subarray(0, 4).toString("latin1")).toBe("Cr24");
    expect(crx.readUInt32LE(4)).toBe(3);
    expect(crx.subarray(12 + headerLength)).toEqual(archive);
  });

  // Chromium reads the ID out of the header's SignedData and refuses to install the
  // package under any other one, so this is the property that makes the committed
  // manifest `key` and the release signing key the same contract.
  it("declares the extension ID the signing key derives", () => {
    const crxId = protobufFields(signedHeaderData).get(1)!;
    expect(crxId).toHaveLength(16);
    const rendered = [...crxId.toString("hex")]
      .map((character) =>
        String.fromCharCode(character.charCodeAt(0) + (character >= "a" ? 10 : 49)),
      )
      .join("");
    expect(rendered).toBe(deriveChromiumExtensionId(publicKeyDer.toString("base64")));
  });

  // components/crx_file/crx_verifier.cc signs with RSA_PKCS1_SHA256 over
  // "CRX3 SignedData\0" + the signed header's length + the signed header + the archive.
  it("carries the public key the ID is derived from", () => {
    expect(proof.get(1)).toEqual(Buffer.from(publicKeyDer));
  });

  it("signs the prefix, the signed header, and the archive with RSA PKCS#1", () => {
    const size = Buffer.alloc(4);
    size.writeUInt32LE(signedHeaderData.length);
    const signed = Buffer.concat([
      Buffer.from("CRX3 SignedData\0", "latin1"),
      size,
      signedHeaderData,
      archive,
    ]);
    expect(
      createVerify("sha256").update(signed).verify(createPublicKey(privateKey), proof.get(2)!),
    ).toBe(true);
  });
});

describe("the system-wide native-messaging host manifests", () => {
  it("installs into the unbranded Chromium and Mozilla directories", () => {
    expect(systemManifests.chromium.directory).toBe(
      "Library/Application Support/Chromium/NativeMessagingHosts",
    );
    expect(systemManifests.mozilla.directory).toBe(
      "Library/Application Support/Mozilla/NativeMessagingHosts",
    );
  });

  it.each(["chromium", "mozilla"])("names the host and the installed executable (%s)", (engine) => {
    const manifest = hostManifest(engine);
    expect(manifest.name).toBe("tech.maxanderson.enterprise_sso_bridge");
    expect(manifest.type).toBe("stdio");
    expect(manifest.path).toBe(
      "/Applications/Enterprise SSO Bridge.app/Contents/MacOS/enterprise-sso-bridge",
    );
  });

  it("lets exactly the two Extensions through", () => {
    expect(hostManifest("chromium").allowed_origins).toEqual([
      "chrome-extension://ddalcfdgiklpbglknegedadiaclfkncc/",
    ]);
    expect(hostManifest("mozilla").allowed_extensions).toEqual([
      "enterprise-sso-bridge@maxanderson.tech",
    ]);
  });
});
