// Builds the Chromium and Gecko bundles of the Extension from one source tree.
// Usage: node build.mjs [--version X.Y.Z]
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync, copyFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as esbuild from "esbuild";
import { entryOriginMatchPatterns } from "../tools/generate.mjs";

const root = dirname(fileURLToPath(import.meta.url));
const distRoot = join(root, "dist");
const iconSource = join(root, "..", "assets", "extension");

export const engines = ["chromium", "gecko"];

const iconSizes = [16, 32, 48, 128];
const pages = ["popup.html", "relay.html"];

/**
 * The committed manifest for one engine with the release version and the entry
 * origins applied. This is the exact object written to dist, so asserting on it
 * asserts on what ships. The origins come from identity-providers/entra.json so
 * that host_permissions cannot drift from the Bridge's adapter and leave capture
 * failing silently.
 */
export function renderManifest(engine, version) {
  if (!/^\d+(\.\d+)*$/.test(version)) {
    throw new Error(`version must be dotted numeric, got '${version}'`);
  }
  const manifest = JSON.parse(readFileSync(join(root, `manifest.${engine}.json`), "utf8"));
  return { ...manifest, version, host_permissions: entryOriginMatchPatterns };
}

async function buildEngine(engine, version) {
  const out = join(distRoot, engine);
  rmSync(out, { recursive: true, force: true });
  mkdirSync(join(out, "icons"), { recursive: true });

  await esbuild.build({
    entryPoints: [join(root, "src", "background.ts")],
    outfile: join(out, "background.js"),
    bundle: true,
    format: "iife",
    // The Chromium service worker and the Gecko event page are both ES2022 hosts;
    // see manifest.gecko.json's strict_min_version for the Gecko floor.
    target: ["chrome109", "firefox115"],
    logLevel: "warning",
  });

  for (const page of pages) {
    copyFileSync(join(root, "pages", page), join(out, page));
  }
  for (const size of iconSizes) {
    copyFileSync(join(iconSource, `icon-${size}.png`), join(out, "icons", `icon-${size}.png`));
  }

  const manifest = renderManifest(engine, version);
  writeFileSync(join(out, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);

  const zip = join(distRoot, `${engine}.zip`);
  rmSync(zip, { force: true });
  execFileSync("zip", ["-q", "-r", "-X", zip, "."], { cwd: out });
  return zip;
}

function parseVersion(argv) {
  let version = "0.0.0";
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--version") {
      version = argv[++i] ?? "";
    } else if (arg.startsWith("--version=")) {
      version = arg.slice("--version=".length);
    } else {
      throw new Error(`usage: build.mjs [--version X.Y.Z], got '${arg}'`);
    }
  }
  return version;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const version = parseVersion(process.argv.slice(2));
  for (const engine of engines) {
    const zip = await buildEngine(engine, version);
    console.log(`${engine} ${version} -> ${zip}`);
  }
}
