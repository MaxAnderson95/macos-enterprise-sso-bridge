# Caller authentication by parent audit token

The Bridge is launched over native-messaging stdio, and its manifest names a world-readable absolute path, so any local process can run it. Before reading a single byte of stdin, the Bridge takes `getppid()`, obtains the parent's audit token via `task_name_for_pid` + `task_info(TASK_AUDIT_TOKEN)`, resolves it with `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)`, and checks it with `SecCodeCheckValidityWithErrors` against the verbatim designated requirement of each Allowed browser; a Caller that fails is logged and the process exits non-zero having written nothing. Both browsers `posix_spawn` the Bridge directly from their main process, so the parent is the browser, and the audit token's pidversion pins that one incarnation, which the bare PID cannot.

## Considered options

- `getsockopt(SOL_LOCAL, LOCAL_PEERTOKEN)` on stdin, the mechanism that would actually prove who holds the channel: fails with `ENOTSOCK`, because both engines hand the host anonymous `pipe(2)` pipes, not a socketpair.
- `xpc_connection_set_peer_code_signing_requirement` / `SecCodeCreateWithXPCMessage`, Apple's sound answer to peer identity: needs an XPC connection, which a native-messaging host does not have.
- `responsibility_get_pid_responsible_for_pid()`: both engines call `responsibility_spawnattrs_setdisclaim(attr, 1)`, so the Bridge is its own responsible process and the answer is its own PID. Private SPI besides.
- The extension ID or manifest path in argv: supplied by whoever spawned the process, so it is input, not identity. The Bridge does not read argv at all.
- `getppid()` + `kSecGuestAttributePid` without the audit token: same proof minus the incarnation pinning, leaving a PID-reuse window. Kept only as a documented fallback shape, not implemented; if `task_name_for_pid` fails, the Bridge rejects rather than silently downgrading.

Details and the live probes behind each row are in `docs/research/caller-identity.md`.

## Consequences

Two gaps remain open and are accepted for v1. A launcher can spawn the Bridge and then `exec` a browser binary in its own process before the Bridge samples the parent; the PID survives `exec`, so the check reads an identity the process did not have at spawn time. And code running inside a legitimately signed browser (a compromised extension, a debugger attach) genuinely is an Allowed browser. No parent-identity check can close either one, and a shared secret between Extension and Bridge would have nowhere secret to live, since anything that can inject into the browser can read extension storage.

The Allowed browsers table is a hardcoded Swift constant, so a browser that rotates its Team ID or renames its bundle requires a Bridge rebuild.

One carve-out, decided with the window prototype in issue #10: a parent that satisfies Apple's requirement for Finder, Dock, or launchd is recognized as a user launch, and the Bridge shows a window explaining that it runs when a browser needs it. It still cannot start a Handoff, because a user launch brings no Sign-in request and no pipe. Every other non-browser parent exits silently as above. The cost is one more entry in the requirement table; the alternative was a double-click that does nothing at all.
