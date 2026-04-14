import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: BacklogStore
    @EnvironmentObject var agent: AgentService
    @State private var selectedCategory: SidebarSelection? = .all
    @State private var showingAddItem = false
    @State private var showingAddCategory = false
    @State private var showingAddProject = false
    @State private var showingChat = true

    var body: some View {
        HSplitView {
            NavigationSplitView {
                SidebarView(
                    selectedCategory: $selectedCategory,
                    showingAddCategory: $showingAddCategory,
                    showingAddProject: $showingAddProject
                )
            } detail: {
                detailContent(for: selectedCategory ?? .all)
            }
            .navigationTitle(detailTitle)

            if showingChat {
                AgentChatView()
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 500)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button(action: { showingAddItem = true }) {
                        Image(systemName: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    Button(action: { withAnimation { showingChat.toggle() } }) {
                        Image(systemName: showingChat ? "bubble.left.fill" : "bubble.left")
                    }
                    .keyboardShortcut("j", modifiers: .command)
                    .help("Toggle chat (Cmd+J)")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemSheet(defaultCategory: selectedCategory.flatMap {
                if case .category(let cat) = $0 { return cat }
                return nil
            })
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategorySheet()
        }
        .sheet(isPresented: $showingAddProject) {
            AddProjectSheet()
        }
        .onChange(of: store.backlog.activeProjectId) {
            selectedCategory = .all
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    @ViewBuilder
    private func detailContent(for selection: SidebarSelection) -> some View {
        switch selection {
        case .all:
            AllItemsView()
        case .category(let category):
            CategoryDetailView(category: category)
        case .completed:
            CategoryDetailView(category: "__completed__")
        }
    }

    private var detailTitle: String {
        switch selectedCategory {
        case .category(let cat): return cat
        case .completed: return "Completed"
        default: return store.backlog.activeProject?.name ?? "Garden"
        }
    }
}
