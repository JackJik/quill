import Cocoa
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let monitor = KeystrokeMonitor()
    private let matcher = Matcher()
    private let replacer = Replacer()
    private var menuBar: MenuBarController!
    private var lastBoundary: Character?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock-less, menu-bar-only.
        NSApp.setActivationPolicy(.accessory)

        matcher.reload(from: SnippetStore.shared)
        SnippetStore.shared.onChange = { [weak self] in
            self?.matcher.reload(from: SnippetStore.shared)
        }

        menuBar = MenuBarController(onQuit: { [weak self] in
            self?.monitor.stop()
            NSApp.terminate(nil)
        }, onToggleEnabled: { [weak self] enabled in
            self?.monitor.suspended = !enabled
        })
        menuBar.install()

        // Global hot key (Control-Option-Command-Q) opens the editor even when
        // the menu-bar icon is hidden (e.g. behind the display notch).
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_Q),
                              modifiers: UInt32(controlKey | optionKey | cmdKey)) { [weak self] in
            self?.menuBar.showEditor()
        }

        monitor.onEvent = { [weak self] event in
            guard let self = self else { return }
            switch event {
            case .character(let ch):
                self.lastBoundary = Matcher.isWordBoundary(ch) ? ch : nil
                if let match = self.matcher.feed(character: ch) {
                    self.fire(match: match)
                }
            case .backspace:
                self.matcher.feedBackspace()
            case .cursorMoved:
                self.matcher.cursorMoved()
            }
        }

        if !monitor.start() {
            // Permission not granted — show a friendly prompt. The system has
            // already opened its own dialog via AXIsProcessTrustedWithOptions.
            let alert = NSAlert()
            alert.messageText = "Accessibility permission required"
            alert.informativeText = """
            Quill needs Accessibility permission to watch for abbreviations \
            and expand them. Grant it in System Settings → Privacy & Security \
            → Accessibility, then quit and re-open Quill.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func fire(match: MatchResult) {
        monitor.suspended = true
        matcher.reset()

        let expansion = VariableResolver.resolve(match.snippet.expansion)
        let boundary = match.hasTrailingBoundary ? lastBoundary : nil

        // Give the host app a beat to process the user's last keystroke before
        // we start sending backspaces — some fields (web inputs especially)
        // lose events otherwise.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self = self else { return }
            self.replacer.replace(
                abbreviationLength: match.abbreviationLength,
                hasTrailingBoundary: match.hasTrailingBoundary,
                boundary: boundary,
                expansion: expansion
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.monitor.suspended = false
            }
        }
    }
}
