import SwiftUI

struct ItemRow: View {
    let item: GardenItem
    @EnvironmentObject var store: BacklogStore
    @State private var isEditing = false

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
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
        .onTapGesture(count: 2) { isEditing = true }
        .contextMenu {
            Button("Edit…") { isEditing = true }
            Divider()
            if !item.isCompleted {
                Button("Complete") { store.completeItem(item.id) }
            }
            Button("Delete", role: .destructive) { store.deleteItem(item.id) }
        }
        .sheet(isPresented: $isEditing) {
            EditItemSheet(item: item)
        }
    }
}
