import Foundation
import Combine
import SwiftUI

@MainActor
class BacklogStore: ObservableObject {
    @Published var backlog: Backlog = Backlog()
    @Published var editingItemId: UUID?

    private let fileURL: URL
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var lastWriteByUs: Date = .distantPast

    init() {
        let gardenDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".garden")
        try? FileManager.default.createDirectory(at: gardenDir, withIntermediateDirectories: true)
        self.fileURL = gardenDir.appendingPathComponent("backlog.json")

        load()
        watchFile()
    }

    deinit {
        fileWatcher?.cancel()
        if fileDescriptor >= 0 { close(fileDescriptor) }
    }

    // MARK: - Persistence

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            backlog = try JSONDecoder().decode(Backlog.self, from: data)
        } catch {
            print("Garden: Failed to load backlog: \(error)")
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(backlog)
            lastWriteByUs = Date()
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Garden: Failed to save backlog: \(error)")
        }
    }

    // MARK: - File watching (for Claude integration)

    private func watchFile() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            save()
        }

        fileDescriptor = Darwin.open(fileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            if Date().timeIntervalSince(self.lastWriteByUs) < 1.0 { return }
            Task { @MainActor in
                self.load()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 { Darwin.close(self.fileDescriptor) }
        }

        source.resume()
        fileWatcher = source
    }

    // MARK: - Project helpers

    private func projectIndex(for id: UUID? = nil) -> Int? {
        if let id = id {
            return backlog.projects.firstIndex { $0.id == id }
        }
        return backlog.activeProjectIndex()
    }

    // MARK: - Item mutations

    func addItem(_ item: GardenItem, inProject projectId: UUID? = nil) {
        guard let idx = projectIndex(for: projectId) else { return }
        var newItem = item
        newItem.priority = (backlog.projects[idx].activeItems.last?.priority ?? -1) + 1
        backlog.projects[idx].items.append(newItem)
        if !backlog.projects[idx].categories.contains(newItem.category) {
            backlog.projects[idx].categories.append(newItem.category)
        }
        save()
    }

    func addItemToTop(_ item: GardenItem, inProject projectId: UUID? = nil) {
        guard let idx = projectIndex(for: projectId) else { return }
        var newItem = item
        // Shift existing items in category to make room at position 0
        for i in backlog.projects[idx].items.indices {
            if backlog.projects[idx].items[i].category == newItem.category && !backlog.projects[idx].items[i].isCompleted {
                backlog.projects[idx].items[i].priority += 1
            }
        }
        newItem.priority = 0
        backlog.projects[idx].items.append(newItem)
        if !backlog.projects[idx].categories.contains(newItem.category) {
            backlog.projects[idx].categories.append(newItem.category)
        }
        editingItemId = newItem.id
        save()
    }

    func updateItem(_ item: GardenItem) {
        for idx in backlog.projects.indices {
            if let itemIdx = backlog.projects[idx].items.firstIndex(where: { $0.id == item.id }) {
                backlog.projects[idx].items[itemIdx] = item
                if !backlog.projects[idx].categories.contains(item.category) {
                    backlog.projects[idx].categories.append(item.category)
                }
                save()
                return
            }
        }
    }

    func completeItem(_ id: UUID) {
        for idx in backlog.projects.indices {
            if let itemIdx = backlog.projects[idx].items.firstIndex(where: { $0.id == id }) {
                backlog.projects[idx].items[itemIdx].completedAt = Date()
                save()
                return
            }
        }
    }

    func deleteItem(_ id: UUID) {
        for idx in backlog.projects.indices {
            if backlog.projects[idx].items.contains(where: { $0.id == id }) {
                backlog.projects[idx].items.removeAll { $0.id == id }
                save()
                return
            }
        }
    }

    func moveItem(from source: IndexSet, to destination: Int, in category: String) {
        guard let idx = projectIndex() else { return }
        var categoryItems = backlog.projects[idx].items(in: category)
        categoryItems.move(fromOffsets: source, toOffset: destination)
        for (i, item) in categoryItems.enumerated() {
            if let itemIdx = backlog.projects[idx].items.firstIndex(where: { $0.id == item.id }) {
                backlog.projects[idx].items[itemIdx].priority = i
            }
        }
        save()
    }

    func moveItemToProject(_ itemId: UUID, targetProjectId: UUID) {
        for sourceIdx in backlog.projects.indices {
            if let itemIdx = backlog.projects[sourceIdx].items.firstIndex(where: { $0.id == itemId }) {
                var item = backlog.projects[sourceIdx].items[itemIdx]
                backlog.projects[sourceIdx].items.remove(at: itemIdx)
                guard let targetIdx = backlog.projects.firstIndex(where: { $0.id == targetProjectId }) else { return }
                item.priority = (backlog.projects[targetIdx].activeItems.last?.priority ?? -1) + 1
                backlog.projects[targetIdx].items.append(item)
                if !backlog.projects[targetIdx].categories.contains(item.category) {
                    backlog.projects[targetIdx].categories.append(item.category)
                }
                save()
                return
            }
        }
    }

    func moveItemToCategory(_ itemId: UUID, newCategory: String) {
        guard let idx = projectIndex() else { return }
        guard let itemIdx = backlog.projects[idx].items.firstIndex(where: { $0.id == itemId }) else { return }
        guard backlog.projects[idx].items[itemIdx].category != newCategory else { return }

        backlog.projects[idx].items[itemIdx].category = newCategory

        // Shift existing items in new category to make room at top
        for i in backlog.projects[idx].items.indices {
            if backlog.projects[idx].items[i].category == newCategory
                && backlog.projects[idx].items[i].id != itemId
                && !backlog.projects[idx].items[i].isCompleted {
                backlog.projects[idx].items[i].priority += 1
            }
        }
        backlog.projects[idx].items[itemIdx].priority = 0

        if !backlog.projects[idx].categories.contains(newCategory) {
            backlog.projects[idx].categories.append(newCategory)
        }
        save()
    }

    func moveItemBeforeTarget(_ draggedId: UUID, targetId: UUID) {
        guard let idx = projectIndex() else { return }
        guard draggedId != targetId else { return }
        guard let dragIdx = backlog.projects[idx].items.firstIndex(where: { $0.id == draggedId }) else { return }
        guard let targetIdx = backlog.projects[idx].items.firstIndex(where: { $0.id == targetId }) else { return }

        let targetCategory = backlog.projects[idx].items[targetIdx].category
        let oldCategory = backlog.projects[idx].items[dragIdx].category

        // Remove from current position
        var item = backlog.projects[idx].items.remove(at: dragIdx)
        item.category = targetCategory

        // Re-find target after removal (index may have shifted)
        guard let newTargetIdx = backlog.projects[idx].items.firstIndex(where: { $0.id == targetId }) else {
            backlog.projects[idx].items.append(item)
            recalculatePriorities(in: targetCategory, projectIdx: idx)
            save()
            return
        }

        backlog.projects[idx].items.insert(item, at: newTargetIdx)
        recalculatePriorities(in: targetCategory, projectIdx: idx)
        if oldCategory != targetCategory {
            recalculatePriorities(in: oldCategory, projectIdx: idx)
        }
        save()
    }

    private func recalculatePriorities(in category: String, projectIdx idx: Int) {
        let categoryItemIds = backlog.projects[idx].items.enumerated()
            .filter { $0.element.category == category && !$0.element.isCompleted }
            .map { $0.offset }
        for (priority, itemIdx) in categoryItemIds.enumerated() {
            backlog.projects[idx].items[itemIdx].priority = priority
        }
    }

    // MARK: - Priority bucket mutations

    func moveItemToBucket(_ itemId: UUID, bucket: Int) {
        guard let idx = projectIndex() else { return }
        guard let itemIdx = backlog.projects[idx].items.firstIndex(where: { $0.id == itemId }) else { return }
        backlog.projects[idx].items[itemIdx].priorityBucket = bucket
        // Place at end of target bucket
        let maxPriority = backlog.projects[idx].items
            .filter { $0.priorityBucket == bucket && !$0.isCompleted && $0.id != itemId }
            .map(\.priority).max() ?? -1
        backlog.projects[idx].items[itemIdx].priority = maxPriority + 1
        save()
    }

    func moveItemInBucket(_ itemId: UUID, beforeItemId: UUID) {
        guard let idx = projectIndex() else { return }
        guard let dragIdx = backlog.projects[idx].items.firstIndex(where: { $0.id == itemId }) else { return }
        guard let targetIdx = backlog.projects[idx].items.firstIndex(where: { $0.id == beforeItemId }) else { return }

        let targetBucket = backlog.projects[idx].items[targetIdx].priorityBucket
        backlog.projects[idx].items[dragIdx].priorityBucket = targetBucket

        // Remove and reinsert
        var item = backlog.projects[idx].items.remove(at: dragIdx)
        item.priorityBucket = targetBucket

        guard let newTargetIdx = backlog.projects[idx].items.firstIndex(where: { $0.id == beforeItemId }) else {
            backlog.projects[idx].items.append(item)
            recalculateBucketPriorities(bucket: targetBucket, projectIdx: idx)
            save()
            return
        }

        backlog.projects[idx].items.insert(item, at: newTargetIdx)
        recalculateBucketPriorities(bucket: targetBucket, projectIdx: idx)
        save()
    }

    private func recalculateBucketPriorities(bucket: Int, projectIdx idx: Int) {
        let bucketItemIndices = backlog.projects[idx].items.enumerated()
            .filter { $0.element.priorityBucket == bucket && !$0.element.isCompleted }
            .map { $0.offset }
        for (priority, itemIdx) in bucketItemIndices.enumerated() {
            backlog.projects[idx].items[itemIdx].priority = priority
        }
    }

    func addItemToBucket(_ bucket: Int) {
        guard let idx = projectIndex() else { return }
        let maxPriority = backlog.projects[idx].items
            .filter { $0.priorityBucket == bucket && !$0.isCompleted }
            .map(\.priority).max() ?? -1
        var newItem = GardenItem(title: "", priorityBucket: bucket)
        newItem.priority = maxPriority + 1
        backlog.projects[idx].items.append(newItem)
        editingItemId = newItem.id
        save()
    }

    func addPriorityBucket() {
        guard let idx = projectIndex() else { return }
        backlog.projects[idx].priorityBucketCount += 1
        save()
    }

    func removePriorityBucket(_ bucket: Int) {
        guard let idx = projectIndex() else { return }
        guard backlog.projects[idx].priorityBucketCount > 1 else { return }
        let targetBucket = max(0, bucket - 1)
        for i in backlog.projects[idx].items.indices {
            if backlog.projects[idx].items[i].priorityBucket == bucket {
                backlog.projects[idx].items[i].priorityBucket = targetBucket
            }
            if backlog.projects[idx].items[i].priorityBucket > bucket {
                backlog.projects[idx].items[i].priorityBucket -= 1
            }
        }
        backlog.projects[idx].priorityBucketCount -= 1
        save()
    }

    // MARK: - Category mutations

    func addCategory(_ name: String, inProject projectId: UUID? = nil) {
        guard let idx = projectIndex(for: projectId) else { return }
        guard !backlog.projects[idx].categories.contains(name) else { return }
        backlog.projects[idx].categories.append(name)
        save()
    }

    func deleteCategory(_ name: String) {
        guard let idx = projectIndex() else { return }
        backlog.projects[idx].categories.removeAll { $0 == name }
        for i in backlog.projects[idx].items.indices {
            if backlog.projects[idx].items[i].category == name {
                backlog.projects[idx].items[i].category = "Uncategorized"
            }
        }
        save()
    }

    func reorderCategories(_ orderedNames: [String], inProject projectId: UUID? = nil) {
        guard let idx = projectIndex(for: projectId) else { return }
        var seen = Set<String>()
        var result: [String] = []
        for name in orderedNames where backlog.projects[idx].categories.contains(name) && !seen.contains(name) {
            result.append(name)
            seen.insert(name)
        }
        for name in backlog.projects[idx].categories where !seen.contains(name) {
            result.append(name)
        }
        backlog.projects[idx].categories = result
        save()
    }

    func reorderItems(in category: String, orderedIds: [UUID], inProject projectId: UUID? = nil) {
        guard let idx = projectIndex(for: projectId) else { return }
        for (i, uuid) in orderedIds.enumerated() {
            if let itemIdx = backlog.projects[idx].items.firstIndex(where: { $0.id == uuid }) {
                backlog.projects[idx].items[itemIdx].priority = i
            }
        }
        save()
    }

    // MARK: - Project mutations

    func addProject(_ name: String) {
        guard !backlog.projects.contains(where: { $0.name == name }) else { return }
        let project = GardenProject(name: name)
        backlog.projects.append(project)
        save()
    }

    func deleteProject(_ id: UUID) {
        guard backlog.projects.count > 1 else { return }
        backlog.projects.removeAll { $0.id == id }
        if backlog.activeProjectId == id {
            backlog.activeProjectId = backlog.projects.first?.id
        }
        save()
    }

    func renameProject(_ id: UUID, to name: String) {
        guard let idx = backlog.projects.firstIndex(where: { $0.id == id }) else { return }
        backlog.projects[idx].name = name
        save()
    }

    func switchProject(_ id: UUID) {
        backlog.activeProjectId = id
        save()
    }

    func reorderProjects(_ orderedIds: [UUID]) {
        var seen = Set<UUID>()
        var result: [GardenProject] = []
        for id in orderedIds {
            if let project = backlog.projects.first(where: { $0.id == id }), !seen.contains(id) {
                result.append(project)
                seen.insert(id)
            }
        }
        for project in backlog.projects where !seen.contains(project.id) {
            result.append(project)
        }
        backlog.projects = result
        save()
    }
}
