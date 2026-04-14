import SwiftUI

struct AllItemsView: View {
    @EnvironmentObject var store: BacklogStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(store.backlog.categories, id: \.self) { category in
                    let items = store.backlog.items(in: category)
                    if !items.isEmpty {
                        CategorySection(category: category, items: items)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Garden")
    }
}

struct CategorySection: View {
    let category: String
    let items: [GardenItem]
    @EnvironmentObject var store: BacklogStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category)
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(items) { item in
                ItemRow(item: item)
            }
        }
    }
}
