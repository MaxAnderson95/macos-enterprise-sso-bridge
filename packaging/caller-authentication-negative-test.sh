#!/bin/bash
# Spawn the built Bridge from this shell and assert it refuses to serve the Caller.
#
# A local check, not a CI job. The assertions stop at the exit code and stdout, because
# a shell script cannot observe what the process did with its window or its webview. The
# rejection line naming this shell is in the unified log:
#
#   command log show --last 1m --predicate 'subsystem == "tech.maxanderson.enterprise-sso-bridge"'
set -euo pipefail

executable="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/dist/Enterprise SSO Bridge.app/Contents/MacOS/enterprise-sso-bridge"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--executable)
		executable="${2:-}"
		shift 2
		;;
	--executable=*)
		executable="${1#--executable=}"
		shift
		;;
	*)
		echo "usage: caller-authentication-negative-test.sh [--executable PATH]" >&2
		exit 2
		;;
	esac
done

if [[ ! -x "$executable" ]]; then
	echo "no executable at '$executable'; run packaging/build-app.sh first" >&2
	exit 2
fi

stdout_file="$(mktemp -t caller-authentication-negative-test)"
trap 'rm -f "$stdout_file"' EXIT

# A native-messaging host is handed a request frame it never gets to read. Feeding one in
# means an accepted Caller would have had something to answer, so an empty stdout is the
# gate's doing and not an empty pipe's.
status=0
printf '\x16\x00\x00\x00{"version":1,"url":""}' |
	"$executable" >"$stdout_file" 2>/dev/null || status=$?

failures=0
if [[ "$status" -eq 0 ]]; then
	echo "FAIL: a shell-spawned Bridge exited 0" >&2
	failures=1
fi
if [[ -s "$stdout_file" ]]; then
	echo "FAIL: a shell-spawned Bridge wrote $(wc -c <"$stdout_file" | tr -d ' ') bytes to stdout" >&2
	failures=1
fi

if [[ "$failures" -ne 0 ]]; then
	exit 1
fi

echo "PASS: rejected a shell Caller, exit $status, stdout empty"
