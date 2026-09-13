# Caller identity for the Bridge on macOS

Research for issue #2. Question: can the Bridge verify, through an OS-backed mechanism, that the process which launched its native-messaging endpoint is an Allowed browser?

Versions read: Chromium `153.0.8010.36` (the version `helium` main pins in `chromium_version.txt`) and `152.0.7977.82` (the framework version the installed Helium 0.16.6.1 ships); the two launch files examined are byte-identical between those tags. Firefox `155.0.1` (the version Zen 1.22.1b pins in `surfer.json`). macOS SDK 26.5 headers, and live probes against the running Helium and Zen on this machine.

## Summary

- Both browsers spawn the Bridge with `posix_spawnp` directly from the **browser's main (parent) process**. No shell, no helper, no launcher binary sits between them. `getppid()` in the Bridge is the PID of `/Applications/Helium.app/Contents/MacOS/Helium` or `/Applications/Zen Browser.app/Contents/MacOS/zen`.
- stdin/stdout are **anonymous `pipe(2)` pipes**, not sockets. `getsockopt(SOL_LOCAL, LOCAL_PEERTOKEN)` and `LOCAL_PEERPID` on them fail with `ENOTSOCK` (verified). There is no way to get the peer identity of a pipe. **Pipe-peer identity is impossible.**
- Both browsers set `responsibility_spawnattrs_setdisclaim(attr, 1)` when spawning the host. A disclaimed child becomes its own responsible process (verified), so `responsibility_get_pid_responsible_for_pid()` returns the Bridge's own PID and proves nothing. It is also declared in no public SDK header.
- The workable mechanism is PID-based: take `getppid()`, get a `SecCodeRef` for it, and check it against a designated requirement. Two ways to get that code ref, both verified working from an **ad-hoc-signed, non-sandboxed** binary as a normal user:
  - `SecCodeCopyGuestWithAttributes(NULL, {kSecGuestAttributePid: pid}, ...)` then `SecCodeCheckValidity` with the browser's DR: returned `/Applications/Helium.app` and `errSecSuccess`.
  - `task_name_for_pid` + `task_info(TASK_AUDIT_TOKEN)` + `SecCodeCopyGuestWithAttributes(NULL, {kSecGuestAttributeAudit: <audit_token_t>}, ...)`: returned `/Applications/Zen Browser.app` and `errSecSuccess`. `task_for_pid` is not needed; the *name* port is enough and is available for same-uid processes.
- The audit-token path is strictly better: the token carries a **pidversion** (`val[7]`), which pins the identity to one specific incarnation of that PID and closes the PID-reuse race that the bare-PID path leaves open.
- Neither path proves the *pipe* came from that process, and neither survives code injected into a legitimately signed browser. Apple's only sound answer to "who is on the other end of this channel" is the XPC one (`xpc_connection_set_peer_code_signing_requirement`, `SecCodeCreateWithXPCMessage`), which is unavailable to a stdio child.
- Argv is attacker-controlled input in both engines and must not be treated as identity: Chromium passes `chrome-extension://<id>`, Gecko passes the manifest path and the add-on ID. Any local process can spawn the Bridge with the same argv.

## Chromium launch chain

Call order, all inside the browser process:

1. `NativeMessageProcessHost` gets its task runner from `content::GetIOThreadTaskRunner({})` (`native_message_process_host.cc:83`), and `LaunchHostProcess()` asserts it runs on that IO thread (`:136`). It builds the origin as `chrome-extension://` + extension ID (`:138`) and calls `launcher_->Launch(origin, native_host_name, ...)` (`:139`).
2. `NativeProcessLauncherImpl::Launch` calls `LaunchContext::Start(...)` with a `base::ThreadPool` task runner (`native_process_launcher.cc:93-103`).
3. `LaunchContext::Start` re-asserts the IO thread (`CHECK(base::CurrentIOThread::IsSet())`, `launch_context.cc:75`) and posts `LaunchInBackground` onto the thread-pool runner (`:79-87`). That is a worker **thread**, still in the browser process.
4. `LaunchInBackground` finds and parses the host manifest, rejects the launch unless `manifest->allowed_origins().MatchesSecurityOrigin(origin)` (`launch_context.cc:169-172`), requires an absolute host path on non-Windows (`:180-190`), then builds the command line.

Argv (`launch_context.cc:202-261`), macOS:

