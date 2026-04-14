import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: BacklogStore
    @State private var selectedCategory: String? = nil
    @State private var showingAddItem = false
    @State private var showingAddCategory = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedCategory: $selectedCategory,
                showingAddCategory: $showingAddCategory
            )
        } detail: {
            if let category = selectedCategory {
                CategoryDetailView(category: category)
            } else {
                AllItemsView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddItem = true }) {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemSheet(defaultCategory: selectedCategory)
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategorySheet()
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
