import SwiftUI

struct CategoryDetailView: View {
    let category: String
    @EnvironmentObject var store: BacklogStore
    @State private var dropTargetId: UUID?

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
                    .overlay(alignment: .top) {
                        if dropTargetId == item.id {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.accentColor.opacity(0.6))
                                .frame(height: 2)
                                .padding(.horizontal, 4)
                                .transition(.opacity)
                        }
                    }
                    .draggable(item)
                    .dropDestination(for: GardenItem.self) { droppedItems, _ in
                        guard let dropped = droppedItems.first, dropped.id != item.id else { return false }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            store.moveItemBeforeTarget(dropped.id, targetId: item.id)
                        }
                        dropTargetId = nil
                        return true
                    } isTargeted: { targeted in
                        dropTargetId = targeted ? item.id : nil
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
