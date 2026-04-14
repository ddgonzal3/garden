import SwiftUI

struct EditItemSheet: View {
    @EnvironmentObject var store: BacklogStore
    @Environment(\.dismiss) var dismiss

    let item: GardenItem

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var category: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit")
                .font(.headline)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Notes", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            Picker("Category", selection: $category) {
                ForEach(store.backlog.categories, id: \.self) { cat in
                    Text(cat).tag(cat)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            title = item.title
            notes = item.notes
            category = item.category
        }
    }

    private func save() {
        var updated = item
        updated.title = title
        updated.notes = notes
        updated.category = category
        store.updateItem(updated)
        dismiss()
    }
}
