import Foundation
import Security
import Testing

@testable import BridgeCore

/// `verify()` itself is unreachable from a test: the test runner's parent is a shell, so
/// it can only ever be rejected, and nothing that skips the gate is compiled anywhere.
/// What is testable without a bypass is the machinery it is built from, exercised against
/// this process's own code identity, plus the table it checks against. The rejection path
/// is covered by `packaging/caller-authentication-negative-test.sh`.
@Suite("Caller authentication")
struct CallerAuthenticationTests {
  /// The running test binary, resolved the same way `verify()` resolves its parent.
  private func selfCode() throws -> SecCode {
    var port = mach_port_name_t(MACH_PORT_NULL)
    #expect(task_name_for_pid(mach_task_self_, getpid(), &port) == KERN_SUCCESS)
    defer { mach_port_deallocate(mach_task_self_, port) }

    var token = audit_token_t()
    var count = mach_msg_type_number_t(CallerAuthentication.auditTokenCount)
    let info = withUnsafeMutablePointer(to: &token) {
      $0.withMemoryRebound(to: integer_t.self, capacity: CallerAuthentication.auditTokenCount) {
        task_info(port, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
      }
    }
    #expect(info == KERN_SUCCESS)

    let attributes =
      [kSecGuestAttributeAudit: withUnsafeBytes(of: token) { Data($0) }] as CFDictionary
    var code: SecCode?
    #expect(SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess)
    return try #require(code)
  }

  @Test("Every Allowed browser's requirement compiles", arguments: AllowedBrowser.all)
  func requirementCompiles(browser: AllowedBrowser) {
    var compiled: SecRequirement?
    #expect(
      SecRequirementCreateWithString(browser.requirement as CFString, [], &compiled)
        == errSecSuccess
    )
  }

  @Test(
    "Every requirement names its own bundle identifier and team identifier",
    arguments: AllowedBrowser.all
  )
  func requirementNamesItsBrowser(browser: AllowedBrowser) {
    #expect(browser.requirement.contains("identifier \"\(browser.bundleIdentifier)\""))
    #expect(browser.requirement.contains(browser.teamIdentifier))
    #expect(browser.requirement.contains("anchor apple generic"))
  }

  @Test("The v1 table is Helium and Zen")
  func tableContents() {
    #expect(
      AllowedBrowser.all.map(\.bundleIdentifier) == ["net.imput.helium", "app.zen-browser.zen"]
    )
  }

  // The audit-token path is the whole identity source: if the Mach trap or the guest
  // lookup stopped working, every Caller would be rejected and only this would say why.
  @Test("An audit token resolves to the code identity of the process it came from")
  func auditTokenResolvesToItsProcess() throws {
    let code = try selfCode()
    var information: CFDictionary?
    let staticCode = unsafeBitCast(code, to: SecStaticCode.self)
    #expect(SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess)

    let fields = try #require(information as? [CFString: Any])
    // The two values a rejection line is made of.
    let executable = try #require(fields[kSecCodeInfoMainExecutable] as? URL)
    #expect(FileManager.default.fileExists(atPath: executable.path))
    #expect(fields[kSecCodeInfoIdentifier] as? String != nil)
  }

  @Test("A code identity that satisfies a requirement passes the check")
  func matchingRequirementPasses() throws {
    let code = try selfCode()
    var designated: SecRequirement?
    let staticCode = unsafeBitCast(code, to: SecStaticCode.self)
    #expect(SecCodeCopyDesignatedRequirement(staticCode, [], &designated) == errSecSuccess)

    var text: CFString?
    #expect(SecRequirementCopyString(try #require(designated), [], &text) == errSecSuccess)
    #expect(
      CallerAuthentication.check(code, against: try #require(text) as String) == errSecSuccess)
  }

  @Test("A code identity that is not an Allowed browser fails every entry")
  func testRunnerIsNotAnAllowedBrowser() throws {
    let code = try selfCode()
    for browser in AllowedBrowser.all {
      #expect(CallerAuthentication.check(code, against: browser.requirement) == errSecCSReqFailed)
    }
  }

  @Test("A requirement that does not compile fails rather than passing")
  func brokenRequirementFails() throws {
    let code = try selfCode()
    #expect(CallerAuthentication.check(code, against: "not a requirement at all") != errSecSuccess)
  }
}
