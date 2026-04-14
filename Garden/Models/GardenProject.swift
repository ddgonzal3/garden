import Foundation

struct GardenProject: Codable, Identifiable {
    var id: UUID
    var name: String
    var categories: [String]
    var items: [GardenItem]

    init(
        id: UUID = UUID(),
        name: String,
        categories: [String] = ["Uncategorized"],
        items: [GardenItem] = []
    ) {
        self.id = id
        self.name = name
        self.categories = categories
        self.items = items
    }

    var activeItems: [GardenItem] {
        items.filter { !$0.isCompleted }.sorted { $0.priority < $1.priority }
    }

    var completedItems: [GardenItem] {
        items.filter { $0.isCompleted }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    func items(in category: String) -> [GardenItem] {
        activeItems.filter { $0.category == category }
    }
}
