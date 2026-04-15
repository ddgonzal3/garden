import SwiftUI

struct PriorityBoardView: View {
    @EnvironmentObject var store: BacklogStore
    @State private var dropTargetId: UUID?
    @State private var dropTargetBucket: Int?
    @State private var detailItemId: UUID?
    @State private var completingIds: Set<UUID> = []

    // Inline editing
    @State private var editingId: UUID?
    @State private var editingTitle: String = ""
    @FocusState private var editFocused: Bool

    @State private var clickMonitor: Any?
    @State private var monitorInstallWork: DispatchWorkItem?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<store.backlog.priorityBucketCount, id: \.self) { bucket in
                bucketColumn(bucket: bucket)
            }
        }
        .padding(16)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.backlog.activeItems.map(\.id))
        .onAppear { ScrollViewHelper.configureAllScrollViews() }
        .onExitCommand { commitEdit() }
        .onChange(of: store.editingItemId) { _, newId in
            if let newId {
                // Clean up any existing edit first (deletes empty placeholders)
                if let oldId = editingId {
                    let existingItem = store.backlog.activeItems.first { $0.id == oldId }
                    if existingItem?.title.isEmpty ?? true {
                        store.deleteItem(oldId)
                    }
                }
                editingId = newId
                editingTitle = ""
                store.editingItemId = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    editFocused = true
                }
            }
        }
        .onChange(of: editFocused) { _, focused in
            if !focused && editingId != nil {
                commitEdit()
            }
        }
        .onChange(of: editingId) { _, newId in
            // Cancel any pending monitor install to prevent leaked monitors
            monitorInstallWork?.cancel()
            monitorInstallWork = nil

            if let monitor = clickMonitor {
                NSEvent.removeMonitor(monitor)
                clickMonitor = nil
            }

            if newId != nil {
                let work = DispatchWorkItem {
                    guard self.editingId != nil else { return }
                    self.clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in
                        guard self.editingId != nil else { return event }

                        if event.type == .keyDown {
                            if event.keyCode == 53 { // Escape
                                DispatchQueue.main.async { self.commitEdit() }
                                return nil
                            }
                            return event
                        }

                        // Hit-test: is the click on a text-input view?
                        if let contentView = event.window?.contentView {
                            let loc = contentView.convert(event.locationInWindow, from: nil)
                            var hitView: NSView? = contentView.hitTest(loc)
                            while let v = hitView {
                                if v is NSText || v is NSTextField {
                                    return event
                                }
                                hitView = v.superview
                            }
                        }

                        // Click outside: force-resign first responder so @FocusState
                        // properly reports false → onChange triggers commitEdit.
                        // This is instant and doesn't interfere with gestures.
                        event.window?.makeFirstResponder(nil)
                        return event
                    }
                }
                monitorInstallWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
            }
        }
        .onDisappear {
            monitorInstallWork?.cancel()
            if let monitor = clickMonitor {
                NSEvent.removeMonitor(monitor)
                clickMonitor = nil
            }
        }
        .sheet(item: $detailItemId) { id in
            ItemDetailSheet(itemId: id)
        }
    }

    // MARK: - Bucket Column

    @ViewBuilder
    private func bucketColumn(bucket: Int) -> some View {
        let items = store.backlog.items(inBucket: bucket)
            .filter { !completingIds.contains($0.id) }

        BucketColumnView(
            bucket: bucket,
            items: items,
            editingId: $editingId,
            editingTitle: $editingTitle,
            editFocused: $editFocused,
            dropTargetId: $dropTargetId,
            dropTargetBucket: $dropTargetBucket,
            detailItemId: $detailItemId,
            completingIds: $completingIds,
            onCreateItem: { createItem(inBucket: bucket) },
            onCommitEdit: { commitEdit() },
            onComplete: { id in completeWithAnimation(id) },
            onStartRename: { item in startRename(item) }
        )
    }

    // MARK: - Actions

    private func createItem(inBucket bucket: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            store.addItemToBucket(bucket)
        }
    }

    private func commitEdit() {
        guard let id = editingId else { return }
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingItem = store.backlog.activeItems.first { $0.id == id }

        // Clear editing state first to prevent re-entrancy from onChange(of: editFocused)
        editingId = nil
        editingTitle = ""
        editFocused = false

        if trimmed.isEmpty {
            if existingItem?.title.isEmpty ?? true {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    store.deleteItem(id)
                }
            }
        } else if var item = existingItem {
            if trimmed != item.title {
                item.title = trimmed
                store.updateItem(item)
            }
        }
    }

    private func startRename(_ item: GardenItem) {
        editingId = item.id
        editingTitle = item.title
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            editFocused = true
        }
    }

    private func cancelEdit() {
        guard let id = editingId else { return }
        editFocused = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            store.deleteItem(id)
        }
        editingId = nil
        editingTitle = ""
    }

    private func completeWithAnimation(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.2)) {
            completingIds.insert(id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                completingIds.remove(id)
                store.completeItem(id)
            }
        }
    }
}

