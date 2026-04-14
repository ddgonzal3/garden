import SwiftUI

enum SidebarSelection: Hashable {
    case all
    case category(String)
    case completed
}

struct SidebarView: View {
    @EnvironmentObject var store: BacklogStore
    @Binding var selectedCategory: SidebarSelection?
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
                .tag(SidebarSelection.all)
                .accessibilityIdentifier("sidebar-all")
            }

            Section("Categories") {
                ForEach(store.backlog.categories, id: \.self) { category in
                    Label {
                        HStack {
                            Text(category)
                            Spacer()
                            Button(action: {
                                let item = GardenItem(title: "", category: category)
                                store.addItemToTop(item)
                                selectedCategory = .category(category)
                            }) {
                                Image(systemName: "plus")
                                    .font(.caption2)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.tertiary)
                            Text("\(store.backlog.items(in: category).count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "folder")
                    }
                    .tag(SidebarSelection.category(category))
                    .accessibilityIdentifier("sidebar-\(category)")
                    .contextMenu {
                        Button("Add Item") {
                            let item = GardenItem(title: "", category: category)
                            store.addItemToTop(item)
                            selectedCategory = .category(category)
                        }
                        if category != "Uncategorized" {
                            Button("Delete Category", role: .destructive) {
                                store.deleteCategory(category)
                            }
                        }
                    }
                }
            }

            Section {
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
                .tag(SidebarSelection.completed)
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
