#!/bin/bash
# Build "Enterprise SSO Bridge.app" into dist/ from the Swift package.
set -euo pipefail

version="0.0.0"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--version)
		version="${2:-}"
		shift 2
		;;
	--version=*)
		version="${1#--version=}"
		shift
		;;
	*)
		echo "usage: build-app.sh [--version X.Y.Z]" >&2
		exit 2
		;;
	esac
done

# CFBundleShortVersionString and the extension manifests share this shape, so the
# same tag-derived string is valid in both.
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
	echo "build-app.sh: --version must be dotted numeric, got '$version'" >&2
	exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/dist/Enterprise SSO Bridge.app"

swift build --package-path "$repo_root/bridge" -c release

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$repo_root/bridge/.build/release/enterprise-sso-bridge" "$app/Contents/MacOS/enterprise-sso-bridge"
cp "$repo_root/assets/EnterpriseSSOBridge.icns" "$app/Contents/Resources/EnterpriseSSOBridge.icns"
cp "$repo_root/packaging/Info.plist" "$app/Contents/Info.plist"

plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$version" "$app/Contents/Info.plist"

codesign --force --sign - "$app"

echo "built $app ($version)"
