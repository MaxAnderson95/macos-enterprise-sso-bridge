import Foundation

/// The fields of a POST Callback, and the two places they can be read from.
///
/// `WKWebView` commonly hands a form submission to the navigation delegate with
/// `httpBody` nil, so docs/spec/callback-recognition.md has the Bridge try the body
/// first and then fall back to the submitting form in the DOM. Both paths live here as
/// values and a script; running the script is the navigation delegate's job, which is
/// what keeps the parsing and the urlencoded-only rule testable without a webview.
public enum CallbackBody {
  /// Which path produced the fields. The `os_log` line naming this is what the first
  /// end-to-end run against a real tenant answers, and the losing path is deleted then.
  public enum Source: String, Sendable {
    case httpBody = "httpBody"
    case domForm = "DOM form"
  }

  public struct Extraction: Equatable, Sendable {
    public let source: Source
    public let fields: [FormField]

    public init(source: Source, fields: [FormField]) {
      self.source = source
      self.fields = fields
    }

    /// The path and how many fields it produced. Never a name and never a value: the
    /// whole point of this line is answering which path fired.
    public var logSummary: String {
      "\(source.rawValue), \(fields.count) field\(fields.count == 1 ? "" : "s")"
    }
  }

  public static let urlencodedMediaType = "application/x-www-form-urlencoded"

  /// The positive rule: a body is recognized only when it says it is urlencoded.
  ///
  /// Both bindings that matter, SAML 2.0 HTTP POST and OAuth `form_post`, submit
  /// ordinary HTML forms, which default to urlencoded. Anything else leaving the
  /// provider is not a Callback under anything Entra implements, so an absent or
  /// unparsable content type answers no rather than being assumed benign.
  public static func isURLEncoded(_ contentType: String?) -> Bool {
    guard let contentType,
      let mediaType = contentType.split(separator: ";", maxSplits: 1).first
    else { return false }
    return mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      == urlencodedMediaType
  }

  /// Whether the request itself said it is sending something other than urlencoded.
  ///
  /// This is not the negation of `isURLEncoded`: an absent header says nothing, and that
  /// is the case the DOM fallback exists for. A header naming another media type is a
  /// refusal the document cannot overturn, because a submit button's `formenctype`
  /// changes what WebKit sends without changing the `form.enctype` the fallback reads.
  public static func declaresOtherMediaType(_ contentType: String?) -> Bool {
    contentType != nil && !isURLEncoded(contentType)
  }

  /// Path 1: the request's own body, when WebKit kept one and it is urlencoded.
  public static func fromHTTPBody(_ body: Data?, contentType: String?) -> Extraction? {
    guard isURLEncoded(contentType), let body, !body.isEmpty,
      let text = String(data: body, encoding: .utf8)
    else { return nil }
    let fields = urlencodedFields(text)
    return fields.isEmpty ? nil : Extraction(source: .httpBody, fields: fields)
  }

  /// Path 2's question, asked of the document that is submitting: the `FormData` of the
  /// form whose action is this navigation's target, with the enctype it would send.
  ///
  /// One expression so `evaluateJavaScript` returns its value, and JSON so the result
  /// crosses as a string rather than as a bridged `Any` whose shape has to be trusted.
  public static func matchingFormScript(action: URL) -> String {
    """
    (function () {
      var target = \(jsonString(action.absoluteString));
      var forms = document.forms;
      for (var i = 0; i < forms.length; i++) {
        var form = forms[i];
        if (form.action !== target) continue;
        var fields = [];
        new FormData(form).forEach(function (value, name) {
          if (typeof value === "string") fields.push([name, value]);
        });
        return JSON.stringify({ enctype: form.enctype, fields: fields });
      }
      return null;
    })()
    """
  }

  /// Path 2: what `matchingFormScript` returned, or nil for no matching form, an
  /// unreadable answer, or a form that would not have sent a urlencoded body.
  ///
  /// `form.enctype` always reflects a value and defaults to urlencoded, so the same
  /// positive rule the header path applies has something concrete to answer on here.
  public static func fromDOMForm(_ json: String?) -> Extraction? {
    guard let json, let data = json.data(using: .utf8),
      let form = try? JSONDecoder().decode(MatchingForm.self, from: data),
      isURLEncoded(form.enctype)
    else { return nil }
    let fields = form.fields.compactMap { pair -> FormField? in
      guard pair.count == 2, let name = pair.first, let value = pair.last, !name.isEmpty else {
        return nil
      }
      return FormField(name: name, value: value)
    }
    return fields.isEmpty ? nil : Extraction(source: .domForm, fields: fields)
  }

  private struct MatchingForm: Decodable {
    let enctype: String
    let fields: [[String]]
  }

  /// `name=value` pairs separated by `&`, with `+` for a space, which is what a form
  /// sends and what `URLComponents` does not decode on its own.
  static func urlencodedFields(_ text: String) -> [FormField] {
    text.split(separator: "&").compactMap { pair in
      let halves = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let name = percentDecoded(String(halves[0]))
      guard !name.isEmpty else { return nil }
      let value = halves.count > 1 ? percentDecoded(String(halves[1])) : ""
      return FormField(name: name, value: value)
    }
  }

  private static func percentDecoded(_ text: String) -> String {
    let spaced = text.replacingOccurrences(of: "+", with: " ")
    return spaced.removingPercentEncoding ?? spaced
  }

  /// A JSON string literal, which is also a JavaScript one. Slashes are left alone
  /// because escaping them is legal JSON that only makes the script harder to read.
  private static func jsonString(_ text: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    guard let data = try? encoder.encode(text),
      let literal = String(data: data, encoding: .utf8)
    else { return "\"\"" }
    return literal
  }
}
