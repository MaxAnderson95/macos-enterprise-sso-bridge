import Darwin
import Foundation
import Security

/// Why the Bridge will not serve this Caller. Both cases are logged before they are
/// thrown, so a caller of `verify()` decides what to do and never what to say.
public enum CallerAuthenticationFailure: Error {
  /// Finder, Dock, or launchd started the Bridge. There is no Sign-in request and no
  /// pipe, so there is nothing to serve, but the user is owed an explanation.
  case userLaunch

  /// Anything else. Exit non-zero having written nothing to stdout.
  case rejected
}

/// Decides whether the process that launched the Bridge may be served.
///
/// The native-messaging manifest names a world-readable absolute path, so any local
/// process can run the Bridge. `verify()` is the gate: it runs at the top of `main`,
/// before `NSApplication` and before a byte of stdin, and either hands back the
/// `AllowedBrowser` that spawned this process or throws.
///
/// It proves that the parent, at the moment of capture, is one incarnation of a binary
/// whose code signature satisfies an Allowed browser's designated requirement. It does
/// not prove that the pipes came from that process, that the parent did not `exec` into
/// a browser after spawning, or that no attacker code runs inside the browser. See
/// `docs/adr/0001-caller-authentication-by-parent-audit-token.md`.
public enum CallerAuthentication {
  /// Apple's designated requirements for the launchers that count as a user launch,
  /// read from the installed system bundles with `codesign -d -r-`.
  private static let userLaunchers: [(displayName: String, requirement: String)] = [
    ("Finder", "identifier \"com.apple.finder\" and anchor apple"),
    ("Dock", "identifier \"com.apple.dock\" and anchor apple"),
  ]

  public static func verify() throws -> AllowedBrowser {
    let parent = getppid()

    // launchd starts everything the user opens from Finder, the Dock, or `open`, and it
    // is the one process whose task port a normal user cannot get: `task_name_for_pid(1)`
    // returns KERN_FAILURE, so pid 1 is recognized by being pid 1. It buys a window and
    // nothing else. A process orphaned by a browser that died mid-spawn lands here too,
    // and has just as little to do.
    if parent == 1 {
      BridgeLog.caller.info("user launch from launchd")
      throw CallerAuthenticationFailure.userLaunch
    }

    let code = try parentCode(of: parent)

    // A caller that is simply not a browser fails every entry with the same
    // uninformative `errSecCSReqFailed`; anything else is how a browser update that
    // broke its own signature looks from here, so that status is the one worth logging.
    var reportedStatus = errSecCSReqFailed
    for browser in AllowedBrowser.all {
      let status = check(code, against: browser.requirement)
      if status == errSecSuccess {
        BridgeLog.caller.info("caller authenticated: \(browser.displayName, privacy: .public)")
        return browser
      }
      if status != errSecCSReqFailed {
        reportedStatus = status
      }
    }

    for launcher in userLaunchers where check(code, against: launcher.requirement) == errSecSuccess
    {
      BridgeLog.caller.info("user launch from \(launcher.displayName, privacy: .public)")
      throw CallerAuthenticationFailure.userLaunch
    }

    logRejection(of: code, pid: parent, status: reportedStatus)
    throw CallerAuthenticationFailure.rejected
  }

  /// The parent's code identity, resolved from its audit token.
  ///
  /// The token's pidversion pins one incarnation of the PID, which closes the reuse
  /// window a bare `kSecGuestAttributePid` lookup leaves open. A Mach failure rejects:
  /// there is no downgrade to the bare-PID path.
  private static func parentCode(of pid: pid_t) throws -> SecCode {
    guard let token = auditToken(of: pid) else {
      throw CallerAuthenticationFailure.rejected
    }

    let attributes =
      [kSecGuestAttributeAudit: withUnsafeBytes(of: token) { Data($0) }] as CFDictionary
    var code: SecCode?
    let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
    guard status == errSecSuccess, let code else {
      BridgeLog.caller.error(
        "rejected caller: no code identity for parent \(pid, privacy: .public), OSStatus \(status, privacy: .public)"
      )
      throw CallerAuthenticationFailure.rejected
    }
    return code
  }

  /// `TASK_AUDIT_TOKEN_COUNT` is a macro over `sizeof`, which Swift does not import.
  static let auditTokenCount = MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size

  private static func auditToken(of pid: pid_t) -> audit_token_t? {
    var port = mach_port_name_t(MACH_PORT_NULL)
    let lookup = task_name_for_pid(mach_task_self_, pid, &port)
    guard lookup == KERN_SUCCESS else {
      BridgeLog.caller.error(
        "rejected caller: no task name port for parent \(pid, privacy: .public), kern_return \(lookup, privacy: .public)"
      )
      return nil
    }
    defer { mach_port_deallocate(mach_task_self_, port) }

    var token = audit_token_t()
    var count = mach_msg_type_number_t(auditTokenCount)
    let info = withUnsafeMutablePointer(to: &token) {
      $0.withMemoryRebound(to: integer_t.self, capacity: auditTokenCount) {
        task_info(port, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
      }
    }
    guard info == KERN_SUCCESS else {
      BridgeLog.caller.error(
        "rejected caller: no audit token for parent \(pid, privacy: .public), kern_return \(info, privacy: .public)"
      )
      return nil
    }
    return token
  }

  /// `errSecSuccess` when the code satisfies the requirement, otherwise the status that
  /// says why, including a requirement string this build failed to compile.
  static func check(_ code: SecCode, against requirement: String) -> OSStatus {
    var compiled: SecRequirement?
    let compileStatus = SecRequirementCreateWithString(requirement as CFString, [], &compiled)
    guard compileStatus == errSecSuccess, let compiled else { return compileStatus }
    return SecCodeCheckValidityWithErrors(code, [], compiled, nil)
  }

  /// A local process's bundle identifier and executable path are not Handoff data, and
  /// they are what tells a browser update that changed its signature from a hostile
  /// launcher, so both go in the line alongside the `OSStatus`.
  private static func logRejection(of code: SecCode, pid: pid_t, status: OSStatus) {
    var information: CFDictionary?
    let staticCode = unsafeBitCast(code, to: SecStaticCode.self)
    SecCodeCopySigningInformation(staticCode, [], &information)
    let fields = information as? [CFString: Any]
    let identifier = fields?[kSecCodeInfoIdentifier] as? String ?? "unknown"
    let executable = (fields?[kSecCodeInfoMainExecutable] as? URL)?.path ?? "unknown"

    BridgeLog.caller.error(
      """
      rejected caller: parent \(pid, privacy: .public) \(identifier, privacy: .public) \
      at \(executable, privacy: .public) satisfies no Allowed browser, \
      OSStatus \(status, privacy: .public)
      """
    )
  }
}
