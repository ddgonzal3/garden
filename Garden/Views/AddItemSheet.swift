import SwiftUI

struct AddItemSheet: View {
    @EnvironmentObject var store: BacklogStore
    @Environment(\.dismiss) var dismiss

    var defaultCategory: String?

    @State private var title = ""
    @State private var notes = ""
    @State private var category = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Plant something")
                .font(.headline)

            TextField("What needs doing?", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { add() }

            TextField("Notes (optional)", text: $notes, axis: .vertical)
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
                Button("Plant") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            category = defaultCategory ?? store.backlog.categories.first ?? "Uncategorized"
        }
    }

    private func add() {
        guard !title.isEmpty else { return }
        let item = GardenItem(title: title, notes: notes, category: category)
        store.addItem(item)
        dismiss()
    }
}
