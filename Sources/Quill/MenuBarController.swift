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
            // SF Symbol as a template image — matches the system menu-bar look.
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let img = NSImage(systemSymbolName: "text.insert", accessibilityDescription: "Quill") {
                let scaled = img.withSymbolConfiguration(cfg) ?? img
                scaled.isTemplate = true
                button.image = scaled
            } else {
                button.title = "q"
            }
            button.toolTip = "Quill — local text expander"
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let count = SnippetStore.shared.snippets.count
        let groups = SnippetStore.shared.groups().count
        let header = NSMenuItem(title: "\(count) snippet\(count == 1 ? "" : "s") in \(groups) group\(groups == 1 ? "" : "s")",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: enabled ? "Pause expansion" : "Resume expansion",
                                action: #selector(togglePaused), keyEquivalent: "")
        toggle.target = self
        toggle.image = NSImage(systemSymbolName: enabled ? "pause.fill" : "play.fill",
                               accessibilityDescription: nil)
        menu.addItem(toggle)

        let edit = NSMenuItem(title: "Edit snippets…",
                              action: #selector(openEditor), keyEquivalent: ",")
        edit.target = self
        edit.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
        menu.addItem(edit)

        let reveal = NSMenuItem(title: "Reveal snippets file in Finder",
                                action: #selector(revealStorage), keyEquivalent: "")
        reveal.target = self
        reveal.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(reveal)

        menu.addItem(.separator())

        let importItem = NSMenuItem(title: "Import snippets from CSV…",
                                    action: #selector(importCSV), keyEquivalent: "")
        importItem.target = self
        importItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        menu.addItem(importItem)

        let exportItem = NSMenuItem(title: "Export snippets to CSV…",
                                    action: #selector(exportCSV), keyEquivalent: "")
        exportItem.target = self
        exportItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        menu.addItem(exportItem)

        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(title: "Launch Quill at login",
                                       action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(launchAtLogin)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Quill", action: #selector(about), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

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
        win.setContentSize(NSSize(width: 1000, height: 620))
        win.title = "Quill"
        win.subtitle = "Local-only snippets"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = false
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("QuillEditorWindow")
        editorWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    @objc private func revealStorage() {
        NSWorkspace.shared.activateFileViewerSelecting([SnippetStore.shared.storageURL])
    }

    @MainActor
    @objc private func importCSV() {
        NSApp.activate(ignoringOtherApps: true)
        CSVFileActions.importFromFile(into: SnippetStore.shared)
    }

    @MainActor
    @objc private func exportCSV() {
        NSApp.activate(ignoringOtherApps: true)
        CSVFileActions.exportToFile(from: SnippetStore.shared)
    }

    @objc private func toggleLaunchAtLogin() {
        let desired = !LoginItem.isEnabled
        if !LoginItem.set(desired) {
            let alert = NSAlert()
            alert.messageText = "Couldn't update Login Items"
            alert.informativeText = "macOS refused the change. You can toggle Quill manually in System Settings → General → Login Items."
            alert.alertStyle = .warning
            alert.runModal()
        }
        rebuildMenu()
    }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Quill"
        alert.informativeText = """
        Local-only text expander, built as a replacement for TextExpander \
        after their forced cloud migration.

        • No network, no account, no telemetry.
        • Snippets live in ~/Library/Application Support/Quill/snippets.json.
        • Source: ~/quill
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        onQuit()
    }
}
