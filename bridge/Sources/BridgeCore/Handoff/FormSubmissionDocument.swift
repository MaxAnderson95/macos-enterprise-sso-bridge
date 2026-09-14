import Foundation

/// A document whose only content is the captured form, submitted the moment it loads.
///
/// This is how the Bridge replays a POST Sign-in request, and it is what the
/// Application itself did: SAML's HTTP-POST binding and OAuth's `form_post` are
/// auto-submitting forms, so replaying one reproduces the original request rather than
/// imitating it. Same method, same target, same `application/x-www-form-urlencoded`
/// encoding, same fields in the same order, and the same request metadata a form
/// navigation carries.
///
/// The alternative is `WKWebView.load` with a `URLRequest` carrying an `httpBody`, and
/// both were measured against an echo server on macOS 26: the body did arrive, so the
/// long-standing WebKit behaviour of dropping it on the way to the networking process
/// is not what rules it out. What rules it out is the shape of the request that
/// results. The form submission arrives as `Sec-Fetch-Site: cross-site` with
/// `Sec-Fetch-Mode: navigate`, which is what the Application's own POST into the
/// provider looks like; the `URLRequest` load arrives as `Sec-Fetch-Site: none`, which
/// claims the user typed it into an address bar. A sign-in is exactly the request
/// where an identity provider is entitled to read that difference.
///
/// What neither reproduces is the original navigation's `Origin` and `Referer`. Both
/// send `Origin: null`, because the Sign-in request the Extension captured carries a
/// URL, a method, and fields and nothing else.
public enum FormSubmissionDocument {
  public static func html(action: URL, fields: [FormField]) -> String {
    let inputs = fields.map { field in
      "<input type=\"hidden\" name=\"\(escaped(field.name))\" value=\"\(escaped(field.value))\">"
    }
    return """
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"><title>Signing in</title></head>
      <body>
      <form id="replay" method="post" action="\(escaped(action.absoluteString))">
      \(inputs.joined(separator: "\n"))
      </form>
      <script>document.getElementById("replay").submit();</script>
      </body>
      </html>
      """
  }

  /// Enough to keep a field value inside its attribute. A `SAMLRequest` is base64 and a
  /// `RelayState` is opaque, so both can carry any of these.
  private static func escaped(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