```
argv[0] = <path from the manifest>
argv[1] = "chrome-extension://<extension id>/"     // must be first arg, :203-206
argv[2..] = optional: an error arg, "--reconnect-command=<base64 json>"
            (only if the manifest sets supports_native_initiated_connections),
            "--native-messaging-connect-id=<id>"
```

`--parent-window=` is Windows-only (`:210-213`, guarded by `BUILDFLAG(IS_WIN)`), which matches Chrome's own documentation of the calling convention.

Stdio and spawn (`launch_context_posix.cc:59-110`):

- Two `pipe()` pairs. The write end of the first is remapped to the child's `STDOUT_FILENO`, the read end of the second to `STDIN_FILENO`, via `options.fds_to_remap` (`:65-83`).
- `options.current_directory = command_line.GetProgram().DirName()` (`:85`).
- `options.disclaim_responsibility = true` on macOS, with the comment "This is executing a third-party binary, so do not associate any system private data requests with Chrome" (`:92-96`).
- `base::LaunchProcess(command_line, options)` (`:98`).

`base::LaunchProcess` on macOS (`base/process/launch_mac.cc:264-408`):

- `posix_spawnattr_setflags(attr, POSIX_SPAWN_CLOEXEC_DEFAULT)` (`:270-275`). Only the fds named in file actions survive.
- dup2 file actions from `fds_to_remap` for fd 0 and 1; stderr is not remapped, so `posix_spawn_file_actions_addinherit_np(STDERR_FILENO)` keeps the browser's stderr (`:283-307`).
- `responsibility_spawnattrs_setdisclaim(attr.get(), 1)` (`:309-312`).
- Environment: the browser's full `environ` (`:329-332`) plus one added variable, `MACH_PORT_RENDEZVOUS_PEER_VALDATION=<int>` (`:314-316`, constant at `base/apple/mach_port_rendezvous_mac.cc:58-59`, inserted at `:95-100`). Note the typo in the name is upstream's.
- `posix_spawn_file_actions_addchdir` for the working directory (`:353-356`).
- `posix_spawnp(&pid, executable_path, file_actions, attr, argv, environ)` (`:405-408`).

No shell, no intermediate process, no Mach port rendezvous for a native host (`mach_ports_for_rendezvous` is empty and `process_requirement` unset for this call path). The Bridge's parent is the browser's main executable.

### Helium's delta

Helium carries exactly one patch touching native messaging: `patches/helium/core/scan-chrome-native-messaging-hosts.patch` (listed at `patches/series:111`). It adds two manifest search directories so Helium also finds manifests installed for Google Chrome:

- `/Library/Google/Chrome/NativeMessagingHosts` as `DIR_CHROME_NATIVE_MESSAGING` (patch lines 44-52)
- `~/Library/Application Support/Google/Chrome/NativeMessagingHosts` as `DIR_CHROME_USER_NATIVE_MESSAGING` (patch lines 61-66, plus `GetChromeUserDataDirectory` for macOS at lines 165-167)

Search order becomes: user Helium dir, user Chrome dir, system Helium dir, system Chrome dir (patch lines 3-24). Nothing in the patch touches argv, pipes, `disclaim_responsibility`, or the spawn itself. No Helium patch references `launch_mac.cc`, `native_message_process_host`, or `disclaim`.

The installed Helium is Developer ID signed, `identifier net.imput.helium`, Team `S4Q33XPHB4`, with flags `kill,restrict,library-validation,runtime`. Its designated requirement is:

```
identifier "net.imput.helium" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = S4Q33XPHB4
```

Helper processes carry different identifiers. A live probe against a Helium renderer helper resolved to `Helium Framework.framework/.../Helium Helper (Renderer).app` and failed the main bundle's requirement with `errSecCSReqFailed` (-67050), which is the correct outcome: only the browser process launches native hosts.

## Gecko launch chain

1. `runtime.connectNative` is serviced in the **parent process**. The chain ends at `IOUtils::LaunchProcess`, which calls `AssertParentProcessWithCallerLocation` (`xpcom/ioutils/IOUtils.cpp:3113`); that helper `MOZ_CRASH`es if `XRE_IsParentProcess()` is false (`:293-298`). A content process cannot spawn the host.
2. `NativeApp`'s constructor looks up the manifest and calls `Subprocess.call` (`toolkit/components/extensions/NativeMessaging.sys.mjs:112-120`):

