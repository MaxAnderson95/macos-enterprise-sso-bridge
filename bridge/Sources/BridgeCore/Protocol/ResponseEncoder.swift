import Foundation

/// Turns a response into the bytes of a frame, and refuses to produce a frame nobody
/// can read.
public enum ResponseEncoder {
  /// Both engines cap a host-to-browser message at exactly 1 MiB: Chromium's
  /// `kMaximumNativeMessageSize`, which logs and closes the port with an IO error,
  /// and Gecko's `MAX_READ`, which throws an ExtensionError. Either way the Extension
  /// sees a bare disconnect that reads exactly like a crash.
  public static let hostToBrowserLimit = 1_024 * 1_024

  /// Headroom for the framing and accounting on the far side of the pipe, which the
  /// Bridge does not control. A Callback within 4 KiB of the cap is not a Callback
  /// worth gambling a silent disconnect on.
  public static let safetyMargin = 4_096

  public static var budget: Int { hostToBrowserLimit - safetyMargin }

  /// The encoded response, and which response that actually is. A Callback over the
  /// budget becomes `callback_too_large`, so the caller logs and the Extension reads
  /// what was really sent rather than what was asked for.
  public static func encode(_ response: BridgeResponse) throws -> (
    sent: BridgeResponse, payload: Data
  ) {
    let encoder = JSONEncoder()
    let payload = try encoder.encode(response)
    if payload.count <= budget {
      return (response, payload)
    }
    let substitute = BridgeResponse.error(
      .callbackTooLarge,
      detail: "encoded response exceeded the 1 MiB native-messaging cap"
    )
    return (substitute, try encoder.encode(substitute))
  }
}
