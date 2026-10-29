import AppKit
import BridgeCore

/// The user-launch window's list of Pre-approved Applications: the same preferences key
/// `defaults write` edits, so either way of changing it is visible to the other. Every
/// change is saved as it is made, because the Bridge reads the list at the start of each
/// Handoff and there is no later moment to save at.
///
/// Editing here is safe for the same reason the Approval is: browser-resident code
/// cannot click in this window, and this window only exists for a user launch, which
/// never carries a Sign-in request. See docs/adr/0004-pre-approved-applications-skip-the-approval.md.
@MainActor
final class PreApprovedApplicationsEditor: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  private var entries = PreApprovedApplications.storedEntries()

  private let table = NSTableView()
  private let input = NSTextField()
  private let message = NSTextField(labelWithString: "")
  private lazy var addButton = NSButton(title: "Add", target: self, action: #selector(add))
  private lazy var removeButton = NSButton(
    title: "Remove", target: self, action: #selector(remove))

  /// Where typing should land when the window opens, rather than in the table.
  var initialFirstResponder: NSView { input }

  func makeView() -> NSView {
    let heading = NSTextField(labelWithString: "Pre-approved Applications")
    heading.font = .preferredFont(forTextStyle: .headline)

    let explanation = NSTextField(
      wrappingLabelWithString:
        "Sign-ins to these sites start on their own and skip the question. List only sites "
        + "you use every day."
    )
    explanation.textColor = .secondaryLabelColor

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("origin"))
    table.addTableColumn(column)
    table.headerView = nil
    table.allowsMultipleSelection = true
    table.usesAlternatingRowBackgroundColors = true
    table.dataSource = self
    table.delegate = self

    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    scroll.heightAnchor.constraint(equalToConstant: 120).isActive = true

    input.placeholderString = "app.example.com"
    // The window's default button, so Return in the field adds what was typed.
    addButton.keyEquivalent = "\r"
    removeButton.isEnabled = false

    let controls = NSStackView(views: [input, addButton, removeButton])
    controls.orientation = .horizontal

    message.textColor = .systemRed
    message.isHidden = true

    let stack = NSStackView(views: [heading, explanation, scroll, controls, message])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    for view in [explanation, scroll, controls] {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    return stack
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    entries.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
    -> NSView?
  {
    let entry = entries[row]
    guard PreApprovedApplications.isReadable(entry) else {
      let label = NSTextField(labelWithString: "\(entry) (ignored: not an HTTPS origin)")
      label.textColor = .secondaryLabelColor
      return label
    }
    return NSTextField(labelWithString: entry)
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    removeButton.isEnabled = !table.selectedRowIndexes.isEmpty
  }

  @objc private func add() {
    guard let entry = PreApprovedApplications.entry(from: input.stringValue) else {
      show("Enter an HTTPS address, such as app.example.com.")
      return
    }
    guard !entries.contains(entry) else {
      show("\(entry) is already listed.")
      return
    }
    entries.append(entry)
    save()
    input.stringValue = ""
  }

  @objc private func remove() {
    entries = entries.enumerated()
      .filter { !table.selectedRowIndexes.contains($0.offset) }
      .map(\.element)
    save()
  }

  private func save() {
    PreApprovedApplications.store(entries)
    // `reloadData()` keeps an in-range selection, which after a removal would point at
    // different entries, so the selection is cleared along with the button.
    table.reloadData()
    table.deselectAll(nil)
    removeButton.isEnabled = false
    message.isHidden = true
  }

  private func show(_ text: String) {
    message.stringValue = text
    message.isHidden = false
  }
}
