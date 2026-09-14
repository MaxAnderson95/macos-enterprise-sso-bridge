import Foundation
import Testing

@testable import BridgeCore

/// Both extraction paths as values: the parsing, and the positive rule that decides
/// whether either path is allowed to answer at all. What a real `WKWebView` actually
/// hands over is the question the `os_log` line in `HandoffWebView` exists to settle.
@Suite("Extracting a POST Callback's fields")
struct CallbackBodyTests {
  private static let urlencoded = "application/x-www-form-urlencoded"

  @Test(
    "Only a urlencoded content type is recognized",
    arguments: [
      (urlencoded, true),
      ("application/x-www-form-urlencoded; charset=UTF-8", true),
      ("Application/X-WWW-Form-Urlencoded", true),
      ("  application/x-www-form-urlencoded  ", true),
      ("multipart/form-data; boundary=----x", false),
      ("application/json", false),
      ("text/plain", false),
      ("", false),
    ]
  )
  func contentType(_ value: String, _ recognized: Bool) {
    #expect(CallbackBody.isURLEncoded(value) == recognized)
  }

  /// A positive rule, not a `multipart/` exclusion: a body that does not say it is
  /// urlencoded is not read, and the POST it belongs to proceeds uncaptured.
  @Test("A body with no content type at all is not recognized")
  func missingContentType() {
    #expect(!CallbackBody.isURLEncoded(nil))
    #expect(
      CallbackBody.fromHTTPBody(Data("SAMLResponse=PHNhbWxw".utf8), contentType: nil) == nil)
  }

  @Test("A urlencoded body becomes its fields, in order, repeats and all")
  func httpBody() throws {
    let body = "SAMLResponse=PHNhbWxw&RelayState=a+b&RelayState=%2Fhome&empty=&flag"
    let extraction = try #require(
      CallbackBody.fromHTTPBody(Data(body.utf8), contentType: Self.urlencoded))

    #expect(extraction.source == .httpBody)
    #expect(
      extraction.fields == [
        FormField(name: "SAMLResponse", value: "PHNhbWxw"),
        FormField(name: "RelayState", value: "a b"),
        FormField(name: "RelayState", value: "/home"),
        FormField(name: "empty", value: ""),
        FormField(name: "flag", value: ""),
      ]
    )
  }

  @Test("A multipart body is never read, whatever it contains")
  func multipartBody() {
    let body = """
      ------x\r
      Content-Disposition: form-data; name="SAMLResponse"\r
      \r
      PHNhbWxw\r
      ------x--\r

      """
    #expect(
      CallbackBody.fromHTTPBody(
        Data(body.utf8), contentType: "multipart/form-data; boundary=----x") == nil)
  }

  @Test("No body, or one with nothing in it, produces no extraction")
  func emptyBody() {
    #expect(CallbackBody.fromHTTPBody(nil, contentType: Self.urlencoded) == nil)
    #expect(CallbackBody.fromHTTPBody(Data(), contentType: Self.urlencoded) == nil)
    #expect(CallbackBody.fromHTTPBody(Data("&&".utf8), contentType: Self.urlencoded) == nil)
  }

  @Test("The DOM answer becomes its fields when the form would send urlencoded")
  func domForm() throws {
    let answer = """
      {"enctype":"application/x-www-form-urlencoded",
       "fields":[["SAMLResponse","PHNhbWxw"],["RelayState","opaque"]]}
      """
    let extraction = try #require(CallbackBody.fromDOMForm(answer))

    #expect(extraction.source == .domForm)
    #expect(
      extraction.fields == [
        FormField(name: "SAMLResponse", value: "PHNhbWxw"),
        FormField(name: "RelayState", value: "opaque"),
      ]
    )
  }

  /// `form.enctype` always reflects a value and defaults to urlencoded, so the same
  /// positive rule the header path applies has something concrete to answer on here.
  @Test(
    "A form that would send anything else is not read either",
    arguments: [
      #"{"enctype":"multipart/form-data","fields":[["SAMLResponse","PHNhbWxw"]]}"#,
      #"{"enctype":"text/plain","fields":[["SAMLResponse","PHNhbWxw"]]}"#,
    ]
  )
  func domFormNotURLEncoded(_ answer: String) {
    #expect(CallbackBody.fromDOMForm(answer) == nil)
  }

  @Test("No matching form, and anything unreadable, produce no extraction")
  func domFormAbsent() {
    #expect(CallbackBody.fromDOMForm(nil) == nil)
    #expect(CallbackBody.fromDOMForm("null") == nil)
    #expect(CallbackBody.fromDOMForm("undefined") == nil)
    #expect(CallbackBody.fromDOMForm(#"{"enctype":"\#(Self.urlencoded)","fields":[]}"#) == nil)
  }

  /// The line the first end-to-end run reads. It names the path and counts the fields,
  /// and carries no name and no value, which is the logging rule for every line.
  @Test("The log summary names the path and never the fields")
  func logSummary() {
    let fields = [FormField(name: "SAMLResponse", value: "PHNhbWxw")]
    #expect(
      CallbackBody.Extraction(source: .httpBody, fields: fields).logSummary
        == "httpBody, 1 field")
    #expect(
      CallbackBody.Extraction(source: .domForm, fields: fields + fields).logSummary
        == "DOM form, 2 fields")
  }

  /// The script has to be one expression, because `evaluateJavaScript` hands back the
  /// value of the last one, and the target it compares against has to be the exact URL
  /// the navigation is going to.
  @Test("The script embeds its target as a string literal")
  func script() throws {
    let url = try #require(URL(string: "https://app.example.com/sso/acs?a=1&b=2"))
    let script = CallbackBody.matchingFormScript(action: url)

    #expect(script.hasPrefix("(function () {"))
    #expect(script.hasSuffix("})()"))
    #expect(script.contains(#"var target = "https://app.example.com/sso/acs?a=1&b=2";"#))
  }
}
