// Registers a locally built Bridge with Helium and Zen for development.
// Usage: node tools/install-dev-native-host.mjs [--executable PATH] [--remove]
//
// These are the user-level manifests, which both engines read before the system-wide
// ones. The release .pkg installs the system-wide pair under /Library instead, so a
// developer's build shadows an installed one without fighting it, and removing these
// two files restores the installed Bridge.
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromiumExtensionId, geckoAddonId, nativeMessagingHostName } from "./extension-ids.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

const defaultExecutable = join(
  root,
  "dist",
  "Enterprise SSO Bridge.app",
  "Contents",
  "MacOS",
  "enterprise-sso-bridge",
);

// Paths confirmed in docs/research/extension-distribution.md: Helium's product
// directory is the literal net.imput.helium, and Gecko hardcodes Mozilla regardless
// of fork branding, so Zen has no path of its own.
const engines = {
  helium: {
    directory: join(homedir(), "Library", "Application Support", "net.imput.helium", "NativeMessagingHosts"),
    allowed: { allowed_origins: [`chrome-extension://${chromiumExtensionId}/`] },
  },
  zen: {
    directory: join(homedir(), "Library", "Application Support", "Mozilla", "NativeMessagingHosts"),
    allowed: { allowed_extensions: [geckoAddonId] },
  },
};

// An omitted value would otherwise resolve to the working directory, which exists and
// so passes the later check, leaving both manifests pointing at a directory.
function requirePath(value) {
  if (!value) {
    throw new Error("install-dev-native-host.mjs: --executable needs a path");
  }
  return value;
}

function parseArguments(argv) {
  let executable = defaultExecutable;
  let remove = false;
  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index];
    if (argument === "--executable") {
      executable = requirePath(argv[++index]);
    } else if (argument.startsWith("--executable=")) {
      executable = requirePath(argument.slice("--executable=".length));
    } else if (argument === "--remove") {
      remove = true;
    } else {
      throw new Error(`usage: install-dev-native-host.mjs [--executable PATH] [--remove]`);
    }
  }
  return { executable: resolve(executable), remove };
}

function manifestFor(engine, executable) {
  return {
    name: nativeMessagingHostName,
    description: "Enterprise SSO Bridge (development build)",
    path: executable,
    type: "stdio",
    ...engines[engine].allowed,
  };
}

const { executable, remove } = parseArguments(process.argv.slice(2));

for (const engine of Object.keys(engines)) {
  const file = join(engines[engine].directory, `${nativeMessagingHostName}.json`);
  if (remove) {
    rmSync(file, { force: true });
    console.log(`${engine}: removed ${file}`);
    continue;
  }
  if (!existsSync(executable)) {
    throw new Error(`no executable at ${executable}; run packaging/build-app.sh first`);
  }
  mkdirSync(engines[engine].directory, { recursive: true });
  writeFileSync(file, `${JSON.stringify(manifestFor(engine, executable), null, 2)}\n`);
  console.log(`${engine}: ${file} -> ${executable}`);
}
