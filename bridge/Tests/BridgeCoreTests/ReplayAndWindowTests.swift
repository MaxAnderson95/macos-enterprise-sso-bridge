import Foundation
import Testing

@testable import BridgeCore

/// A POST Sign-in request is replayed as the form the Application itself submitted, so
/// what matters is that the fields arrive intact, in order, and cannot escape their
/// attributes.
@Suite("Replaying a POST Sign-in request")
struct FormSubmissionDocumentTests {
  private let action = URL(string: "https://login.microsoftonline.com/tenant/saml2")!

  @Test("The captured fields are hidden inputs in the order they were captured")
  func fieldsInOrder() {
    let html = FormSubmissionDocument.html(
      action: action,
      fields: [
        FormField(name: "SAMLRequest", value: "fVLLbtsw"),
        FormField(name: "RelayState", value: "opaque"),
        FormField(name: "RelayState", value: "second"),
      ]
    )

    #expect(html.contains("action=\"https://login.microsoftonline.com/tenant/saml2\""))
    #expect(html.contains("method=\"post\""))
    let names = html.components(separatedBy: "name=\"").dropFirst().map {
      $0.prefix(while: { $0 != "\"" })
    }
    #expect(names == ["SAMLRequest", "RelayState", "RelayState"])
    #expect(html.contains("value=\"fVLLbtsw\""))
    #expect(html.contains("value=\"second\""))
  }

  @Test("A value that could close its attribute cannot")
  func escaping() {
    let html = FormSubmissionDocument.html(
      action: action,
      fields: [FormField(name: "RelayState", value: "\"><script>alert(1)</script>")]
    )

    #expect(!html.contains("<script>alert(1)"))
    #expect(html.contains("value=\"&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;\""))
  }

  @Test("A field value carrying an ampersand survives as itself")
  func ampersand() {
    let html = FormSubmissionDocument.html(
      action: action,
      fields: [FormField(name: "RelayState", value: "a&b")]
    )
    #expect(html.contains("value=\"a&amp;b\""))
  }
}

/// The window's copy for the states after the Approval. Same rule as `ApprovalPrompt`:
/// every value is one the Bridge derived for itself, and it is readable without AppKit.
@Suite("What the window says after the Approval")
struct HandoffWindowCopyTests {
  @Test("The footer keeps naming the destination the Approval named")
  func withDestination() {
    let copy = HandoffWindowCopy(
      destinationHost: "app.example.com", providerHost: "login.microsoftonline.com")
    #expect(copy.authenticating == "Signing in to app.example.com.")
    #expect(copy.returningCallback == "Handing the sign-in back to your browser.")
  }

  @Test("With no derivable destination the footer names the provider instead")
  func withoutDestination() {
    let copy = HandoffWindowCopy(destinationHost: nil, providerHost: "login.microsoftonline.com")
    #expect(copy.authenticating == "Signing in through login.microsoftonline.com.")
  }

  /// The failure state names the host whose page was on screen and what to do next.
  /// The coded reason is a console diagnostic and never reaches the window.
  @Test("The failure state says what happened without a code in it")
  func failure() {
    let copy = HandoffWindowCopy(
      prompt: ApprovalPrompt(
        destinationHost: "app.example.com",
        providerHost: "login.microsoftonline.com",
        browserName: "Helium"
      )
    )
    #expect(copy.failureHeading == "Sign-in could not be completed")
    #expect(
      copy.failureBody == "login.microsoftonline.com could not be reached. Nothing was "
        + "returned to your browser; start the sign-in again from the site's login page."
    )
  }
}
