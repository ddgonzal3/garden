import SwiftUI

struct CategoryDetailView: View {
    let category: String
    @EnvironmentObject var store: BacklogStore

    var items: [GardenItem] {
        if category == "__completed__" {
            return store.backlog.completedItems
        }
        return store.backlog.items(in: category)
    }

    var title: String {
        category == "__completed__" ? "Completed" : category
    }

    var body: some View {
        List {
            ForEach(items) { item in
                ItemRow(item: item)
            }
            .onMove { source, destination in
                if category != "__completed__" {
                    store.moveItem(from: source, to: destination, in: category)
                }
            }
        }
        .listStyle(.plain)
        .onAppear { ScrollViewHelper.configureAllScrollViews() }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    category == "__completed__" ? "Nothing pruned yet" : "Nothing planted",
                    systemImage: category == "__completed__" ? "checkmark.circle" : "leaf",
                    description: Text(category == "__completed__"
                        ? "Completed items will appear here."
                        : "Press ⌘N to plant something.")
                )
            }
        }
    }
}
