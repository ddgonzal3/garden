import Foundation

struct GardenItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var category: String
    var priority: Int
    var createdAt: Date
    var completedAt: Date?

    var isCompleted: Bool { completedAt != nil }

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        category: String = "Uncategorized",
        priority: Int = 0,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.category = category
        self.priority = priority
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}
