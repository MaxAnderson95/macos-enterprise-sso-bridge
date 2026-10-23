#!/bin/bash
# Register the Chromium extension with Helium and Ardia, without root. Run it again
# after downloading a newer .crx to update.
#
# Each browser reads external-extension preferences from its own user data directory
# and installs the .crx at next launch, where you accept it once. That JSON has to name
# an absolute path and JSON has no variable expansion, which is why this is a script and
# not a committed file.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
support="$HOME/Library/Application Support"
bridge_dir="$support/tech.maxanderson.enterprise-sso-bridge"

# Helium's is its literal product directory; Ardia passes --user-data-dir pointing at
# the Chromium folder inside its own. A browser that is not installed never reads its
# file, so both are written regardless.
user_data_dirs=(
	"$support/net.imput.helium"
	"$support/com.ardia.browser/Chromium"
)

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
# what keeps this file's name in step with what the browser will actually register.
extension_id="$(printf %s "$key" | base64 -d | shasum -a 256 | cut -c1-32 | tr '0-9a-f' 'a-p')"

mkdir -p "$bridge_dir"
installed_crx="$bridge_dir/$extension_id.crx"
cp "$crx" "$installed_crx"

echo "installed $extension_id $version"
echo "  package: $installed_crx"

host_name="tech.maxanderson.enterprise_sso_bridge"
for user_data_dir in "${user_data_dirs[@]}"; do
	external_prefs_dir="$user_data_dir/External Extensions"
	mkdir -p "$external_prefs_dir"
	cat >"$external_prefs_dir/$extension_id.json" <<JSON
{
  "external_crx": "$installed_crx",
  "external_version": "$version"
}
JSON
	echo "  external preferences: $external_prefs_dir/$extension_id.json"

	# A user-level development registration shadows the release's system manifest,
	# even when a moved checkout or migrated home directory left its target missing.
	development_manifest="$user_data_dir/NativeMessagingHosts/$host_name.json"
	if [[ -e "$development_manifest" || -L "$development_manifest" ]]; then
		name="$(plutil -extract name raw -o - -- "$development_manifest" 2>/dev/null || true)"
		description="$(plutil -extract description raw -o - -- "$development_manifest" 2>/dev/null || true)"
		target="$(plutil -extract path raw -o - -- "$development_manifest" 2>/dev/null || true)"
		if [[ ! -L "$development_manifest" && "$name" == "$host_name" &&
			"$description" == "Enterprise SSO Bridge (development build)" &&
			"$target" == /* && ! -e "$target" && ! -L "$target" ]]; then
			rm "$development_manifest"
			echo "Removed stale development registration: $development_manifest"
		else
			echo "Warning: user-level native-messaging registration may override the installed Bridge: $development_manifest" >&2
			echo "Left it unchanged; inspect it if the browser cannot reach the release Bridge." >&2
		fi
	fi
done

echo "Restart Helium and accept the extension when it offers it in the three-dot menu."
echo "Restart Ardia and turn the extension on in Settings, Extensions."
