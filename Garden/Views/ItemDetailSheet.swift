import SwiftUI

struct ItemDetailSheet: View {
    let itemId: UUID
    @EnvironmentObject var store: BacklogStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var notes: String = ""
    @FocusState private var titleFocused: Bool

    private var item: GardenItem? {
        store.backlog.activeItems.first { $0.id == itemId }
        ?? store.backlog.completedItems.first { $0.id == itemId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Title
            TextField("Title", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold))
                .focused($titleFocused)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .onSubmit { commitTitle() }

            // Metadata row
            if let item {
                HStack(spacing: 12) {
                    // Priority badge
                    Text("P\(item.priorityBucket + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    // Category pill
                    let catColor = CategoryColor.color(for: item.category)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(catColor)
                            .frame(width: 6, height: 6)
                        Text(item.category)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(catColor.opacity(0.1))
                    .clipShape(Capsule())

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 16)

            // Notes
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Add notes...")
                        .foregroundStyle(.quaternary)
                        .font(.system(size: 13))
                        .padding(.top, 1)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notes)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(.leading, -1)
                    .frame(minHeight: 120)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()
        }
        .frame(width: 420)
        .frame(minHeight: 300)
        .onAppear {
            if let item {
                title = item.title
                notes = item.notes
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                titleFocused = true
            }
        }
        .onDisappear { commitAll() }
        .onChange(of: titleFocused) { _, focused in
            if !focused { commitTitle() }
        }
    }

    private func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let item, trimmed != item.title, !trimmed.isEmpty else { return }
        var updated = item
        updated.title = trimmed
        store.updateItem(updated)
    }

    private func commitAll() {
        guard let item else { return }
        var updated = item
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        var changed = false
        if !trimmedTitle.isEmpty && trimmedTitle != item.title {
            updated.title = trimmedTitle
            changed = true
        }
        if trimmedNotes != item.notes {
            updated.notes = trimmedNotes
            changed = true
        }
        if changed { store.updateItem(updated) }
    }
}