// MARK: - Make UUID work with .sheet(item:)

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

// MARK: - Bucket Column (extracted for hover state)

private struct BucketColumnView: View {
    let bucket: Int
    let items: [GardenItem]
    @Binding var editingId: UUID?
    @Binding var editingTitle: String
    var editFocused: FocusState<Bool>.Binding
    @Binding var dropTargetId: UUID?
    @Binding var dropTargetBucket: Int?
    @Binding var detailItemId: UUID?
    @Binding var completingIds: Set<UUID>
    let onCreateItem: () -> Void
    let onCommitEdit: () -> Void
    let onComplete: (UUID) -> Void
    let onStartRename: (GardenItem) -> Void

    @EnvironmentObject var store: BacklogStore
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("P\(bucket + 1)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(items.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                if isHovering {
                    Button(action: onCreateItem) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contextMenu {
                Button("New Item") { onCreateItem() }
                Divider()
                Button("Add Priority Level") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        store.addPriorityBucket()
                    }
                }
                if store.backlog.priorityBucketCount > 1 {
                    Button("Remove P\(bucket + 1)", role: .destructive) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            store.removePriorityBucket(bucket)
                        }
                    }
                }
            }

            Divider()
                .padding(.horizontal, 8)

            // Scrollable card area
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(items) { item in
                        if editingId == item.id {
                            inlineEditCard(item: item)
                        } else {
                            boardCard(item: item)
                                .id(item.id)
                                .draggable(item)
                                .dropDestination(for: GardenItem.self) { dropped, _ in
                                    guard let source = dropped.first, source.id != item.id else { return false }
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        store.moveItemInBucket(source.id, beforeItemId: item.id)
                                    }
                                    dropTargetId = nil
                                    return true
                                } isTargeted: { targeted in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        dropTargetId = targeted ? item.id : (dropTargetId == item.id ? nil : dropTargetId)
                                    }
                                }
                        }
                    }
                }
                .padding(6)

                // Catch-all drop zone at bottom of content
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                    .dropDestination(for: GardenItem.self) { dropped, _ in
                        guard let source = dropped.first else { return false }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            store.moveItemToBucket(source.id, bucket: bucket)
                        }
                        dropTargetBucket = nil
                        return true
                    } isTargeted: { targeted in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            dropTargetBucket = targeted ? bucket : (dropTargetBucket == bucket ? nil : dropTargetBucket)
                        }
                    }
            }
            // Double-click anywhere in the column's scroll area to create
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onCreateItem() }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 200)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    dropTargetBucket == bucket
                        ? Color.accentColor.opacity(0.4)
                        : Color(.separatorColor).opacity(0.3),
                    lineWidth: dropTargetBucket == bucket ? 2 : 1
                )
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Inline Edit Card (new item creation — styled like a real card)

    @ViewBuilder
    private func inlineEditCard(item: GardenItem) -> some View {
        let catColor = CategoryColor.color(for: item.category)

        VStack(alignment: .leading, spacing: 6) {
            TextField("New item...", text: $editingTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .focused(editFocused)
                .onSubmit { onCommitEdit() }

            HStack(spacing: 5) {
                Circle()
                    .fill(catColor)
                    .frame(width: 6, height: 6)

                Text(item.category)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(catColor)
                .frame(width: 3)
                .padding(.vertical, 1)
        }
    }

    // MARK: - Board Card

    @ViewBuilder
    private func boardCard(item: GardenItem) -> some View {
        let catColor = CategoryColor.color(for: item.category)
        let isTarget = dropTargetId == item.id

        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(3)
                .foregroundStyle(.primary)
                .onTapGesture { onStartRename(item) }

            HStack(spacing: 5) {
                Circle()
                    .fill(catColor)
                    .frame(width: 6, height: 6)

                Text(item.category)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(catColor)
                .frame(width: 3)
                .padding(.vertical, 1)
        }
        .overlay(alignment: .top) {
            if isTarget {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
                    .offset(y: -3)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            detailItemId = item.id
        }
        .contextMenu {
            Button("Open") { detailItemId = item.id }
            Divider()
            Menu("Priority") {
                ForEach(0..<store.backlog.priorityBucketCount, id: \.self) { b in
                    if b != item.priorityBucket {
                        Button("P\(b + 1)") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                store.moveItemToBucket(item.id, bucket: b)
                            }
                        }
                    }
                }
            }
            Menu("Category") {
                ForEach(store.backlog.categories.filter { $0 != item.category }, id: \.self) { cat in
                    Button(cat) { store.moveItemToCategory(item.id, newCategory: cat) }
                }
            }
            Divider()
            Button("Complete") { onComplete(item.id) }
            Button("Delete", role: .destructive) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    store.deleteItem(item.id)
                }
            }
        }
    }
}
