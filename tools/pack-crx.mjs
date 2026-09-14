// Packs a built Chromium bundle's zip into a CRX3 archive signed with the project's
// private key. Usage: node tools/pack-crx.mjs --zip PATH --key PATH --output PATH
//
// CRX3 is [Cr24][version 3][header length][CrxFileHeader][zip], with every signature
// covering "CRX3 SignedData\0" + the little-endian length of signed_header_data +
// signed_header_data + the zip. The proto field numbers and the RSA PKCS#1 v1.5
// padding are Chromium's, from components/crx_file/crx3.proto and crx_verifier.cc.
import { createHash, createPrivateKey, createPublicKey, createSign } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { chromiumExtensionId, deriveChromiumExtensionId } from "./extension-ids.mjs";

const signatureContext = Buffer.from("CRX3 SignedData\0", "latin1");

function varint(value) {
  const bytes = [];
  while (value > 0x7f) {
    bytes.push((value & 0x7f) | 0x80);
    value >>>= 7;
  }
  bytes.push(value);
  return Buffer.from(bytes);
}

/** One length-delimited protobuf field, the only wire type CRX3's messages use. */
function field(number, value) {
  return Buffer.concat([varint((number << 3) | 2), varint(value.length), value]);
}

function uint32le(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeUInt32LE(value);
  return buffer;
}

export function packCrx(zip, privateKeyPem) {
  const privateKey = createPrivateKey(privateKeyPem);
  const publicKey = createPublicKey(privateKey).export({ type: "spki", format: "der" });

  // The same 16 bytes the extension ID is rendered from, which is why a CRX signed
  // with this key installs under the ID the committed manifest `key` pins.
  const crxId = createHash("sha256").update(publicKey).digest().subarray(0, 16);
  const signedHeaderData = field(1, crxId);

  const signature = createSign("sha256")
    .update(Buffer.concat([signatureContext, uint32le(signedHeaderData.length), signedHeaderData, zip]))
    .sign(privateKey);

  const header = Buffer.concat([
    field(2, Buffer.concat([field(1, publicKey), field(2, signature)])),
    field(10000, signedHeaderData),
  ]);

  return Buffer.concat([
    Buffer.from("Cr24", "latin1"),
    uint32le(3),
    uint32le(header.length),
    header,
    zip,
  ]);
}

const usage = "usage: pack-crx.mjs --zip PATH --key PATH --output PATH";

function parseArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    if (!["--zip", "--key", "--output"].includes(name) || argv[index + 1] === undefined) {
      throw new Error(usage);
    }
    options[name.slice(2)] = argv[index + 1];
  }
  if (!options.zip || !options.key || !options.output) {
    throw new Error(usage);
  }
  return options;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { zip, key, output } = parseArguments(process.argv.slice(2));
  const privateKeyPem = readFileSync(key, "utf8");
  const publicKey = createPublicKey(createPrivateKey(privateKeyPem)).export({
    type: "spki",
    format: "der",
  });

  // The wrong signing key produces a package that installs under the wrong ID, which
  // the native-messaging manifests would then refuse. Fail here instead.
  const signedAs = deriveChromiumExtensionId(publicKey.toString("base64"));
  if (signedAs !== chromiumExtensionId) {
    throw new Error(
      `${key} signs as ${signedAs}, but manifest.chromium.json pins ${chromiumExtensionId}`,
    );
  }

  const crx = packCrx(readFileSync(zip), privateKeyPem);
  writeFileSync(output, crx);
  console.log(`packed ${output} as ${signedAs} (${crx.length} bytes)`);
}
