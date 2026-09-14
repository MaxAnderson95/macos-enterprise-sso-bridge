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

# The payload's modes come from whoever ran this, and --ownership recommended hands the
# result to root. Under a umask of 077 that installs a root-owned 0700 app and 0600
# manifests, which the browser running as the user cannot traverse or read, so the
# package builds fine and the Bridge never launches. Set them here instead of inheriting
# them.
find "$staging" -type d -exec chmod 0755 {} +
find "$staging" -type f -exec chmod 0644 {} +
chmod 0755 "$staging/Applications/Enterprise SSO Bridge.app/Contents/MacOS/enterprise-sso-bridge"

# pkgbuild marks a bundle relocatable by default, which means an install can follow a
# copy the user moved elsewhere. Both native-messaging manifests name the executable
# inside /Applications by absolute path, so an install that lands anywhere else leaves
# both browsers unable to spawn the Bridge.
component="$repo_root/dist/component.plist"
pkgbuild --analyze --root "$staging" "$component" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool false "$component"

# Payload only: no --scripts, so nothing runs as root at install time. Both manifest
# directories under /Library are root-writable and system-wide, which is why no
# postinstall step is needed to place them per user.
rm -f "$pkg"
pkgbuild \
	--root "$staging" \
	--component-plist "$component" \
	--install-location / \
	--identifier tech.maxanderson.enterprise-sso-bridge \
	--version "$version" \
	--ownership recommended \
	"$pkg"

echo "built $pkg ($version)"
