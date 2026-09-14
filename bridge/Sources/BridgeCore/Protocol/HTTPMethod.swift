/// The two methods the protocol carries, on a Sign-in request and on a Callback alike.
///
/// Spelled exactly as the wire spells them, so the raw value is both the decoder's
/// accepted input and the encoder's output.
public enum HTTPMethod: String, Equatable, Sendable {
  case get = "GET"
  case post = "POST"
}
