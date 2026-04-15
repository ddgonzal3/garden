import SwiftUI

enum SidebarSelection: Hashable {
    case all
    case priorityBoard
    case category(String)
    case completed
}

struct SidebarView: View {
    @EnvironmentObject var store: BacklogStore
    @Binding var selectedCategory: SidebarSelection?
    @Binding var showingAddCategory: Bool
    @Binding var showingAddProject: Bool
    @State private var showingProjectPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Project switcher header
            HStack {
                Button {
                    showingProjectPicker.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text(store.backlog.activeProject?.name ?? "Project")
                            .font(.subheadline)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingProjectPicker, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.backlog.projects) { project in
                            Button {
                                store.switchProject(project.id)
                                showingProjectPicker = false
                            } label: {
                                HStack {
                                    Text(project.name)
                                        .font(.subheadline)
                                    Spacer()
                                    if project.id == store.backlog.activeProjectId {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(minWidth: 140)
                }

                Spacer()

                Button(action: { showingAddProject = true }) {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New project")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .padding(.horizontal, 12)

            // Sidebar list
            List(selection: $selectedCategory) {
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

            Section {
                Label {
                    HStack {
                        Text("Priority Board")
                        Spacer()
                        Text("\(store.backlog.activeItems.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                }
                .tag(SidebarSelection.priorityBoard)
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
        .scrollIndicators(.never)
        .safeAreaInset(edge: .bottom) {
            Button(action: { showingAddCategory = true }) {
                Label("Add Category", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        } // end VStack
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
    }
}
