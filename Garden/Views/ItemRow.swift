import SwiftUI

struct ItemRow: View {
    let item: GardenItem
    @EnvironmentObject var store: BacklogStore
    @State private var editingTitle: String = ""
    @State private var editingNotes: String = ""
    @State private var isEditingTitle = false
    @State private var isEditingNotes = false
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                if item.isCompleted {
                    var updated = item
                    updated.completedAt = nil
                    store.updateItem(updated)
                } else {
                    store.completeItem(item.id)
                }
            }) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                if isEditingTitle {
                    TextField("Title", text: $editingTitle)
                        .textFieldStyle(.plain)
                        .focused($titleFocused)
                        .onSubmit { commitTitle() }
                        .onChange(of: titleFocused) { _, focused in
                            if !focused { commitTitle() }
                        }
                } else {
                    Text(item.title)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .onTapGesture { startEditingTitle() }
                }

                if isEditingNotes {
                    TextField("Notes", text: $editingNotes)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .focused($notesFocused)
                        .onSubmit { commitNotes() }
                        .onChange(of: notesFocused) { _, focused in
                            if !focused { commitNotes() }
                        }
                } else if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .onTapGesture { startEditingNotes() }
                } else {
                    Text("Add notes")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                        .onTapGesture { startEditingNotes() }
                }
            }

            Spacer()

            Text(item.category)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            if !item.isCompleted {
                Button("Complete") { store.completeItem(item.id) }
            }
            Button("Delete", role: .destructive) { store.deleteItem(item.id) }
        }
    }

    private func startEditingTitle() {
        editingTitle = item.title
        isEditingTitle = true
        titleFocused = true
    }

    private func commitTitle() {
        isEditingTitle = false
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.title else { return }
        var updated = item
        updated.title = trimmed
        store.updateItem(updated)
    }

    private func startEditingNotes() {
        editingNotes = item.notes
        isEditingNotes = true
        notesFocused = true
    }

    private func commitNotes() {
        isEditingNotes = false
        let trimmed = editingNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != item.notes else { return }
        var updated = item
        updated.notes = trimmed
        store.updateItem(updated)
    }
}
