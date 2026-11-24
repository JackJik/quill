import Foundation
import AppKit

/// RFC 4180-compliant CSV import/export tailored to Quill snippets.
///
/// Import rules:
///   - First row is the header row (case-insensitive).
///   - Required columns: "abbreviation" (aliases: "abbr", "shortcut", "key", "trigger")
///                       "expansion"    (aliases: "content", "value", "snippet", "replacement")
///   - Optional: "group" (aliases: "folder", "category")
///                "trigger_mode" (aliases: "mode", "when") — values "word"/"immediate"/"any"
///                "case_sensitive" (aliases: "case")
///                "enabled"
///   - Rows with blank abbreviation or expansion are skipped.
///   - Existing snippets with the same (abbreviation, group) are updated in place;
///     others are appended.
enum CSVImporter {

    struct ImportResult {
        var added: Int
        var updated: Int
        var skipped: Int
        var errors: [String]
    }

    static func importCSV(data: Data, into store: SnippetStore) -> ImportResult {
        guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16)
                    ?? String(data: data, encoding: .isoLatin1) else {
            return ImportResult(added: 0, updated: 0, skipped: 0,
                                errors: ["File is not readable as UTF-8 / UTF-16 / Latin-1."])
        }
        let rows = parseCSV(text)
        guard rows.count >= 2 else {
            return ImportResult(added: 0, updated: 0, skipped: 0,
                                errors: ["CSV has no data rows (need header + at least one row)."])
        }
        let header = rows[0].map { normalizeHeader($0) }

        let colAbbr = header.firstIndex(where: {
            ["abbreviation", "abbr", "shortcut", "key", "trigger"].contains($0)
        })
        let colExp = header.firstIndex(where: {
            ["expansion", "content", "value", "snippet", "replacement"].contains($0)
        })
        let colGroup = header.firstIndex(where: {
            ["group", "folder", "category"].contains($0)
        })
        let colMode = header.firstIndex(where: {
            ["trigger_mode", "mode", "when"].contains($0)
        })
        let colCase = header.firstIndex(where: {
            ["case_sensitive", "casesensitive", "case"].contains($0)
        })
        let colEnabled = header.firstIndex(where: {
            ["enabled", "active"].contains($0)
        })

        guard let abbrIdx = colAbbr, let expIdx = colExp else {
            return ImportResult(added: 0, updated: 0, skipped: 0,
                                errors: ["CSV header must include an abbreviation column and an expansion column. Got: \(header.joined(separator: ", "))"])
        }

        var added = 0, updated = 0, skipped = 0
        var errors: [String] = []

        for (i, row) in rows.enumerated().dropFirst() {
            guard abbrIdx < row.count, expIdx < row.count else {
                skipped += 1
                errors.append("Row \(i + 1): too few columns.")
                continue
            }
            let abbr = row[abbrIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let exp = row[expIdx]
            if abbr.isEmpty || exp.isEmpty {
                skipped += 1
                continue
            }

            let group = (colGroup.flatMap { $0 < row.count ? row[$0] : nil } ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let modeStr = (colMode.flatMap { $0 < row.count ? row[$0] : nil } ?? "")
                .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let mode: TriggerMode = (modeStr == "immediate" || modeStr == "any") ? .immediate : .word
            let caseSensitive = parseBool(colCase.flatMap { $0 < row.count ? row[$0] : nil } ?? "")
            let enabled = parseBool(colEnabled.flatMap { $0 < row.count ? row[$0] : nil } ?? "", default: true)
            let resolvedGroup = group.isEmpty ? "Imported" : group

            if let existing = store.snippets.first(where: {
                $0.abbreviation.caseInsensitiveCompare(abbr) == .orderedSame &&
                $0.group.caseInsensitiveCompare(resolvedGroup) == .orderedSame
            }) {
                var s = existing
                s.expansion = exp
                s.trigger = mode
                s.caseSensitive = caseSensitive
                s.enabled = enabled
                s.updatedAt = Date()
                store.upsert(s)
                updated += 1
            } else {
                let s = Snippet(abbreviation: abbr,
                                expansion: exp,
                                trigger: mode,
                                caseSensitive: caseSensitive,
                                group: resolvedGroup,
                                enabled: enabled)
                store.upsert(s)
                added += 1
            }
        }

        return ImportResult(added: added, updated: updated, skipped: skipped, errors: errors)
    }

    static func exportCSV(from store: SnippetStore) -> Data {
        var out = "abbreviation,expansion,group,trigger_mode,case_sensitive,enabled\n"
        for s in store.snippets.sorted(by: {
            $0.group == $1.group
                ? $0.abbreviation.localizedCompare($1.abbreviation) == .orderedAscending
                : $0.group.localizedCompare($1.group) == .orderedAscending
        }) {
            let fields = [s.abbreviation,
                          s.expansion,
                          s.group,
                          s.trigger.rawValue,
                          s.caseSensitive ? "true" : "false",
                          s.enabled ? "true" : "false"]
            out.append(fields.map(quote).joined(separator: ","))
            out.append("\n")
        }
        return out.data(using: .utf8) ?? Data()
    }

    // MARK: - Parsing

    /// Minimal RFC 4180 parser. Handles quoted fields, escaped quotes (""),
    /// embedded newlines inside quotes, and CRLF or LF line endings.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let ch = text[i]
            if inQuotes {
                if ch == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = text.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                        i = text.index(after: i)
                        continue
                    }
                } else {
                    field.append(ch)
                    i = text.index(after: i)
                    continue
                }
            } else {
                if ch == "\"" {
                    inQuotes = true
                    i = text.index(after: i)
                    continue
                } else if ch == "," {
                    row.append(field)
                    field = ""
                    i = text.index(after: i)
                    continue
                } else if ch == "\r" {
                    i = text.index(after: i)
                    continue
                } else if ch == "\n" {
                    row.append(field)
                    rows.append(row)
                    field = ""
                    row = []
                    i = text.index(after: i)
                    continue
                } else {
                    field.append(ch)
                    i = text.index(after: i)
                    continue
                }
            }
        }
        // Flush trailing field/row
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func normalizeHeader(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    private static func parseBool(_ s: String, default d: Bool = false) -> Bool {
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if v.isEmpty { return d }
        return ["1", "true", "yes", "y", "t"].contains(v)
    }

    private static func quote(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return s
    }
}

// MARK: - File-picker helpers

enum CSVFileActions {

    @MainActor
    static func importFromFile(into store: SnippetStore) {
        let panel = NSOpenPanel()
        panel.title = "Import snippets from CSV"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "First row must be a header. Required columns: abbreviation, expansion. Optional: group, trigger_mode, case_sensitive, enabled."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let r = CSVImporter.importCSV(data: data, into: store)
            let alert = NSAlert()
            alert.messageText = "Import complete"
            var body = "Added: \(r.added)\nUpdated: \(r.updated)\nSkipped: \(r.skipped)"
            if !r.errors.isEmpty {
                body += "\n\n" + r.errors.prefix(10).joined(separator: "\n")
                if r.errors.count > 10 { body += "\n…(\(r.errors.count - 10) more)" }
            }
            alert.informativeText = body
            alert.alertStyle = r.errors.isEmpty ? .informational : .warning
            alert.runModal()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @MainActor
    static func exportToFile(from store: SnippetStore) {
        let panel = NSSavePanel()
        panel.title = "Export snippets to CSV"
        panel.nameFieldStringValue = "quill-snippets.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = CSVImporter.exportCSV(from: store)
            try data.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
