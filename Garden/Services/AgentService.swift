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
        // Build conversation from message history
        var apiMessages = buildAPIMessages(newUserText: userText)

        for _ in 0..<10 { // max iterations to prevent runaway
            let response = try await callClaude(messages: apiMessages)

            guard let stopReason = response["stop_reason"] as? String,
                  let contentBlocks = response["content"] as? [[String: Any]] else {
                throw AgentError.invalidResponse
            }

            if stopReason == "end_turn" {
                return extractText(from: contentBlocks)
            }

            if stopReason == "tool_use" {
                // Append assistant response to conversation
                apiMessages.append(["role": "assistant", "content": contentBlocks])

                // Execute tools and collect results
                var toolResults: [[String: Any]] = []
                for block in contentBlocks where (block["type"] as? String) == "tool_use" {
                    let result = executeTool(block)
                    toolResults.append(result)
                }

                // Append tool results as user message
                apiMessages.append(["role": "user", "content": toolResults])
                continue
            }

            // Unknown stop reason — return whatever text we have
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
        default:
            result = "Unknown tool: \(name)"
        }

        return [
            "type": "tool_result",
            "tool_use_id": toolUseId,
            "content": result,
        ]
    }

    // MARK: - Tool implementations

    private func readBacklog() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(backlogStore.backlog) else { return "Failed to encode backlog" }
        return String(data: data, encoding: .utf8) ?? "Failed to encode backlog"
    }

    private func addItem(_ input: [String: Any]) -> String {
        let title = input["title"] as? String ?? ""
        let notes = input["notes"] as? String ?? ""
        let category = input["category"] as? String ?? "Uncategorized"

        guard !title.isEmpty else { return "Error: title is required" }

        let item = GardenItem(title: title, notes: notes, category: category)
        backlogStore.addItem(item)
        return "Added '\(title)' to \(category)"
    }

    private func updateItem(_ input: [String: Any]) -> String {
        guard let idStr = input["id"] as? String, let id = UUID(uuidString: idStr) else {
            return "Error: valid id is required"
        }
        guard var item = backlogStore.backlog.items.first(where: { $0.id == id }) else {
            return "Error: item not found"
        }

        if let title = input["title"] as? String { item.title = title }
        if let notes = input["notes"] as? String { item.notes = notes }
        if let category = input["category"] as? String { item.category = category }

        backlogStore.updateItem(item)
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

    private func addCategory(_ input: [String: Any]) -> String {
        guard let name = input["name"] as? String, !name.isEmpty else {
            return "Error: name is required"
        }
        backlogStore.addCategory(name)
        return "Added category '\(name)'"
    }

    private func reorderItems(_ input: [String: Any]) -> String {
        guard let category = input["category"] as? String,
              let orderedIds = input["item_ids"] as? [String] else {
            return "Error: category and item_ids are required"
        }

        let uuids = orderedIds.compactMap { UUID(uuidString: $0) }
        for (index, uuid) in uuids.enumerated() {
            if let itemIndex = backlogStore.backlog.items.firstIndex(where: { $0.id == uuid }) {
                backlogStore.backlog.items[itemIndex].priority = index
            }
        }
        backlogStore.save()
        return "Reordered \(uuids.count) items in \(category)"
    }

    // MARK: - Helpers

    private func buildAPIMessages(newUserText: String) -> [[String: Any]] {
        // Include recent conversation history for context (last 20 messages)
        var apiMessages: [[String: Any]] = []
        let recent = messages.suffix(20)

        for msg in recent {
            apiMessages.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content,
            ])
        }

        // The new user message is already appended to self.messages,
        // so it's included in the loop above
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

        You help organize, prioritize, and manage a backlog of tasks. You have tools to read \
        the backlog, add items, update items, complete items, delete items, add categories, and \
        reorder priorities.

        Guidelines:
        - Be concise and direct
        - When asked to add items, use the add_item tool
        - When asked about the backlog, use read_backlog first to see current state
        - When reorganizing, read the backlog first, then use reorder_items with the new order
        - Categories are flexible — create new ones when it makes sense
        - Item IDs are UUIDs — always use read_backlog to get the actual IDs before modifying items
        """
    }

    // MARK: - Tool definitions

    private var toolDefinitions: [[String: Any]] {
        [
            [
                "name": "read_backlog",
                "description": "Read the full backlog including all items, categories, and priorities. Always call this first before making changes.",
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
                    ] as [String: Any],
                    "required": ["title"],
                ],
            ],
            [
                "name": "update_item",
                "description": "Update an existing item's title, notes, or category",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "The item's UUID"],
                        "title": ["type": "string", "description": "New title"],
                        "notes": ["type": "string", "description": "New notes"],
                        "category": ["type": "string", "description": "New category"],
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
                "description": "Add a new category to the backlog",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Category name"],
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
                    ] as [String: Any],
                    "required": ["category", "item_ids"],
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
