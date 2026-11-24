import SwiftUI

struct SnippetEditorView: View {
    @State private var snippets: [Snippet] = SnippetStore.shared.snippets
    @State private var selectedGroup: GroupKey = .all
    @State private var selection: UUID?
    @State private var filter: String = ""

    enum GroupKey: Hashable {
        case all
        case disabled
        case named(String)

        var title: String {
            switch self {
            case .all: return "All Snippets"
            case .disabled: return "Disabled"
            case .named(let s): return s
            }
        }
    }

    private var groupCounts: [(GroupKey, Int)] {
        var dict: [String: Int] = [:]
        var disabledCount = 0
        for s in snippets {
            if !s.enabled { disabledCount += 1 }
            dict[s.group, default: 0] += 1
        }
        var out: [(GroupKey, Int)] = [(.all, snippets.count)]
        out.append(contentsOf: dict.keys.sorted().map { (GroupKey.named($0), dict[$0]!) })
        if disabledCount > 0 {
            out.append((.disabled, disabledCount))
        }
        return out
    }

    private var filtered: [Snippet] {
        var base = snippets
        switch selectedGroup {
        case .all: break
        case .disabled:
            base = base.filter { !$0.enabled }
        case .named(let g):
            base = base.filter { $0.group == g }
        }
        if !filter.isEmpty {
            let q = filter.lowercased()
            base = base.filter {
                $0.abbreviation.lowercased().contains(q) ||
                $0.expansion.lowercased().contains(q)
            }
        }
        return base.sorted {
            $0.abbreviation.localizedCaseInsensitiveCompare($1.abbreviation) == .orderedAscending
        }
    }

    var body: some View {
        NavigationSplitView {
            groupSidebar
        } content: {
            snippetList
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 560)
        .onAppear { snippets = SnippetStore.shared.snippets }
    }

    // MARK: - Panes

