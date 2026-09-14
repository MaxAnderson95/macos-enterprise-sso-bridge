#!/bin/bash
# Build the unsigned installer package into dist/ from the app and the two
# native-messaging host manifests.
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
		echo "usage: build-pkg.sh [--version X.Y.Z]" >&2
		exit 2
		;;
	esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
staging="$repo_root/dist/pkgroot"
pkg="$repo_root/dist/EnterpriseSSOBridge-$version.pkg"

# One version input for the whole package: build-app.sh validates it and puts it in
# Info.plist, and pkgbuild carries the same string in the receipt.
"$repo_root/packaging/build-app.sh" --version "$version"

rm -rf "$staging"
mkdir -p "$staging/Applications"
cp -R "$repo_root/dist/Enterprise SSO Bridge.app" "$staging/Applications/"

node "$repo_root/tools/native-host-manifests.mjs" --root "$staging"

# Payload only: no --scripts, so nothing runs as root at install time. Both manifest
# directories under /Library are root-writable and system-wide, which is why no
# postinstall step is needed to place them per user.
rm -f "$pkg"
pkgbuild \
	--root "$staging" \
	--install-location / \
	--identifier tech.maxanderson.enterprise-sso-bridge \
	--version "$version" \
	--ownership recommended \
	"$pkg"

echo "built $pkg ($version)"
