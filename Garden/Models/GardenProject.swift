import Foundation

struct GardenProject: Codable, Identifiable {
    var id: UUID
    var name: String
    var categories: [String]
    var items: [GardenItem]
    var priorityBucketCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        categories: [String] = ["Uncategorized"],
        items: [GardenItem] = [],
        priorityBucketCount: Int = 3
    ) {
        self.id = id
        self.name = name
        self.categories = categories
        self.items = items
        self.priorityBucketCount = priorityBucketCount
    }

    enum CodingKeys: String, CodingKey {
        case id, name, categories, items, priorityBucketCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        categories = try container.decode([String].self, forKey: .categories)
        items = try container.decode([GardenItem].self, forKey: .items)
        priorityBucketCount = try container.decodeIfPresent(Int.self, forKey: .priorityBucketCount) ?? 3
    }

    var activeItems: [GardenItem] {
        items.filter { !$0.isCompleted }.sorted {
            if $0.priorityBucket != $1.priorityBucket {
                return $0.priorityBucket < $1.priorityBucket
            }
            return $0.priority < $1.priority
        }
    }

    var completedItems: [GardenItem] {
        items.filter { $0.isCompleted }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    func items(in category: String) -> [GardenItem] {
        activeItems.filter { $0.category == category }
    }

    func items(inBucket bucket: Int) -> [GardenItem] {
        activeItems.filter { $0.priorityBucket == bucket }
    }
}
