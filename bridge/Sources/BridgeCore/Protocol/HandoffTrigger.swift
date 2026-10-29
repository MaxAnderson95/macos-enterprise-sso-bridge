/// Who started a Handoff: the user's toolbar click, or the Extension on capturing a
/// Sign-in request.
///
/// The Extension is the party ADR 0002 distrusts, so this can only make the Bridge
/// stricter. An automatic Handoff whose destination is not a Pre-approved Application is
/// answered `approval_required` instead of interrupting the user with an Approval they
/// did not ask for; nothing here can skip the Approval. See
/// docs/adr/0004-pre-approved-applications-skip-the-approval.md.
public enum HandoffTrigger: String, Equatable, Sendable {
  case manual
  case automatic
}
