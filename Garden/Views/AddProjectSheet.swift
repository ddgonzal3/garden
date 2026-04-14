import SwiftUI

struct AddProjectSheet: View {
    @EnvironmentObject var store: BacklogStore
    @Environment(\.dismiss) var dismiss

    @State private var name = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("New Project")
                .font(.headline)

            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { add() }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }

    private func add() {
        guard !name.isEmpty else { return }
        store.addProject(name)
        if let project = store.backlog.projects.first(where: { $0.name == name }) {
            store.switchProject(project.id)
        }
        dismiss()
    }
}