    private var groupSidebar: some View {
        List(selection: Binding(
            get: { selectedGroup },
            set: { if let v = $0 { selectedGroup = v; selection = nil } }
        )) {
            Section("Library") {
                ForEach(groupCounts, id: \.0) { (key, count) in
                    HStack {
                        groupIcon(key)
                            .frame(width: 18)
                            .foregroundStyle(groupTint(key))
                        Text(key.title)
                        Spacer()
                        Text("\(count)")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .tag(key)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Menu {
                    Button("Import from CSV…") {
                        CSVFileActions.importFromFile(into: SnippetStore.shared)
                        snippets = SnippetStore.shared.snippets
                    }
                    Button("Export to CSV…") {
                        CSVFileActions.exportToFile(from: SnippetStore.shared)
                    }
                } label: {
                    Label("Import / Export", systemImage: "square.and.arrow.up.on.square")
                }
                .menuStyle(.borderlessButton)
                Spacer()
            }
            .padding(10)
            .background(.ultraThinMaterial)
        }
    }

    private var snippetList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter abbreviation or text", text: $filter)
                    .textFieldStyle(.plain)
                if !filter.isEmpty {
                    Button(action: { filter = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                Button(action: addSnippet) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .help("New snippet (⌘N)")
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(10)
            .background(.regularMaterial)

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No snippets match").foregroundStyle(.secondary)
                    if !filter.isEmpty {
                        Button("Clear filter") { filter = "" }
                            .buttonStyle(.link)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(filtered) { s in
                        SnippetRow(snippet: s)
                            .tag(s.id)
                    }
                    .onDelete(perform: deleteAt)
                }
                .listStyle(.inset)
            }
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 500)
    }

    private var detailPane: some View {
        Group {
            if let id = selection, let idx = snippets.firstIndex(where: { $0.id == id }) {
                SnippetDetail(snippet: Binding(
                    get: { snippets[idx] },
                    set: { snippets[idx] = $0; save(id: id) }
                ), onDelete: {
                    SnippetStore.shared.delete(id)
                    snippets = SnippetStore.shared.snippets
                    selection = nil
                })
            } else {
                EmptyDetail()
            }
        }
        .navigationSplitViewColumnWidth(min: 380, ideal: 500)
    }

    // MARK: - Actions

    private func addSnippet() {
        let group: String = {
            if case .named(let g) = selectedGroup { return g }
            return "My Snippets"
        }()
        let s = Snippet(abbreviation: ";new",
                        expansion: "",
                        trigger: .word,
                        group: group)
        SnippetStore.shared.upsert(s)
        snippets = SnippetStore.shared.snippets
        selection = s.id
    }

    private func deleteAt(_ offsets: IndexSet) {
        let visible = filtered
        for i in offsets { SnippetStore.shared.delete(visible[i].id) }
        snippets = SnippetStore.shared.snippets
    }

    private func save(id: UUID) {
        if let s = snippets.first(where: { $0.id == id }) {
            SnippetStore.shared.upsert(s)
        }
    }

    // MARK: - Helpers

    private func groupIcon(_ key: GroupKey) -> Image {
        switch key {
        case .all: return Image(systemName: "tray.full")
        case .disabled: return Image(systemName: "pause.circle")
        case .named(let n):
            let lc = n.lowercased()
            if lc.contains("sig") { return Image(systemName: "signature") }
            if lc.contains("email") || lc.contains("contact") { return Image(systemName: "envelope") }
            if lc.contains("date") || lc.contains("time") { return Image(systemName: "calendar") }
            if lc.contains("html") || lc.contains("css") || lc.contains("code") { return Image(systemName: "chevron.left.forwardslash.chevron.right") }
            if lc.contains("symbol") { return Image(systemName: "character") }
            if lc.contains("autocorrect") { return Image(systemName: "checkmark.seal") }
            if lc.contains("accent") { return Image(systemName: "a.circle") }
            if lc.contains("web") || lc.contains("internet") { return Image(systemName: "globe") }
            return Image(systemName: "folder")
        }
    }

    private func groupTint(_ key: GroupKey) -> Color {
        switch key {
        case .all: return .accentColor
        case .disabled: return .secondary
        case .named(let n):
            let hash = abs(n.hashValue)
            let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .green, .indigo, .brown, .cyan, .mint]
            return palette[hash % palette.count]
        }
    }
}

// MARK: - Row

private struct SnippetRow: View {
    let snippet: Snippet

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(snippet.abbreviation)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .foregroundStyle(snippet.enabled ? Color.primary : Color.secondary)
                if snippet.trigger == .immediate {
                    Text("immediate")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Spacer()
                if !snippet.enabled {
                    Image(systemName: "pause.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(previewText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 2)
    }

    private var previewText: String {
        let flat = snippet.expansion
            .replacingOccurrences(of: "\n", with: " ↵ ")
            .trimmingCharacters(in: .whitespaces)
        return flat.isEmpty ? "(empty)" : flat
    }
}

// MARK: - Detail

private struct SnippetDetail: View {
    @Binding var snippet: Snippet
    let onDelete: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snippet.abbreviation.isEmpty ? "New snippet" : snippet.abbreviation)
                            .font(.title2.weight(.semibold))
                            .textSelection(.enabled)
                        Text("\(snippet.group) • \(snippet.trigger.label.lowercased())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $snippet.enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help(snippet.enabled ? "Enabled" : "Disabled")
                }

                Divider()

                // Abbreviation
                LabeledField(title: "Abbreviation",
                             hint: "What you type to trigger this snippet.") {
                    TextField("e.g. ;sig", text: $snippet.abbreviation)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                // Group + Trigger row
                HStack(alignment: .top, spacing: 14) {
                    LabeledField(title: "Group",
                                 hint: "Used for organizing only.") {
                        TextField("Default", text: $snippet.group)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField(title: "Trigger",
                                 hint: "Word-boundary is safer; immediate fires the moment you finish typing.") {
                        Picker("", selection: $snippet.trigger) {
                            ForEach(TriggerMode.allCases) { m in
                                Text(m.label).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                LabeledField(title: "Options", hint: nil) {
                    Toggle("Case sensitive", isOn: $snippet.caseSensitive)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                }

                // Expansion
                LabeledField(title: "Expansion",
                             hint: "Variables: {{date}}, {{time}}, {{longdate}}, {{clipboard}}.") {
                    TextEditor(text: $snippet.expansion)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                        .padding(6)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                        )
                }

                Divider()

                // Footer
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Created \(snippet.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        Text("Updated \(snippet.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive, action: { confirmingDelete = true }) {
                        Label("Delete snippet", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding(24)
        }
        .alert("Delete this snippet?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This can't be undone from inside Quill, but you can restore it from the JSON file if needed.")
        }
    }
}

private struct LabeledField<Content: View>: View {
    let title: String
    let hint: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            content
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct EmptyDetail: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "text.cursor")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Select a snippet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("or press ⌘N to create one.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
