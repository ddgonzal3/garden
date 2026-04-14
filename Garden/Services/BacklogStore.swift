import Foundation
import Combine
import SwiftUI

@MainActor
class BacklogStore: ObservableObject {
    @Published var backlog: Backlog = Backlog()

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
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            backlog = try decoder.decode(Backlog.self, from: data)
        } catch {
            print("Garden: Failed to load backlog: \(error)")
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(backlog)
            lastWriteByUs = Date()
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Garden: Failed to save backlog: \(error)")
        }
    }

    // MARK: - File watching (for Claude integration)

    private func watchFile() {
        // Ensure the file exists so we can watch it
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
            // Skip reloads from our own writes
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

    // MARK: - Mutations

    func addItem(_ item: GardenItem) {
        var newItem = item
        newItem.priority = (backlog.activeItems.last?.priority ?? -1) + 1
        backlog.items.append(newItem)
        if !backlog.categories.contains(newItem.category) {
            backlog.categories.append(newItem.category)
        }
        save()
    }

    func updateItem(_ item: GardenItem) {
        guard let index = backlog.items.firstIndex(where: { $0.id == item.id }) else { return }
        backlog.items[index] = item
        if !backlog.categories.contains(item.category) {
            backlog.categories.append(item.category)
        }
        save()
    }

    func completeItem(_ id: UUID) {
        guard let index = backlog.items.firstIndex(where: { $0.id == id }) else { return }
        backlog.items[index].completedAt = Date()
        save()
    }

    func deleteItem(_ id: UUID) {
        backlog.items.removeAll { $0.id == id }
        save()
    }

    func moveItem(from source: IndexSet, to destination: Int, in category: String) {
        var categoryItems = backlog.items(in: category)
        categoryItems.move(fromOffsets: source, toOffset: destination)
        // Reassign priorities based on new order
        for (index, item) in categoryItems.enumerated() {
            if let itemIndex = backlog.items.firstIndex(where: { $0.id == item.id }) {
                backlog.items[itemIndex].priority = index
            }
        }
        save()
    }

    func addCategory(_ name: String) {
        guard !backlog.categories.contains(name) else { return }
        backlog.categories.append(name)
        save()
    }

    func deleteCategory(_ name: String) {
        backlog.categories.removeAll { $0 == name }
        // Move items to Uncategorized
        for index in backlog.items.indices {
            if backlog.items[index].category == name {
                backlog.items[index].category = "Uncategorized"
            }
        }
        save()
    }
}
