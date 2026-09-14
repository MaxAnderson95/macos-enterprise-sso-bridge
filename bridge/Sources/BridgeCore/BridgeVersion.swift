import Foundation

/// The version the Bridge reports about itself.
///
/// `packaging/build-app.sh` writes the release version into the bundle's
/// `CFBundleShortVersionString`. A build made without `--version` keeps the
/// default `0.0.0`, which is visibly not a release rather than impersonating one.
public enum BridgeVersion {
  public static let developmentBuild = "0.0.0"

  public static var current: String {
    let key = "CFBundleShortVersionString"
    return resolve(shortVersionString: Bundle.main.object(forInfoDictionaryKey: key) as? String)
  }

  public static func resolve(shortVersionString: String?) -> String {
    guard
      let trimmed = shortVersionString?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return developmentBuild
    }
    return trimmed
  }
}
