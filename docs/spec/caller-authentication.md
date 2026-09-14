# Caller authentication

Settled in [issue #3](https://github.com/MaxAnderson95/macos-enterprise-sso-bridge/issues/3) and recorded as [ADR 0001](../adr/0001-caller-authentication-by-parent-audit-token.md). The research behind it, including the live probes, is in `docs/research/caller-identity.md`.

The native-messaging manifest names a world-readable absolute path, so any local process can run the Bridge. This is the check that decides whether it keeps going.

## Identity source

`getppid()`, then `task_name_for_pid` and `task_info(TASK_AUDIT_TOKEN)`, then `SecCodeCopyGuestWithAttributes(NULL, {kSecGuestAttributeAudit: token}, ...)`.

Both engines `posix_spawn` the Bridge directly from the browser's main process, so the parent is the browser. The audit token's pidversion pins one incarnation of that PID, which closes the reuse window the bare-PID path leaves open. If `task_name_for_pid` fails for any reason, the Bridge rejects the Caller. There is no silent downgrade to `kSecGuestAttributePid`.

## The check

`SecCodeCheckValidityWithErrors` against the verbatim designated requirement of each Allowed browser, as `codesign -d -r-` reports it: identifier, `anchor apple generic`, the Developer ID intermediate marker, and the leaf Team OU.

The v1 set is Helium (`net.imput.helium`, Team S4Q33XPHB4) and Zen (`app.zen-browser.zen`, Team 9V5K9TP787). A match against any entry passes; no match, or no resolvable guest, rejects.

## Where it runs

At the top of `main`, before `NSApplication` setup and before the native-messaging read loop starts. A rejected Caller never reaches a message parser, and the exec-after-spawn sampling window is as narrow as the OS allows.

One gate only. There is no re-validation later in the Handoff: a browser that dies mid-Handoff already surfaces as EOF on stdin, which the Bridge handles regardless.

## The Allowed browsers table

A hardcoded Swift constant, one record per browser carrying display name, bundle identifier, team identifier, and requirement string. No data file and no `Info.plist` key: an ad-hoc-signed bundle's resources are writable by anyone who can reach the `.app`, and the list is fixed at build time anyway. A browser that rotates its Team ID or renames its bundle needs a Bridge rebuild.

## Module shape

One module, one call: `try CallerAuthentication.verify() -> AllowedBrowser`.

It owns `getppid()`, the Mach trap, the Security calls, and the table. Token capture and requirement matching stay private to it and are exercised through that seam. The matched `AllowedBrowser` flows downstream for `os_log` context and for naming the requesting browser in the Approval, so the Bridge never has to ask "which browser am I talking to" a second way.

## argv is not read

Chromium passes `chrome-extension://<id>/` and Gecko passes the manifest path plus the add-on ID, but both are supplied by whoever spawned the process. Ignoring argv entirely means there is no untrusted value to sanitize and no "never decide on this" rule for a future reader to remember.

## Rejection

`os_log` the `OSStatus` plus the parent's bundle identifier and executable path, then exit non-zero having written nothing to stdout.

The path and bundle ID of a local process are not Handoff data, so the logging invariant is untouched, and the log distinguishes a browser update that changed its signature from a hostile launcher. A successful check logs only the matched browser's name. The browser sees a native-host disconnect, which the Extension must handle anyway and surfaces as "Enterprise SSO Bridge did not respond".

## User-launch carve-out

A parent satisfying Apple's requirement for Finder or Dock is recognized as a user launch. The Bridge shows a window explaining that it runs when a browser needs it, and quits when dismissed. It cannot start a Handoff either way: a user launch brings no Sign-in request and no pipe.

launchd is recognized by being PID 1 rather than by a requirement, because it is the one process whose task port a normal user cannot get: `task_name_for_pid(1)` returns `KERN_FAILURE`, so there is no audit token to resolve, and the PID guest attribute is not a mechanism this design admits. In practice that is the case that matters, since Finder, the Dock, and `open` all hand the launch to launchd, which is the Bridge's parent. A process orphaned by a browser that died mid-spawn lands there too, and has just as little to do.

Every other non-browser parent exits silently. The cost is one more entry in the requirement table, against a double-click that otherwise does nothing at all.

## Residual risk

Two gaps stay open in v1, both accepted and recorded in ADR 0001.

A launcher can `exec` a browser binary in its own process after spawning the Bridge. The PID survives `exec`, so the check can read an identity the process did not have at spawn time. The attacker gains a real browser identity but no hold on the pipes, since `exec` replaces the address space.

Code injected into a legitimately signed browser genuinely is an Allowed browser. No parent-identity check closes that, and a shared secret between Extension and Bridge has nowhere to live: anything that can inject into the browser can also read extension storage. The Approval is the control that covers this case, not caller authentication.
