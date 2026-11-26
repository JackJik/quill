import Foundation

enum TriggerMode: String, Codable, CaseIterable, Identifiable {
    case word       // expand when a word-boundary char follows the abbreviation
    case immediate  // expand the moment the abbreviation is typed
    var id: String { rawValue }
    var label: String { self == .word ? "On word boundary" : "Immediately" }
}

struct Snippet: Codable, Identifiable, Hashable {
    var id: UUID
    var abbreviation: String
    var expansion: String
    var trigger: TriggerMode
    var caseSensitive: Bool
    var group: String
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         abbreviation: String,
         expansion: String,
         trigger: TriggerMode = .word,
         caseSensitive: Bool = false,
         group: String = "Default",
         enabled: Bool = true,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.abbreviation = abbreviation
        self.expansion = expansion
        self.trigger = trigger
        self.caseSensitive = caseSensitive
        self.group = group
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Local-only snippet store. Persists to ~/Library/Application Support/Quill/snippets.json.
/// No network, no cloud, no telemetry.
final class SnippetStore {
    static let shared = SnippetStore()

    private(set) var snippets: [Snippet] = []
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.tglabs.quill.store")

    var onChange: (() -> Void)?

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Quill", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("snippets.json")
        load()
        if snippets.isEmpty { seedDefaults() }
    }

    func load() {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([Snippet].self, from: data) {
                self.snippets = decoded
            }
        }
    }

    func save() {
        queue.sync {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snippets) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
        onChange?()
    }

    func upsert(_ snippet: Snippet) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            var s = snippet
            s.updatedAt = Date()
            snippets[idx] = s
        } else {
            snippets.append(snippet)
        }
        save()
    }

    func delete(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    func groups() -> [String] {
        Array(Set(snippets.map { $0.group })).sorted()
    }

    var storageURL: URL { fileURL }

    private func seedDefaults() {
        snippets = [
            Snippet(abbreviation: ";sig",
                    expansion: "Jack Matthews\n50mm LLC / TG Labs\n",
                    trigger: .word, group: "Signatures"),
            Snippet(abbreviation: ";ddate",
                    expansion: "{{date}}",
                    trigger: .immediate, group: "Dates"),
            Snippet(abbreviation: ";ttime",
                    expansion: "{{time}}",
                    trigger: .immediate, group: "Dates"),
            Snippet(abbreviation: ";email",
                    expansion: "info@tglabs.com",
                    trigger: .word, group: "Contact")
        ]
        save()
    }
}
