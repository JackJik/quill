import SwiftUI

struct SnippetEditorView: View {
    @State private var snippets: [Snippet] = SnippetStore.shared.snippets
    @State private var selection: UUID?
    @State private var filter: String = ""

    var filtered: [Snippet] {
        let base = snippets.sorted { $0.group == $1.group
            ? $0.abbreviation.localizedCompare($1.abbreviation) == .orderedAscending
            : $0.group.localizedCompare($1.group) == .orderedAscending }
        if filter.isEmpty { return base }
        let q = filter.lowercased()
        return base.filter {
            $0.abbreviation.lowercased().contains(q) ||
            $0.expansion.lowercased().contains(q) ||
            $0.group.lowercased().contains(q)
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Filter", text: $filter)
                        .textFieldStyle(.roundedBorder)
                    Button(action: addSnippet) { Image(systemName: "plus") }
                        .help("New snippet")
                }
                .padding(8)

                List(selection: $selection) {
                    ForEach(filtered) { s in
                        HStack {
                            Text(s.abbreviation).font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(s.group).foregroundColor(.secondary).font(.caption)
                        }
                        .tag(s.id)
                        .opacity(s.enabled ? 1.0 : 0.4)
                    }
                    .onDelete(perform: deleteAt)
                }
                .listStyle(.sidebar)
                .frame(minWidth: 260)
            }

            Group {
                if let id = selection, let idx = snippets.firstIndex(where: { $0.id == id }) {
                    SnippetDetail(snippet: Binding(
                        get: { snippets[idx] },
                        set: { snippets[idx] = $0; save() }
                    ), onDelete: {
                        SnippetStore.shared.delete(id)
                        snippets = SnippetStore.shared.snippets
                        selection = nil
                    })
                } else {
                    VStack {
                        Spacer()
                        Text("Select a snippet, or press + to create one.")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 440)
        }
        .frame(minWidth: 760, minHeight: 440)
        .onAppear { snippets = SnippetStore.shared.snippets }
    }

    private func addSnippet() {
        let s = Snippet(abbreviation: ";new",
                        expansion: "",
                        trigger: .word,
                        group: "Default")
        SnippetStore.shared.upsert(s)
        snippets = SnippetStore.shared.snippets
        selection = s.id
    }

    private func deleteAt(_ offsets: IndexSet) {
        let visible = filtered
        for i in offsets {
            SnippetStore.shared.delete(visible[i].id)
        }
        snippets = SnippetStore.shared.snippets
    }

    private func save() {
        if let id = selection, let s = snippets.first(where: { $0.id == id }) {
            SnippetStore.shared.upsert(s)
        }
    }
}

private struct SnippetDetail: View {
    @Binding var snippet: Snippet
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Enabled", isOn: $snippet.enabled)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }

            Group {
                Text("Abbreviation").font(.caption).foregroundColor(.secondary)
                TextField("e.g. ;sig", text: $snippet.abbreviation)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                VStack(alignment: .leading) {
                    Text("Group").font(.caption).foregroundColor(.secondary)
                    TextField("Default", text: $snippet.group)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading) {
                    Text("Trigger").font(.caption).foregroundColor(.secondary)
                    Picker("", selection: $snippet.trigger) {
                        ForEach(TriggerMode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .labelsHidden()
                }
                VStack(alignment: .leading) {
                    Text("Case").font(.caption).foregroundColor(.secondary)
                    Toggle("Case sensitive", isOn: $snippet.caseSensitive)
                        .toggleStyle(.checkbox)
                }
            }

            Text("Expansion").font(.caption).foregroundColor(.secondary)
            TextEditor(text: $snippet.expansion)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            Text("Variables: {{date}}, {{time}}, {{longdate}}, {{clipboard}}")
                .font(.caption2).foregroundColor(.secondary)

            Spacer()
        }
        .padding(16)
    }
}
