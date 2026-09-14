#!/bin/bash
# Register the Chromium extension with Helium, without root. Run it again after
# downloading a newer .crx to update.
#
# Helium reads external-extension preferences from its own product directory and
# installs the .crx at next launch, where you accept it once. That JSON has to name an
# absolute path and JSON has no variable expansion, which is why this is a script and
# not a committed file.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
support="$HOME/Library/Application Support"
bridge_dir="$support/tech.maxanderson.enterprise-sso-bridge"
external_prefs_dir="$support/net.imput.helium/External Extensions"

if [[ $# -gt 1 ]]; then
	echo "usage: install-chromium-extension.sh [path/to/extension.crx]" >&2
	exit 2
fi

if [[ $# -eq 1 ]]; then
	crx="$1"
else
	shopt -s nullglob
	candidates=("$script_dir"/*.crx)
	shopt -u nullglob
	if [[ ${#candidates[@]} -ne 1 ]]; then
		echo "install-chromium-extension.sh: found ${#candidates[@]} .crx files next to the script; pass the one to install" >&2
		exit 2
	fi
	crx="${candidates[0]}"
fi

if [[ ! -f "$crx" ]]; then
	echo "install-chromium-extension.sh: no such file: $crx" >&2
	exit 2
fi

# A .crx is a header followed by the zip, so read the header length and cut the zip out
# rather than relying on unzip tolerating the prefix.
header_length="$(od -An -tu4 -j8 -N4 "$crx" | tr -d ' ')"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tail -c "+$((13 + header_length))" "$crx" >"$work/extension.zip"
unzip -p "$work/extension.zip" manifest.json >"$work/manifest.json"

version="$(plutil -extract version raw -o - -- "$work/manifest.json")"
key="$(plutil -extract key raw -o - -- "$work/manifest.json")"

# Chromium's extension ID is the first 16 bytes of the SHA-256 of the DER public key,
# hex-encoded with 0-f remapped to a-p. Deriving it from the package being installed is
# what keeps this file's name in step with what Helium will actually register.
extension_id="$(printf %s "$key" | base64 -d | shasum -a 256 | cut -c1-32 | tr '0-9a-f' 'a-p')"

mkdir -p "$bridge_dir" "$external_prefs_dir"

installed_crx="$bridge_dir/$extension_id.crx"
cp "$crx" "$installed_crx"

cat >"$external_prefs_dir/$extension_id.json" <<JSON
{
  "external_crx": "$installed_crx",
  "external_version": "$version"
}
JSON

echo "installed $extension_id $version"
echo "  package: $installed_crx"
echo "  external preferences: $external_prefs_dir/$extension_id.json"
echo "Restart Helium and accept the extension when it offers it in the three-dot menu."
