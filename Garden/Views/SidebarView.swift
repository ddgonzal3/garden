import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: BacklogStore
    @Binding var selectedCategory: String?
    @Binding var showingAddCategory: Bool
    @Binding var showingAddProject: Bool

    private var projectBinding: Binding<UUID> {
        Binding(
            get: { store.backlog.activeProjectId ?? store.backlog.projects.first?.id ?? UUID() },
            set: { store.switchProject($0) }
        )
    }

    var body: some View {
        List(selection: $selectedCategory) {
            Section {
                HStack(spacing: 6) {
                    Picker("Project", selection: projectBinding) {
                        ForEach(store.backlog.projects) { project in
                            Text(project.name).tag(project.id)
                        }
                    }
                    .labelsHidden()

                    Button(action: { showingAddProject = true }) {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("New project")
                }
            }

            Section {
                NavigationLink(value: nil as String?) {
                    Label {
                        HStack {
                            Text("All")
                            Spacer()
                            Text("\(store.backlog.activeItems.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "leaf")
                    }
                }
            }

            Section("Categories") {
                ForEach(store.backlog.categories, id: \.self) { category in
                    NavigationLink(value: category) {
                        Label {
                            HStack {
                                Text(category)
                                Spacer()
                                Text("\(store.backlog.items(in: category).count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "folder")
                        }
                    }
                    .contextMenu {
                        if category != "Uncategorized" {
                            Button("Delete Category", role: .destructive) {
                                store.deleteCategory(category)
                            }
                        }
                    }
                }
            }

            Section {
                NavigationLink(value: "__completed__") {
                    Label {
                        HStack {
                            Text("Completed")
                            Spacer()
                            Text("\(store.backlog.completedItems.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button(action: { showingAddCategory = true }) {
                Label("Add Category", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
    }
}
