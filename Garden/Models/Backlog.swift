import Foundation

struct Backlog: Codable {
    var items: [GardenItem]
    var categories: [String]

    init(items: [GardenItem] = [], categories: [String] = ["Uncategorized"]) {
        self.items = items
        self.categories = categories
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