```js
let subprocessOpts = {
  command: command,
  arguments: [hostInfo.path, context.extension.id],
  workdir: PathUtils.parent(command),
  stderr: "pipe",
  disclaim: true,
};
```

3. `Subprocess.call` fills in defaults and prepends the command as argv[0] (`toolkit/modules/subprocess/Subprocess.sys.mjs:146`), so the final argv is:

```
argv[0] = <path from the manifest>
argv[1] = <absolute path to the manifest .json>
argv[2] = <extension id, e.g. sso-bridge@example.com>
```

   Environment: no `environment` option is passed, so `getEnvironment()` returns the parent's full environment and it is passed verbatim (`Subprocess.sys.mjs:116-127`). `disclaim` is honored only on macOS (`:39-41`, `:131-133`).

4. The work happens in a `ChromeWorker` (`subprocess_unix.worker.js`), which is a thread of the parent process. `initPipes` creates the pipes with `libc.pipe`, sets `FD_CLOEXEC` and `O_NONBLOCK` on the parent ends, and hands the child fds 0, 1, 2 (because `stderr: "pipe"`) **and fd 3**, an extra sentinel pipe the parent polls to detect process exit (`:328-377`).
5. `this.pid = IOUtils.launchProcess(options.arguments, launchOptions)` (`:398`), with `fdMap`, `workdir`, `environment`, and `disclaim`.
6. `IOUtils::LaunchProcess` converts that to `base::LaunchOptions`, sets `options.disclaim` under `XP_MACOSX` (`IOUtils.cpp:3142-3144`), and calls `base::LaunchApp(argv, std::move(options), &pid)` (`:3150`).
7. `base::LaunchApp` on macOS (`ipc/chromium/src/base/process_util_mac.mm:41-160`): `posix_spawn_file_actions_adddup2` per fdMap entry (`:76-85`), `posix_spawn_file_actions_addchdir_np` for the workdir (`:87-94`), `responsibility_spawnattrs_setdisclaim(&spawnattr, 1)` when `options.disclaim` (`:120-126`), `POSIX_SPAWN_CLOEXEC_DEFAULT` with `addinherit_np` for the std fds (`:131-142`), then `posix_spawnp` (`:147`).

Again: no shell, no intermediate process. The Bridge's parent is the main browser process.

Manifest locations (`NativeManifests.sys.mjs:16-20`, `:37-42`): `XREUserNativeManifests` and `XRESysNativeManifests` plus the `NativeMessagingHosts` slug. Those directory keys hardcode the literal `Mozilla` regardless of fork branding (`toolkit/xre/nsXREDirProvider.cpp:417-428` for the user path, `:335-343` for the system path), so Zen reads:

- `~/Library/Application Support/Mozilla/NativeMessagingHosts/`
- `/Library/Application Support/Mozilla/NativeMessagingHosts/`

### Zen's delta

Zen ships `src/external-patches/firefox/issue_15123.patch`, which fixes the `fcntl` ctypes declaration to be genuinely variadic (`"..."` instead of a fixed `ctypes.int`) because variadic arguments use a different calling convention on Apple silicon, and wraps the flag arguments in `ctypes.int(...)` in `subprocess_unix.sys.mjs` and `subprocess_unix.worker.js`. It also adds an xpcshell test asserting the worker pipes carry exactly `FD_CLOEXEC` and are non-blocking. This is a correctness fix in the pipe setup; it does not change argv, the spawn API, the process topology, or `disclaim`. A grep of the Zen tree found no other change to native messaging (remaining hits are generated `.d.ts` type stubs and unrelated shell tests).

Installed Zen is Developer ID signed, `identifier app.zen-browser.zen`, Team `9V5K9TP787`, flags `runtime`. Its designated requirement is:

```
identifier "app.zen-browser.zen" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "9V5K9TP787"
```

## macOS identity APIs

Everything in the "Verified here" column was run on this machine (macOS 26, SDK 26.5) from an **ad-hoc-signed, non-sandboxed, non-root** binary, against the running Helium and Zen.

