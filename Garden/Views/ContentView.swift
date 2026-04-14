import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: BacklogStore
    @EnvironmentObject var agent: AgentService
    @State private var selectedCategory: String? = nil
    @State private var showingAddItem = false
    @State private var showingAddCategory = false
    @State private var showingChat = true

    var body: some View {
        HSplitView {
            NavigationSplitView {
                SidebarView(
                    selectedCategory: $selectedCategory,
                    showingAddCategory: $showingAddCategory
                )
            } detail: {
                Group {
                    if let category = selectedCategory {
                        CategoryDetailView(category: category)
                    } else {
                        AllItemsView()
                    }
                }
                .id(selectedCategory)
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
            AddItemSheet(defaultCategory: selectedCategory)
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategorySheet()
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    private var detailTitle: String {
        guard let cat = selectedCategory else { return "Garden" }
        return cat == "__completed__" ? "Completed" : cat
    }
}
