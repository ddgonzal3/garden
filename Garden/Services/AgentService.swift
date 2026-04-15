import Foundation
import SwiftUI

@MainActor
class AgentService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var apiKey: String = ""

    @AppStorage("claude_model") var model: String = "claude-sonnet-4-6"

    private let backlogStore: BacklogStore

    init(backlogStore: BacklogStore) {
        self.backlogStore = backlogStore
        self.apiKey = KeychainService.load()
    }

    var hasApiKey: Bool { !apiKey.isEmpty }

    func saveApiKey(_ key: String) {
        apiKey = key
        KeychainService.save(key)
    }

    // MARK: - Public

    func send(_ text: String) async {
        messages.append(ChatMessage(role: .user, content: text))
        isLoading = true
        defer { isLoading = false }

        do {
            let reply = try await runAgentLoop(userText: text)
            messages.append(ChatMessage(role: .assistant, content: reply))
        } catch {
            messages.append(ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)"))
        }
    }

    // MARK: - Agent loop

    private func runAgentLoop(userText: String) async throws -> String {
        var apiMessages = buildAPIMessages(newUserText: userText)

        for _ in 0..<10 {
            let response = try await callClaude(messages: apiMessages)

            guard let stopReason = response["stop_reason"] as? String,
                  let contentBlocks = response["content"] as? [[String: Any]] else {
                throw AgentError.invalidResponse
            }

            if stopReason == "end_turn" {
                return extractText(from: contentBlocks)
            }

            if stopReason == "tool_use" {
                apiMessages.append(["role": "assistant", "content": contentBlocks])

                var toolResults: [[String: Any]] = []
                for block in contentBlocks where (block["type"] as? String) == "tool_use" {
                    let result = executeTool(block)
                    toolResults.append(result)
                }

                apiMessages.append(["role": "user", "content": toolResults])
                continue
            }

            return extractText(from: contentBlocks)
        }

        return "I hit my iteration limit. Try a simpler request."
    }

    // MARK: - API call

    private func callClaude(messages: [[String: Any]]) async throws -> [String: Any] {
        guard !apiKey.isEmpty else { throw AgentError.noApiKey }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "tools": toolDefinitions,
            "messages": messages,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        if let http = httpResponse as? HTTPURLResponse, http.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AgentError.apiError(http.statusCode, errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.invalidResponse
        }

        return json
    }

    // MARK: - Tool execution

    private func executeTool(_ block: [String: Any]) -> [String: Any] {
        let toolUseId = block["id"] as? String ?? ""
        let name = block["name"] as? String ?? ""
        let input = block["input"] as? [String: Any] ?? [:]

        let result: String
        switch name {
        case "read_backlog":
            result = readBacklog()
        case "add_item":
            result = addItem(input)
        case "update_item":
            result = updateItem(input)
        case "complete_item":
            result = completeItem(input)
        case "delete_item":
            result = deleteItem(input)
        case "add_category":
            result = addCategory(input)
        case "reorder_items":
            result = reorderItems(input)
        case "reorder_categories":
            result = reorderCategories(input)
        case "add_project":
            result = addProject(input)
        case "delete_project":
            result = deleteProject(input)
        case "rename_project":
            result = renameProject(input)
        case "switch_project":
            result = switchProject(input)
        case "reorder_projects":
            result = reorderProjects(input)
        default:
            result = "Unknown tool: \(name)"
        }

        return [
            "type": "tool_result",
            "tool_use_id": toolUseId,
            "content": result,
        ]
    }

    // MARK: - Project resolution

    /// Returns (projectId, errorMessage). projectId is nil for active project.
    private func resolveProjectId(_ name: String?) -> (UUID?, String?) {
        guard let name = name else { return (nil, nil) }
        guard let project = backlogStore.backlog.projects.first(where: { $0.name == name }) else {
            return (nil, "Error: project '\(name)' not found")
        }
        return (project.id, nil)
    }

    // MARK: - Tool implementations (items)

    private func readBacklog() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(backlogStore.backlog) else { return "Failed to encode backlog" }

        var result = String(data: data, encoding: .utf8) ?? "Failed to encode backlog"
        if let activeName = backlogStore.backlog.activeProject?.name {
            result = "Active project: \(activeName)\n\n\(result)"
        }
        return result
    }

    private func addItem(_ input: [String: Any]) -> String {
        let (projectId, error) = resolveProjectId(input["project"] as? String)
        if let error { return error }

        let title = input["title"] as? String ?? ""
        let notes = input["notes"] as? String ?? ""
        let category = input["category"] as? String ?? "Uncategorized"

        guard !title.isEmpty else { return "Error: title is required" }

        let bucket: Int
        if let p = input["priority"] as? Int {
            bucket = p
        } else if let p = input["priority"] as? String, let n = Int(p) {
            bucket = n
        } else {
            bucket = 0
        }

        let item = GardenItem(title: title, notes: notes, category: category, priorityBucket: bucket)
        backlogStore.addItem(item, inProject: projectId)
        return "Added '\(title)' to \(category) at P\(bucket)"
    }

    private func updateItem(_ input: [String: Any]) -> String {
        guard let idStr = input["id"] as? String, let id = UUID(uuidString: idStr) else {
            return "Error: valid id is required"
        }

        // Find the item across all projects
        var foundItem: GardenItem?
        var sourceProjectId: UUID?
        for project in backlogStore.backlog.projects {
            if let item = project.items.first(where: { $0.id == id }) {
                foundItem = item
                sourceProjectId = project.id
                break
            }
        }

        guard var item = foundItem else {
            return "Error: item not found"
        }

        if let title = input["title"] as? String { item.title = title }
        if let notes = input["notes"] as? String { item.notes = notes }
        if let category = input["category"] as? String { item.category = category }
        if let p = input["priority"] as? Int { item.priorityBucket = p }
        else if let p = input["priority"] as? String, let n = Int(p) { item.priorityBucket = n }

        // If project param is specified, move the item to that project
        if let targetName = input["project"] as? String {
            guard let targetProject = backlogStore.backlog.projects.first(where: { $0.name == targetName }) else {
                return "Error: project '\(targetName)' not found"
            }
            // Apply field updates first, then move if different project
            backlogStore.updateItem(item)
            if let sourceId = sourceProjectId, targetProject.id != sourceId {
                backlogStore.moveItemToProject(id, targetProjectId: targetProject.id)
            }
        } else {
            backlogStore.updateItem(item)
        }

        return "Updated '\(item.title)'"
    }

    private func completeItem(_ input: [String: Any]) -> String {
        guard let idStr = input["id"] as? String, let id = UUID(uuidString: idStr) else {
            return "Error: valid id is required"
        }
        backlogStore.completeItem(id)
        return "Completed item"
    }

    private func deleteItem(_ input: [String: Any]) -> String {
        guard let idStr = input["id"] as? String, let id = UUID(uuidString: idStr) else {
            return "Error: valid id is required"
        }
        backlogStore.deleteItem(id)
        return "Deleted item"
    }

    // MARK: - Tool implementations (categories)

    private func addCategory(_ input: [String: Any]) -> String {
        let (projectId, error) = resolveProjectId(input["project"] as? String)
        if let error { return error }

        guard let name = input["name"] as? String, !name.isEmpty else {
            return "Error: name is required"
        }
        backlogStore.addCategory(name, inProject: projectId)
        return "Added category '\(name)'"
    }

    private func reorderItems(_ input: [String: Any]) -> String {
        guard let category = input["category"] as? String,
              let orderedIds = input["item_ids"] as? [String] else {
            return "Error: category and item_ids are required"
        }

        let (projectId, error) = resolveProjectId(input["project"] as? String)
        if let error { return error }

        let uuids = orderedIds.compactMap { UUID(uuidString: $0) }
        backlogStore.reorderItems(in: category, orderedIds: uuids, inProject: projectId)
        return "Reordered \(uuids.count) items in \(category)"
    }

    private func reorderCategories(_ input: [String: Any]) -> String {
        guard let orderedNames = input["category_names"] as? [String] else {
            return "Error: category_names is required"
        }

        let (projectId, error) = resolveProjectId(input["project"] as? String)
        if let error { return error }

        backlogStore.reorderCategories(orderedNames, inProject: projectId)
        return "Reordered categories to: \(orderedNames.joined(separator: ", "))"
    }

    // MARK: - Tool implementations (projects)

    private func addProject(_ input: [String: Any]) -> String {
        guard let name = input["name"] as? String, !name.isEmpty else {
            return "Error: name is required"
        }
        if backlogStore.backlog.projects.contains(where: { $0.name == name }) {
            return "Error: project '\(name)' already exists"
        }
        backlogStore.addProject(name)
        return "Added project '\(name)'"
    }

    private func deleteProject(_ input: [String: Any]) -> String {
        guard let name = input["name"] as? String, !name.isEmpty else {
            return "Error: name is required"
        }
        guard let project = backlogStore.backlog.projects.first(where: { $0.name == name }) else {
            return "Error: project '\(name)' not found"
        }
        if backlogStore.backlog.projects.count <= 1 {
            return "Error: cannot delete the only project"
        }
        let itemCount = project.items.count
        backlogStore.deleteProject(project.id)
        return "Deleted project '\(name)' (\(itemCount) items removed)"
    }

    private func renameProject(_ input: [String: Any]) -> String {
        guard let oldName = input["old_name"] as? String, !oldName.isEmpty else {
            return "Error: old_name is required"
        }
        guard let newName = input["new_name"] as? String, !newName.isEmpty else {
            return "Error: new_name is required"
        }
        guard let project = backlogStore.backlog.projects.first(where: { $0.name == oldName }) else {
            return "Error: project '\(oldName)' not found"
        }
        if backlogStore.backlog.projects.contains(where: { $0.name == newName }) {
            return "Error: project '\(newName)' already exists"
        }
        backlogStore.renameProject(project.id, to: newName)
        return "Renamed project '\(oldName)' to '\(newName)'"
    }

    private func switchProject(_ input: [String: Any]) -> String {
        guard let name = input["name"] as? String, !name.isEmpty else {
            return "Error: name is required"
        }
        guard let project = backlogStore.backlog.projects.first(where: { $0.name == name }) else {
            return "Error: project '\(name)' not found"
        }
        backlogStore.switchProject(project.id)
        return "Switched to project '\(name)'"
    }

    private func reorderProjects(_ input: [String: Any]) -> String {
        guard let orderedNames = input["project_names"] as? [String] else {
            return "Error: project_names is required"
        }

        let orderedIds = orderedNames.compactMap { name in
            backlogStore.backlog.projects.first(where: { $0.name == name })?.id
        }
        backlogStore.reorderProjects(orderedIds)
        return "Reordered projects to: \(orderedNames.joined(separator: ", "))"
    }

    // MARK: - Helpers

    private func buildAPIMessages(newUserText: String) -> [[String: Any]] {
        var apiMessages: [[String: Any]] = []
        let recent = messages.suffix(20)

        for msg in recent {
            apiMessages.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content,
            ])
        }

        return apiMessages
    }

    private func extractText(from blocks: [[String: Any]]) -> String {
        blocks
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
    }

    // MARK: - System prompt

    private var systemPrompt: String {
        """
        You are Garden, a personal task management assistant embedded in a native Mac app.

        You help organize, prioritize, and manage a backlog of tasks across multiple projects. \
        Each project contains its own categories and items. You have tools to manage projects, \
        read the backlog, add items, update items, complete items, delete items, add categories, \
        reorder item priorities, reorder categories, and reorder projects.

        Guidelines:
        - Be concise and direct
        - When asked to add items, use the add_item tool — it defaults to the active project
        - When asked about the backlog, use read_backlog first to see current state
        - When reorganizing, read the backlog first, then use reorder_items with the new order
        - Categories are flexible — create new ones when it makes sense
        - Item IDs are UUIDs — always use read_backlog to get the actual IDs before modifying items
        - Most operations default to the active project — specify a project name only when targeting a different one
        - Use switch_project when the user wants to work in a different project
        """
    }

    // MARK: - Tool definitions

    private var toolDefinitions: [[String: Any]] {
        [
            [
                "name": "read_backlog",
                "description": "Read the full backlog including all projects, their items, categories, and priorities. Always call this first before making changes.",
                "input_schema": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                ],
            ],
            [
                "name": "add_item",
                "description": "Add a new item to the backlog",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "The task title"],
                        "notes": ["type": "string", "description": "Optional notes or details"],
                        "category": ["type": "string", "description": "Category name. Creates the category if it doesn't exist."],
                        "project": ["type": "string", "description": "Project name. Defaults to the active project."],
                        "priority": ["type": "integer", "description": "Priority bucket (0 = P0/highest). Defaults to 0."],
                    ] as [String: Any],
                    "required": ["title"],
                ],
            ],
            [
                "name": "update_item",
                "description": "Update an existing item's title, notes, category, priority bucket, or move it to a different project",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "The item's UUID"],
                        "title": ["type": "string", "description": "New title"],
                        "notes": ["type": "string", "description": "New notes"],
                        "category": ["type": "string", "description": "New category"],
                        "project": ["type": "string", "description": "Move item to this project"],
                        "priority": ["type": "integer", "description": "Priority bucket (0 = P0/highest)"],
                    ] as [String: Any],
                    "required": ["id"],
                ],
            ],
            [
                "name": "complete_item",
                "description": "Mark an item as completed",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "The item's UUID"],
                    ] as [String: Any],
                    "required": ["id"],
                ],
            ],
            [
                "name": "delete_item",
                "description": "Delete an item permanently",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "The item's UUID"],
                    ] as [String: Any],
                    "required": ["id"],
                ],
            ],
            [
                "name": "add_category",
                "description": "Add a new category to a project",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Category name"],
                        "project": ["type": "string", "description": "Project name. Defaults to the active project."],
                    ] as [String: Any],
                    "required": ["name"],
                ],
            ],
            [
                "name": "reorder_items",
                "description": "Reorder items within a category by specifying the desired order of item IDs",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "category": ["type": "string", "description": "The category to reorder"],
                        "item_ids": ["type": "array", "items": ["type": "string"], "description": "Item UUIDs in the desired priority order (first = highest priority)"],
                        "project": ["type": "string", "description": "Project name. Defaults to the active project."],
                    ] as [String: Any],
                    "required": ["category", "item_ids"],
                ],
            ],
            [
                "name": "reorder_categories",
                "description": "Reorder the sidebar categories by specifying all category names in the desired display order",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "category_names": ["type": "array", "items": ["type": "string"], "description": "Category names in the desired display order"],
                        "project": ["type": "string", "description": "Project name. Defaults to the active project."],
                    ] as [String: Any],
                    "required": ["category_names"],
                ],
            ],
            [
                "name": "add_project",
                "description": "Create a new project",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Project name"],
                    ] as [String: Any],
                    "required": ["name"],
                ],
            ],
            [
                "name": "delete_project",
                "description": "Delete a project and all its items. Cannot delete the last remaining project.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Project name to delete"],
                    ] as [String: Any],
                    "required": ["name"],
                ],
            ],
            [
                "name": "rename_project",
                "description": "Rename a project",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "old_name": ["type": "string", "description": "Current project name"],
                        "new_name": ["type": "string", "description": "New project name"],
                    ] as [String: Any],
                    "required": ["old_name", "new_name"],
                ],
            ],
            [
                "name": "switch_project",
                "description": "Switch the active project (updates the UI)",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Project name to switch to"],
                    ] as [String: Any],
                    "required": ["name"],
                ],
            ],
            [
                "name": "reorder_projects",
                "description": "Reorder projects in the project switcher",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "project_names": ["type": "array", "items": ["type": "string"], "description": "Project names in the desired display order"],
                    ] as [String: Any],
                    "required": ["project_names"],
                ],
            ],
        ]
    }
}

// MARK: - Errors

enum AgentError: LocalizedError {
    case noApiKey
    case apiError(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "No API key set. Open Settings to add your Anthropic key."
        case .apiError(let code, let body): return "API error \(code): \(body)"
        case .invalidResponse: return "Invalid response from Claude"
        }
    }
}