| Mechanism | Public? | Works for a stdio child? | Verified here | Weaknesses |
|---|---|---|---|---|
| `getsockopt(SOL_LOCAL, LOCAL_PEERTOKEN)` on stdin | Declared in `sys/un.h:93` but not on developer.apple.com | **No** | `-1`, `errno 38` (`ENOTSOCK`) on a `pipe()` fd; succeeds and returns the peer's audit token on a `socketpair()` | Only works for unix-domain sockets. Both browsers use pipes. |
| `getsockopt(..., LOCAL_PEERPID)` on stdin | `sys/un.h:89` | **No** | same `ENOTSOCK` | as above |
| `getppid()` + `SecCodeCopyGuestWithAttributes(NULL, {kSecGuestAttributePid}, ...)` + `SecCodeCheckValidity(code, flags, DR)` | Yes. `SecCode.h:126`, `:189-190`, `:237-238` | Yes | `errSecSuccess`, path `/Applications/Helium.app`, DR satisfied | PID reuse if the parent exits between spawn and check; `exec()` after spawn; injection into a valid browser |
| `task_name_for_pid` + `task_info(TASK_AUDIT_TOKEN)` + `SecCodeCopyGuestWithAttributes(NULL, {kSecGuestAttributeAudit}, ...)` + `SecCodeCheckValidity` | `mach/mach_traps.h:286`, `mach/task_info.h:242`, `SecCode.h:127`. In the public SDK; `task_name_for_pid` has no developer.apple.com page | Yes | `KERN_SUCCESS` for both browsers (including Helium with `library-validation`+`restrict`); audit token carried a pidversion; Zen resolved to `/Applications/Zen Browser.app` with DR satisfied; a Helium *helper* correctly failed with `errSecCSReqFailed` | Same `exec()` and injection weaknesses. Closes PID reuse via pidversion. Needs same-uid (or root); the *name* port suffices, `task_for_pid` is not required. |
| `responsibility_get_pid_responsible_for_pid()` | **No.** Not declared in any SDK header (grep over `usr/include` and `Security.framework/Headers` found nothing); resolves via `dlsym(RTLD_DEFAULT, ...)` | Useless here | With `disclaim=0` the child inherited the launcher's responsible PID; with `responsibility_spawnattrs_setdisclaim(attr,1)` the child's responsible PID **was its own PID** | Both browsers disclaim, so this returns the Bridge itself. Private SPI besides. |
| `proc_pidinfo(pid, PROC_PIDTBSDINFO)` / `proc_pidpath` | Yes, `libproc.h:96`, `:102` | Yes (works on non-children too) | Returned ppid, `pbi_start_tvsec/tvusec`, comm, and the executable path for an unrelated process | A path is not an identity: it proves nothing about signing. Useful only as a PID-reuse guard (start time) or for diagnostics. |
| `PROC_PIDUNIQIDENTIFIERINFO` (`p_uniqueid`) | **No.** Not in the public SDK's `sys/proc_info.h` | - | Absent from the header | Would be the clean PID-reuse guard; use the audit token's pidversion instead. |
| `SecCodeCreateWithXPCMessage` | Yes, `SecCode.h:194-203` | **No** | not applicable | Requires an XPC message with an associated connection. |
| `xpc_connection_set_peer_code_signing_requirement` | Yes, `xpc/connection.h:772-803`, macOS 12.0+ | **No** | not applicable | The sound mechanism, and the one Apple points at (its doc comment links TN3127). Needs an XPC connection, which a native-messaging host does not have. |
| `SecTaskCreateWithAuditToken` | Yes, `SecTask.h:57-65` | Yes, given a token | not exercised | Reads entitlements; it does not validate a code signature against a requirement. |

Notes on what the checks mean:

- `SecCodeCheckValidity` with a requirement is the operation that binds "this running process" to "this code-signing identity". Failure code for a mismatch is `errSecCSReqFailed` = -67050 (`CSCommon.h:86`); a missing guest is `errSecCSNoSuchCode` = -67065 (`:71`).
- Hardened runtime and library validation on the target do not block either lookup; both were verified against Helium, which sets `kill,restrict,library-validation,runtime`.
- Nothing here needed an entitlement, root, or a non-sandboxed exception beyond not being sandboxed.

## Threats and gaps

