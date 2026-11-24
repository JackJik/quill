import Cocoa

/// Deletes the typed abbreviation and types the expansion.
/// Uses CGEvent.keyboardSetUnicodeString to inject characters directly, which:
///   - does not touch the system clipboard
///   - works in essentially any text field that accepts typing
///   - preserves the trailing boundary character (space, period, …) that the
///     user typed to trigger the expansion.
final class Replacer {

    private let source = CGEventSource(stateID: .combinedSessionState)

    /// - Parameters:
    ///   - abbreviationLength: number of chars of the abbreviation that are
    ///     currently to the left of the cursor
    ///   - hasTrailingBoundary: if true, a boundary char (e.g. space) is to the
    ///     right of the abbreviation and was just typed — it must be deleted
    ///     before the expansion and re-typed after.
    ///   - expansion: the resolved expansion text (variables already applied)
    ///   - boundary: the boundary character the user typed (only used if hasTrailingBoundary)
    func replace(abbreviationLength: Int,
                 hasTrailingBoundary: Bool,
                 boundary: Character?,
                 expansion: String) {
        let totalDeletes = abbreviationLength + (hasTrailingBoundary ? 1 : 0)
        for _ in 0..<totalDeletes {
            sendBackspace()
        }
        sendText(expansion)
        if hasTrailingBoundary, let b = boundary {
            sendText(String(b))
        }
    }

    private func sendBackspace() {
        let kDelete: CGKeyCode = 0x33
        if let down = CGEvent(keyboardEventSource: source, virtualKey: kDelete, keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: kDelete, keyDown: false) {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    private func sendText(_ text: String) {
        // Chunk into pieces small enough for CGEvent's unicode buffer. It accepts
        // up to ~20 UTF-16 code units per event in practice; keep it well under.
        let utf16 = Array(text.utf16)
        var i = 0
        let chunk = 16
        while i < utf16.count {
            let end = min(i + chunk, utf16.count)
            let slice = Array(utf16[i..<end])
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
               let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                slice.withUnsafeBufferPointer { ptr in
                    down.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: ptr.baseAddress)
                    up.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: ptr.baseAddress)
                }
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            i = end
        }
    }
}

/// Resolves template variables in an expansion. Keep this small and offline.
enum VariableResolver {
    static func resolve(_ template: String) -> String {
        var out = template
        let df = DateFormatter()

        df.dateFormat = "yyyy-MM-dd"
        out = out.replacingOccurrences(of: "{{date}}", with: df.string(from: Date()))

        df.dateFormat = "HH:mm"
        out = out.replacingOccurrences(of: "{{time}}", with: df.string(from: Date()))

        df.dateFormat = "EEEE, MMMM d, yyyy"
        out = out.replacingOccurrences(of: "{{longdate}}", with: df.string(from: Date()))

        // {{clipboard}} pulls the current pasteboard string, without mutating it.
        if out.contains("{{clipboard}}") {
            let clip = NSPasteboard.general.string(forType: .string) ?? ""
            out = out.replacingOccurrences(of: "{{clipboard}}", with: clip)
        }

        return out
    }
}
