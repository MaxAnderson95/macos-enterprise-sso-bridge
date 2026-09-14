import Compression
import Foundation

/// Reads the `SAMLRequest` the Application sent, far enough to say where its response
/// will land.
///
/// Both bindings Entra implements are supported, and they are told apart by what comes
/// out rather than by anything the request claims: HTTP-Redirect carries base64 of
/// raw-DEFLATE bytes, HTTP-POST carries base64 of the plain XML. Inflation is tried
/// first, and the result is used only if it opens like XML; otherwise the decoded bytes
/// are parsed directly. HTTP-Artifact is not handled because Entra does not implement
/// it, which is the same reason `SAMLart` is not recognized on the way back.
enum SAMLAuthnRequest {
  /// The Assertion Consumer Service URL, or the issuer when the request does not name
  /// one. Nil whenever the answer would be a guess: unreadable encoding, XML that is
  /// not an AuthnRequest, or an issuer spelled as a URN rather than a web address.
  static func destination(fromEncoded encoded: String) -> URL? {
    guard let xml = xml(fromEncoded: encoded) else { return nil }
    // External entities never load: this XML came from the Extension, which ADR 0002
    // treats as untrusted.
    guard
      let document = try? XMLDocument(data: xml, options: [.nodeLoadExternalEntitiesNever]),
      let root = document.rootElement(),
      root.localName == "AuthnRequest"
    else { return nil }

    if let consumer = root.attribute(forName: "AssertionConsumerServiceURL")?.stringValue,
      let url = webURL(consumer)
    {
      return url
    }
    let issuer = root.children?
      .compactMap { $0 as? XMLElement }
      .first { $0.localName == "Issuer" }?
      .stringValue
    return issuer.flatMap(webURL)
  }

  static func xml(fromEncoded encoded: String) -> Data? {
    guard let decoded = base64Decode(encoded), !decoded.isEmpty else { return nil }
    if let inflated = inflate(decoded), opensLikeXML(inflated) { return inflated }
    return opensLikeXML(decoded) ? decoded : nil
  }

  /// Standard base64, retried with the padding a redirect binding may have stripped.
  private static func base64Decode(_ text: String) -> Data? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let data = Data(base64Encoded: trimmed) { return data }
    let padding = String(repeating: "=", count: (4 - trimmed.count % 4) % 4)
    return Data(base64Encoded: trimmed + padding)
  }

  /// Raw DEFLATE, which is what `COMPRESSION_ZLIB` decodes: no zlib header, as the
  /// HTTP-Redirect binding specifies.
  ///
  /// One shot into a fixed buffer rather than a streaming loop. An AuthnRequest is a
  /// few kilobytes, so a megabyte is already absurd, and output that fills the buffer
  /// exactly is refused rather than assumed complete.
  private static func inflate(_ data: Data) -> Data? {
    let capacity = 1 << 20
    var output = Data(count: capacity)
    let written = output.withUnsafeMutableBytes { destination in
      data.withUnsafeBytes { source in
        compression_decode_buffer(
          destination.baseAddress!.assumingMemoryBound(to: UInt8.self),
          capacity,
          source.baseAddress!.assumingMemoryBound(to: UInt8.self),
          data.count,
          nil,
          COMPRESSION_ZLIB
        )
      }
    }
    guard written > 0, written < capacity else { return nil }
    return output.prefix(written)
  }

  /// A UTF-8 serializer may emit a byte-order mark, which is valid before the
  /// declaration and which `XMLDocument` parses happily, so skip it before looking for
  /// the opening angle bracket rather than discarding the document.
  private static func opensLikeXML(_ data: Data) -> Bool {
    var bytes = data[...]
    if bytes.starts(with: [0xef, 0xbb, 0xbf]) {
      bytes = bytes.dropFirst(3)
    }
    return bytes.drop { $0 == 0x20 || $0 == 0x09 || $0 == 0x0a || $0 == 0x0d }.first == 0x3c
  }

  /// An entity identifier is often a URN, which is nothing to show a user, so only an
  /// http(s) address with a host counts as a destination.
  private static func webURL(_ text: String) -> URL? {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      url.host() != nil
    else { return nil }
    return url
  }
}
