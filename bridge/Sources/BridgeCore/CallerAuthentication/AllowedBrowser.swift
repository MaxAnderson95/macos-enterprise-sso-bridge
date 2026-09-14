/// A browser whose code-signing identity the Bridge accepts as a Caller.
///
/// The set is fixed at build time. A data file or an `Info.plist` key would sit in an
/// ad-hoc-signed bundle whose resources are writable by anyone who can reach the `.app`,
/// so a browser that rotates its Team ID or renames its bundle needs a Bridge rebuild.
public struct AllowedBrowser: Sendable, Equatable {
  /// Named in the Approval, so it is the browser's own name, not its bundle identifier.
  public let displayName: String
  public let bundleIdentifier: String
  public let teamIdentifier: String

  /// The browser's designated requirement, verbatim as `codesign -d -r-` reports it.
  /// Read off the installed bundle rather than composed from the Team ID, so the string
  /// carries the same anchor and certificate markers the system itself would check.
  public let requirement: String

  public static let helium = AllowedBrowser(
    displayName: "Helium",
    bundleIdentifier: "net.imput.helium",
    teamIdentifier: "S4Q33XPHB4",
    requirement: """
      identifier "net.imput.helium" and anchor apple generic and \
      certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and \
      certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and \
      certificate leaf[subject.OU] = S4Q33XPHB4
      """
  )

  public static let zen = AllowedBrowser(
    displayName: "Zen",
    bundleIdentifier: "app.zen-browser.zen",
    teamIdentifier: "9V5K9TP787",
    requirement: """
      identifier "app.zen-browser.zen" and anchor apple generic and \
      certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and \
      certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and \
      certificate leaf[subject.OU] = "9V5K9TP787"
      """
  )

  public static let all: [AllowedBrowser] = [helium, zen]
}
