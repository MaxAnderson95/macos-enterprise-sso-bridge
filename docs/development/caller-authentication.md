# Checking the caller gate locally

The Bridge refuses to serve anyone but an Allowed browser, and the check runs before a byte of stdin. What that means for testing is set out in [docs/spec/testing.md](../spec/testing.md): the rejection half can be proved from a shell, the acceptance half needs a real browser and cannot be.

## Rejection, from a shell

```
packaging/build-app.sh --version 0.0.0
packaging/caller-authentication-negative-test.sh
```

The script spawns the built executable, so the parent is the shell, and asserts a non-zero exit and an empty stdout. It is a local check and deliberately not a CI job: a runner proves nothing here that this Mac does not, and the half that matters cannot run there at all.

The reason for the refusal is in the unified log:

```
command log show --last 1m --predicate 'subsystem == "tech.maxanderson.enterprise-sso-bridge" and category == "caller"'
```

A rejection line carries the parent's PID, its signing identifier, its executable path, and the `OSStatus`. `-67050` (`errSecCSReqFailed`) is the ordinary "not a browser" answer. Anything else is worth reading: a browser updated on disk while it was running, for instance, no longer resolves to a code identity at all.

`command` matters in zsh, which has a `log` builtin of its own. Add `--info` to see the accepting lines, which are logged at info level and name only the matched browser.

## Acceptance, from a browser

Register the Bridge and load the Extension as [native-messaging.md](native-messaging.md) describes, then use the toolbar action. A Handoff that gets as far as a terminal response was authenticated first, and `log show --info` names the browser that was matched.

## The user-launch window

`open "dist/Enterprise SSO Bridge.app"`, or a double-click in Finder, shows the window explaining that the Bridge runs when a browser needs it. Both routes arrive with launchd as the parent, which is the case the carve-out is written for.
