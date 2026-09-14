import Foundation

/// What the window says once the user has approved, in the same place and for the same
/// reason as `ApprovalPrompt`: readable without AppKit, and built only from values the
/// Bridge established for itself.
///
/// The footer is where the destination stays visible after the provider's page fills
/// the window, so it is the same host the Approval named, not a second answer to the
/// same question.
public struct HandoffWindowCopy: Equatable, Sendable {
  public let destinationHost: String?
  public let providerHost: String

  public init(prompt: ApprovalPrompt) {
    self.init(destinationHost: prompt.destinationHost, providerHost: prompt.providerHost)
  }

  public init(destinationHost: String?, providerHost: String) {
    self.destinationHost = destinationHost
    self.providerHost = providerHost
  }

  /// State 3, while the provider's page is up.
  public var authenticating: String {
    if let destinationHost {
      "Signing in to \(destinationHost)."
    } else {
      "Signing in through \(providerHost)."
    }
  }

  /// State 4, usually on screen for well under a second: the Callback was recognized
  /// and stopped, and the Bridge is writing its response.
  public var returningCallback: String {
    "Handing the sign-in back to your browser."
  }

  public var failureHeading: String {
    "Sign-in could not be completed"
  }

  /// Names the provider, because that is the host whose page was on screen when it
  /// failed, and says what to do next. The coded reason is a console diagnostic and
  /// stays out of here.
  public var failureBody: String {
    "\(providerHost) could not be reached. Nothing was returned to your browser; start "
      + "the sign-in again from the site's login page."
  }
}
