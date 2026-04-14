import Foundation

struct Backlog: Codable {
    var projects: [GardenProject]
    var activeProjectId: UUID?

    init(projects: [GardenProject] = [], activeProjectId: UUID? = nil) {
        if projects.isEmpty {
            let defaultProject = GardenProject(name: "My Project")
            self.projects = [defaultProject]
            self.activeProjectId = defaultProject.id
        } else {
            self.projects = projects
            self.activeProjectId = activeProjectId ?? projects.first?.id
        }
    }

    // MARK: - Active project

    var activeProject: GardenProject? {
        projects.first { $0.id == activeProjectId } ?? projects.first
    }

    mutating func activeProjectIndex() -> Int? {
        if let id = activeProjectId {
            return projects.firstIndex { $0.id == id }
        }
        return projects.indices.first
    }

    // MARK: - Convenience (delegates to active project for views)

    var categories: [String] { activeProject?.categories ?? [] }
    var activeItems: [GardenItem] { activeProject?.activeItems ?? [] }
    var completedItems: [GardenItem] { activeProject?.completedItems ?? [] }
    func items(in category: String) -> [GardenItem] { activeProject?.items(in: category) ?? [] }

    // MARK: - Codable (with legacy migration)

    enum CodingKeys: String, CodingKey {
        case projects, activeProjectId
        case items, categories // legacy keys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let projects = try? container.decode([GardenProject].self, forKey: .projects) {
            self.projects = projects
            self.activeProjectId = try container.decodeIfPresent(UUID.self, forKey: .activeProjectId)
        } else {
            // Legacy format — wrap into a "Flow" project
            let items = try container.decodeIfPresent([GardenItem].self, forKey: .items) ?? []
            let categories = try container.decodeIfPresent([String].self, forKey: .categories) ?? ["Uncategorized"]
            let project = GardenProject(name: "Flow", categories: categories, items: items)
            self.projects = [project]
            self.activeProjectId = project.id
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projects, forKey: .projects)
        try container.encodeIfPresent(activeProjectId, forKey: .activeProjectId)
    }
}
