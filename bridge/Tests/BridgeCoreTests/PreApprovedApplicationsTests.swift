import Foundation
import Testing

@testable import BridgeCore

/// What counts as a listed origin, and what a destination has to be to match one. The
/// list skips the Approval, so an entry that matched more than the user named would
/// skip it for an Application they never chose.
@Suite("Pre-approved Applications")
struct PreApprovedApplicationsTests {
  private func listing(_ entries: String...) -> PreApprovedApplications {
    PreApprovedApplications(preferenceValue: entries)
  }

  private func url(_ string: String) -> URL {
    URL(string: string)!
  }

  @Test(
    "A destination matches an origin listed with or without its default port",
    arguments: [
      "https://app.example.com", "https://app.example.com/", "https://app.example.com:443",
    ]
  )
  func defaultPort(entry: String) {
    let list = listing(entry)
    #expect(list.contains(url("https://app.example.com/signin-oidc")))
    #expect(list.contains(url("https://app.example.com:443/sso/acs?x=1")))
  }

  @Test("An explicit port matches only that port")
  func explicitPort() {
    let list = listing("https://app.example.com:8443")
    #expect(list.contains(url("https://app.example.com:8443/callback")))
    #expect(!list.contains(url("https://app.example.com/callback")))
  }

  @Test("Host case does not matter on either side")
  func hostCase() {
    #expect(listing("https://App.Example.COM").contains(url("https://app.example.com/c")))
    #expect(listing("https://app.example.com").contains(url("https://APP.example.com/c")))
  }

  @Test(
    "Anything other than the exact origin does not match",
    arguments: [
      "http://app.example.com/c",
      "https://other.example.com/c",
      "https://sub.app.example.com/c",
      "https://app.example.com.attacker.example/c",
      "https://app.example.com:8443/c",
    ]
  )
  func mismatches(destination: String) {
    #expect(!listing("https://app.example.com").contains(url(destination)))
  }

  // ADR 0004: a plan with no bound destination always gets the Approval.
  @Test("A nil destination is never pre-approved")
  func nilDestination() {
    #expect(!listing("https://app.example.com").contains(nil))
  }

  @Test(
    "An entry that is not an HTTPS origin is ignored",
    arguments: [
      "http://app.example.com",
      "https://app.example.com/path",
      "https://app.example.com/?",
      "https://app.example.com?q=1",
      "https://app.example.com#fragment",
      "https://user@app.example.com",
      "https://user:secret@app.example.com",
      "app.example.com",
      "https://",
      "",
      "not a url",
    ]
  )
  func rejectedEntries(entry: String) {
    let list = listing(entry)
    #expect(!PreApprovedApplications.isReadable(entry))
    #expect(list == PreApprovedApplications(preferenceValue: nil))
    #expect(!list.contains(url("https://app.example.com/c")))
  }

  @Test("A rejected entry leaves the valid ones around it in place")
  func mixedEntries() {
    let list = PreApprovedApplications(
      preferenceValue: [
        "https://app.example.com/path", 7, "https://two.example.com",
      ] as [Any])
    #expect(list.contains(url("https://two.example.com/c")))
    #expect(!list.contains(url("https://app.example.com/path")))
  }

  @Test(
    "The editor stores what was typed as an origin",
    arguments: [
      ("app.example.com", "https://app.example.com"),
      ("  App.Example.COM \n", "https://app.example.com"),
      ("https://app.example.com/signin-oidc?x=1#top", "https://app.example.com"),
      ("https://app.example.com:443/", "https://app.example.com"),
      ("app.example.com:8443", "https://app.example.com:8443"),
      ("https://app.example.com:8443/sso", "https://app.example.com:8443"),
    ]
  )
  func editorEntry(input: String, entry: String) {
    #expect(PreApprovedApplications.entry(from: input) == entry)
    // Whatever the editor stores, the Bridge must read back as a listed origin.
    #expect(PreApprovedApplications(preferenceValue: [entry]).contains(url("\(entry)/c")))
  }

  @Test(
    "The editor refuses what could never be a listed origin",
    arguments: [
      "", "   ", "http://app.example.com", "ftp://app.example.com",
      "https://user@app.example.com", "https://user:secret@app.example.com", "https://",
      "not a url",
    ]
  )
  func editorRefusal(input: String) {
    #expect(PreApprovedApplications.entry(from: input) == nil)
  }

  @Test("A missing key, an empty array, or a value that is not an array pre-approves nothing")
  func nothingListed() {
    let destination = url("https://app.example.com/c")
    #expect(!PreApprovedApplications(preferenceValue: nil).contains(destination))
    #expect(!PreApprovedApplications(preferenceValue: [String]()).contains(destination))
    #expect(
      !PreApprovedApplications(preferenceValue: "https://app.example.com").contains(destination))
  }
}
