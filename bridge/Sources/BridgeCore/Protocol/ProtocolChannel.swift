import Foundation

/// The wire version the Extension sends and this Bridge implements. An integer,
/// bumped only on a breaking change, and the whole of the skew story: the two halves
/// are installed by hand and independently, so nothing stops a new `.pkg` from
/// meeting last month's extension.
public enum ProtocolVersion {
  public static let supported = 1
}

/// One request in, one terminal response out, then the process exits.
///
/// The version check and the malformed-request answer live here rather than in the
/// codecs, because both are decisions about what to say back, and saying something
/// back exactly once is this type's whole job.
public final class ProtocolChannel {
  /// What a request frame earned: either a Sign-in request to act on, or the terminal
  /// response that answers it without the rest of the Bridge ever being involved.
  public enum ReceivedRequest: Equatable {
    case request(SignInRequest)
    case answer(BridgeResponse)
  }

  private let frames: FrameChannel
  private var didRespond = false

  public init(frames: FrameChannel) {
    self.frames = frames
  }

  public static func standardIO() -> ProtocolChannel {
    ProtocolChannel(frames: .standardIO())
  }

  /// Reads the one request frame.
  ///
  /// Throws `FramingError` when the framing itself is broken, which means the channel
  /// is not usable and the caller must exit non-zero without writing. Anything that
  /// arrives as a whole frame is answerable, so it returns rather than throws.
  public func receiveRequest() throws -> ReceivedRequest {
    let payload = try frames.readFrame()
    let decoder = JSONDecoder()

    guard let envelope = try? decoder.decode(VersionEnvelope.self, from: payload) else {
      BridgeLog.wire.error("request frame carries no integer version")
      return .answer(.error(.malformedRequest, detail: "missing or non-integer version"))
    }
    guard envelope.version == ProtocolVersion.supported else {
      BridgeLog.wire.error(
        "request version \(envelope.version, privacy: .public) is not implemented"
      )
      let code = BridgeErrorCode.unsupportedVersion(bridgeVersion: ProtocolVersion.supported)
      return .answer(.error(code, detail: nil))
    }
    guard let message = try? decoder.decode(RequestMessage.self, from: payload) else {
      BridgeLog.wire.error("request frame does not match the version 1 schema")
      return .answer(.error(.malformedRequest, detail: "request schema"))
    }

    BridgeLog.wire.info("received \(message.signInRequest.logSummary, privacy: .public)")
    return .request(message.signInRequest)
  }

  /// Writes the terminal response and returns the response that actually went, which is
  /// `callback_too_large` when the Callback did not fit the cap. Nil means nothing was
  /// written: the second and later calls write nothing, so a Handoff with several
  /// termination paths cannot put two frames on the wire.
  @discardableResult
  public func send(_ response: BridgeResponse) throws -> BridgeResponse? {
    guard !didRespond else {
      BridgeLog.wire.error(
        "suppressed a second terminal response: \(response.logSummary, privacy: .public)"
      )
      return nil
    }
    didRespond = true
    let (sent, payload) = try ResponseEncoder.encode(response)
    try frames.writeFrame(payload)
    BridgeLog.wire.info("sent \(sent.logSummary, privacy: .public)")
    return sent
  }
}
