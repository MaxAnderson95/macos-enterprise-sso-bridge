import AppKit

/// The menu bar both windows run under. AppKit routes Command-X, C, V, A, and Z to a
/// text field or web view only through menu items carrying those key equivalents, so
/// without an Edit menu nothing can be pasted into the editor's field or into Entra's
/// sign-in page.
///
/// Quit is offered only for a user launch. A Handoff ends through Cancel or the close
/// button, which answer `declined`; a menu Quit would end the process without that
/// answer.
@MainActor
func installMainMenu(offeringQuit: Bool) {
  let appMenu = NSMenu()
  if offeringQuit {
    appMenu.addItem(
      withTitle: "Quit Enterprise SSO Bridge",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
  }

  let editMenu = NSMenu(title: "Edit")
  editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
  editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
  editMenu.addItem(.separator())
  editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
  editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
  editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
  editMenu.addItem(
    withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

  let mainMenu = NSMenu()
  for menu in [appMenu, editMenu] {
    let item = NSMenuItem()
    item.submenu = menu
    mainMenu.addItem(item)
  }
  NSApplication.shared.mainMenu = mainMenu
}
