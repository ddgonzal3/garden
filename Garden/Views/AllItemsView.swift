import SwiftUI

struct AllItemsView: View {
    @EnvironmentObject var store: BacklogStore

    var body: some View {
        let _ = debugLog("[AllItemsView] body — categories: \(store.backlog.categories.count), activeItems: \(store.backlog.activeItems.count)")
        List {
            ForEach(store.backlog.categories, id: \.self) { category in
                let items = store.backlog.items(in: category)
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            ItemRow(item: item)
                        }
                    } header: {
                        HStack {
                            Text(category)
                            Spacer()
                            Button(action: {
                                let newItem = GardenItem(title: "", category: category)
                                store.addItemToTop(newItem)
                            }) {
                                Image(systemName: "plus")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}