- **No pipe-peer identity.** This is the load-bearing negative result. The Bridge cannot ask the kernel who is on the other end of fd 0 or fd 1, because they are pipes. Everything below is an inference about a *process*, tied to the channel only by the assumption that the parent is the one holding the pipe.
- **PID reuse.** `getppid()` is a snapshot. If the browser exits right after spawning, the Bridge is reparented to `launchd` (PID 1) and `getppid()` no longer names the browser; worse, a naive design that stashes the PID and checks later can check a recycled PID. Capturing the parent's **audit token** immediately at startup and validating that token (not the bare PID) removes the window, because the token's pidversion does not repeat.
- **`exec()` after spawn.** A malicious launcher spawns the Bridge, then `exec`s the browser binary in its own process before the Bridge samples its parent. The PID does not change across `exec`, so the Bridge reads the browser's code identity from a process that was not the browser when it did the spawning. Sampling at the earliest possible moment narrows the window; it does not close it. The OS offers no "identity of the process as it was at the instant it spawned me". Note the attacker gains little from this: they end up with a real browser as the Caller and no hold on the pipes, since `exec` replaces the address space. It is a real gap in what the check *proves*, not obviously an exploitable path.
- **Injection into a legitimately signed browser.** If an attacker gets code execution inside Helium or Zen (a compromised extension calling `connectNative`, a debugger attach, a dylib in a browser that permits it), the parent genuinely *is* the Allowed browser. No parent-identity check can distinguish that. The Extension origin/ID in argv is not a defense: argv is supplied by the launcher.
- **Argv is not evidence.** Any local process can run the Bridge with `chrome-extension://<id>/` or a manifest path plus add-on ID as argv. The spike's origin check establishes only which Extension the browser *claims* is on the other end, and only if the browser is trusted first.
- **Responsibility is deliberately severed.** Both engines disclaim responsibility precisely so the child's TCC prompts are not attributed to the browser. A side effect is that the responsibility chain carries no evidence of the launcher.
- **The Bridge's own distribution matters.** Because the manifest lives in a world-readable directory and names an absolute path, a non-browser process can invoke the Bridge at will. Caller authentication limits what such an invocation achieves, but the Bridge should assume it will be run by hostile callers and keep anything sensitive behind the check.

## Recommendation candidates

### 1. Audit token captured at startup, validated against a per-browser designated requirement (recommended)

At the very top of `main`, before reading stdin: `pid = getppid()`, `task_name_for_pid(mach_task_self(), pid, &port)`, `task_info(port, TASK_AUDIT_TOKEN, ...)`, wrap the token in a `CFData`, `SecCodeCopyGuestWithAttributes(NULL, {kSecGuestAttributeAudit: data}, kSecCSDefaultFlags, &code)`, then `SecCodeCheckValidityWithErrors(code, kSecCSDefaultFlags, req, &err)` against the requirement for each Allowed browser. Keep the token for the process lifetime and re-validate before each sensitive operation.

- Proves: the process that holds the other end of the pipes, at the moment of capture, is a specific incarnation (PID + pidversion) of a binary whose code signature satisfies the requirement, including Team ID, bundle identifier, and Apple anchor.
- Does not prove: that the pipes came from that process; that the parent did not `exec` into the browser after spawning; that no attacker code is running inside the browser; that the Extension named in argv is the one talking.
- Cost: one Mach trap plus two Security calls. Verified working, unsandboxed, non-root, against both target browsers.

### 2. PID-only variant: `getppid()` + `kSecGuestAttributePid` + `SecCodeCheckValidity`

Same shape, one fewer moving part, no Mach API.

- Proves: the same thing as option 1, minus the incarnation pinning.
- Does not prove: additionally, it cannot tell a recycled PID from the original. Re-validating later re-resolves the PID and may resolve a different process.
- Use if `task_name_for_pid` turns out to be blocked in some deployment configuration. Otherwise option 1 dominates at negligible extra cost.

### 3. Defense in depth on top of 1: bind the Handoff to a browser-supplied secret

The parent check answers "is my Caller a browser". It cannot answer "is my Caller the browser instance that this Handoff belongs to", nor detect injected code. If that matters, add a second factor at the protocol level (for example, the Bridge refuses to act until the Extension proves knowledge of something only the Bridge and a live Extension instance share) and keep option 1 as the outer gate.

Not viable, for the record: `LOCAL_PEERTOKEN` on stdio (pipes are not sockets), `responsibility_get_pid_responsible_for_pid` (disclaimed, and private), XPC peer requirements (no XPC connection), and trusting argv.

## Sources

Chromium, read at tag `153.0.8010.36` (identical at `152.0.7977.82` for the two launch files):

