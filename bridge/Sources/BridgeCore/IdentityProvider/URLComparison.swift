import Foundation

extension URL {
  /// The port the request actually uses, so an origin written with its default port
  /// compares equal to the same origin written without one.
  var effectivePort: Int? {
    if let port { return port }
    switch scheme?.lowercased() {
    case "https": return 443
    case "http": return 80
    default: return nil
    }
  }
}
