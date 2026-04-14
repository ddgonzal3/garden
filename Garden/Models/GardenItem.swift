import Foundation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let gardenItem = UTType(exportedAs: "com.danny.garden.item")
}

struct GardenItem: Identifiable, Equatable, Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .gardenItem)
    }
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

// Custom Codable to handle null dates with iso8601 strategy
extension GardenItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, notes, category, priority, createdAt, completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        category = try container.decode(String.self, forKey: .category)
        priority = try container.decode(Int.self, forKey: .priority)

        let createdStr = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter().date(from: createdStr) ?? Date()

        if let completedStr = try container.decodeIfPresent(String.self, forKey: .completedAt) {
            completedAt = ISO8601DateFormatter().date(from: completedStr)
        } else {
            completedAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(category, forKey: .category)
        try container.encode(priority, forKey: .priority)
        try container.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
        if let completedAt {
            try container.encode(ISO8601DateFormatter().string(from: completedAt), forKey: .completedAt)
        } else {
            try container.encodeNil(forKey: .completedAt)
        }
    }
}