- https://chromium.googlesource.com/chromium/src/+/refs/tags/153.0.8010.36/chrome/browser/extensions/api/messaging/native_message_process_host.cc
- https://chromium.googlesource.com/chromium/src/+/refs/tags/153.0.8010.36/chrome/browser/extensions/api/messaging/native_process_launcher.cc
- https://chromium.googlesource.com/chromium/src/+/refs/tags/153.0.8010.36/chrome/browser/extensions/api/messaging/launch_context.cc
- https://chromium.googlesource.com/chromium/src/+/refs/tags/153.0.8010.36/chrome/browser/extensions/api/messaging/launch_context_posix.cc
- https://chromium.googlesource.com/chromium/src/+/refs/tags/153.0.8010.36/base/process/launch_mac.cc
- https://chromium.googlesource.com/chromium/src/+/refs/tags/153.0.8010.36/base/process/launch.h
- https://chromium.googlesource.com/chromium/src/+/refs/tags/153.0.8010.36/base/apple/mach_port_rendezvous_mac.cc

Helium (`imputnet/helium`, main at `0ae15ad`, `chromium_version.txt` = 153.0.8010.36):

- https://github.com/imputnet/helium/blob/main/patches/helium/core/scan-chrome-native-messaging-hosts.patch
- https://github.com/imputnet/helium/blob/main/patches/series

Firefox, read at tag `FIREFOX_155_0_1_RELEASE` (`mozilla-firefox/firefox`):

- https://github.com/mozilla-firefox/firefox/blob/FIREFOX_155_0_1_RELEASE/toolkit/components/extensions/NativeMessaging.sys.mjs
- https://github.com/mozilla-firefox/firefox/blob/FIREFOX_155_0_1_RELEASE/toolkit/components/extensions/NativeManifests.sys.mjs
- https://github.com/mozilla-firefox/firefox/blob/FIREFOX_155_0_1_RELEASE/toolkit/modules/subprocess/Subprocess.sys.mjs
- https://github.com/mozilla-firefox/firefox/blob/FIREFOX_155_0_1_RELEASE/toolkit/modules/subprocess/subprocess_unix.worker.js
- https://github.com/mozilla-firefox/firefox/blob/FIREFOX_155_0_1_RELEASE/xpcom/ioutils/IOUtils.cpp
- https://github.com/mozilla-firefox/firefox/blob/FIREFOX_155_0_1_RELEASE/ipc/chromium/src/base/process_util_mac.mm
- https://github.com/mozilla-firefox/firefox/blob/FIREFOX_155_0_1_RELEASE/toolkit/xre/nsXREDirProvider.cpp

Zen (`zen-browser/desktop`, main at `22961e9`, `surfer.json` pins firefox 155.0.1):

- https://github.com/zen-browser/desktop/blob/main/src/external-patches/firefox/issue_15123.patch
- https://github.com/zen-browser/desktop/blob/main/surfer.json

Apple, macOS SDK 26.5 headers (`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`):

- `System/Library/Frameworks/Security.framework/Headers/SecCode.h` (guest attributes at 123-131; `SecCodeCopyGuestWithAttributes` at 134-190; `SecCodeCreateWithXPCMessage` at 192-203; `SecCodeCheckValidity` at 216-238)
- `System/Library/Frameworks/Security.framework/Headers/CSCommon.h` (error codes at 71, 86)
- `System/Library/Frameworks/Security.framework/Headers/SecTask.h` (57-65)
- `usr/include/xpc/connection.h` (772-803)
- `usr/include/sys/un.h` (88-93)
- `usr/include/libproc.h` (96, 102-103)
- `usr/include/sys/proc_info.h` (`proc_bsdinfo` at 59-82; flavors at 717-768)
- `usr/include/mach/mach_traps.h` (286), `usr/include/mach/task_info.h` (242-243)

Apple documentation:

- https://developer.apple.com/documentation/security/seccodecopyguestwithattributes(_:_:_:_:)
- https://developer.apple.com/documentation/security/seccodecheckvalidity(_:_:_:)
- https://developer.apple.com/documentation/xpc/xpc_connection_set_peer_code_signing_requirement(_:_:)
- https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements

Chrome extension documentation (for the documented argv convention):

- https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging

Live probes on this machine (macOS 26, ad-hoc-signed non-sandboxed test binaries, normal user): `LOCAL_PEERTOKEN`/`LOCAL_PEERPID` on a pipe vs a socketpair; `SecCodeCopyGuestWithAttributes` by PID and by audit token against running Helium and Zen with each browser's designated requirement; `task_name_for_pid` + `TASK_AUDIT_TOKEN`; `responsibility_get_pid_responsible_for_pid` for a child spawned with and without `responsibility_spawnattrs_setdisclaim`.
