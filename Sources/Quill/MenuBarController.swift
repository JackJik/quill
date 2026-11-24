import Cocoa
import SwiftUI

final class MenuBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var editorWindow: NSWindow?
    private let onQuit: () -> Void
    private let onToggleEnabled: (Bool) -> Void
    private var enabled = true

    init(onQuit: @escaping () -> Void, onToggleEnabled: @escaping (Bool) -> Void) {
        self.onQuit = onQuit
        self.onToggleEnabled = onToggleEnabled
    }

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Lowercase q, so it looks like nothing branded — just a glyph.
            button.title = "q"
            button.font = NSFont.menuBarFont(ofSize: 0)
            button.toolTip = "Quill — local text expander"
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let count = SnippetStore.shared.snippets.count
        let header = NSMenuItem(title: "Quill — \(count) snippet\(count == 1 ? "" : "s")",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: enabled ? "Pause expansion" : "Resume expansion",
                                action: #selector(togglePaused), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let edit = NSMenuItem(title: "Edit snippets…",
                              action: #selector(openEditor), keyEquivalent: ",")
        edit.target = self
        menu.addItem(edit)

        let reveal = NSMenuItem(title: "Reveal snippets file in Finder",
                                action: #selector(revealStorage), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Quill",
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    @objc private func togglePaused() {
        enabled.toggle()
        onToggleEnabled(enabled)
        rebuildMenu()
    }

    @objc private func openEditor() {
        if let win = editorWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SnippetEditorView()
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.setContentSize(NSSize(width: 820, height: 520))
        win.title = "Quill — Snippets"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.isReleasedWhenClosed = false
        win.center()
        editorWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    @objc private func revealStorage() {
        NSWorkspace.shared.activateFileViewerSelecting([SnippetStore.shared.storageURL])
    }

    @objc private func quit() {
        onQuit()
    }
}
