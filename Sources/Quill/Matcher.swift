import Foundation

struct MatchResult {
    let snippet: Snippet
    let abbreviationLength: Int
    let hasTrailingBoundary: Bool
}

/// Rolling-buffer matcher. Maintains a small suffix of recently typed characters
/// and looks for snippet abbreviations ending at the cursor. O(snippets * len) per
/// keystroke — fine for even 10k snippets since we only check the tail.
final class Matcher {
    private var buffer: [Character] = []
    private let maxBuffer = 128
    private var snippetsByAbbrLen: [Int: [Snippet]] = [:]
    private var longestAbbr: Int = 0

    func reload(from store: SnippetStore) {
        snippetsByAbbrLen.removeAll()
        longestAbbr = 0
        for s in store.snippets where s.enabled && !s.abbreviation.isEmpty {
            let len = s.abbreviation.count
            snippetsByAbbrLen[len, default: []].append(s)
            if len > longestAbbr { longestAbbr = len }
        }
    }

    func reset() { buffer.removeAll(keepingCapacity: true) }

    /// Feed a printable character. Returns a MatchResult if the character
    /// completes an abbreviation (word mode: current char is a boundary;
    /// immediate mode: tail equals abbreviation).
    func feed(character ch: Character) -> MatchResult? {
        buffer.append(ch)
        if buffer.count > maxBuffer {
            buffer.removeFirst(buffer.count - maxBuffer)
        }

        let isBoundary = Matcher.isWordBoundary(ch)

        // Immediate mode: last character is part of the abbreviation itself.
        for len in stride(from: min(longestAbbr, buffer.count), through: 1, by: -1) {
            guard let candidates = snippetsByAbbrLen[len] else { continue }
            let start = buffer.count - len
            let tail = String(buffer[start..<buffer.count])
            for s in candidates where s.trigger == .immediate {
                if matches(abbr: s.abbreviation, tail: tail, caseSensitive: s.caseSensitive) {
                    return MatchResult(snippet: s, abbreviationLength: len, hasTrailingBoundary: false)
                }
            }
        }

        // Word mode: the current character is a boundary; the abbreviation sits
        // before it. Look at buffer[..<count-1].
        if isBoundary && buffer.count >= 2 {
            let endExclusive = buffer.count - 1
            for len in stride(from: min(longestAbbr, endExclusive), through: 1, by: -1) {
                guard let candidates = snippetsByAbbrLen[len] else { continue }
                let start = endExclusive - len
                if start < 0 { continue }
                // Ensure the char before the abbreviation is also a boundary
                // (or the abbreviation sits at the very start of the buffer).
                if start > 0 && !Matcher.isWordBoundary(buffer[start - 1]) {
                    // allow abbreviations that start with punctuation (e.g. ";sig")
                    // to match anywhere by not requiring a leading boundary.
                    if !Matcher.isPunctuation(buffer[start]) { continue }
                }
                let tail = String(buffer[start..<endExclusive])
                for s in candidates where s.trigger == .word {
                    if matches(abbr: s.abbreviation, tail: tail, caseSensitive: s.caseSensitive) {
                        return MatchResult(snippet: s, abbreviationLength: len, hasTrailingBoundary: true)
                    }
                }
            }
        }

        return nil
    }

    func feedBackspace() {
        if !buffer.isEmpty { buffer.removeLast() }
    }

    /// Call when the cursor may have moved (arrow keys, mouse click, modifier combos).
    func cursorMoved() { reset() }

    private func matches(abbr: String, tail: String, caseSensitive: Bool) -> Bool {
        if caseSensitive { return abbr == tail }
        return abbr.lowercased() == tail.lowercased()
    }

    static func isWordBoundary(_ ch: Character) -> Bool {
        if ch.isWhitespace || ch.isNewline { return true }
        if let scalar = ch.unicodeScalars.first,
           CharacterSet.punctuationCharacters.contains(scalar) { return true }
        if let scalar = ch.unicodeScalars.first,
           CharacterSet.symbols.contains(scalar) { return true }
        return false
    }

    static func isPunctuation(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        return CharacterSet.punctuationCharacters.contains(scalar)
    }
}
