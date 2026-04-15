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

    // Selection
    @State private var selectedId: UUID?
    @State private var selectionMonitor: Any?

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
        .onAppear {
            ScrollViewHelper.configureAllScrollViews()
            installSelectionMonitor()
        }
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
            if let monitor = selectionMonitor {
                NSEvent.removeMonitor(monitor)
                selectionMonitor = nil
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
            selectedId: $selectedId,
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
        selectedId = nil
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
        if selectedId == id { selectedId = nil }
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

    private func duplicateItem(_ id: UUID) {
        if let newId = store.duplicateItem(id) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedId = newId
            }
        }
    }

    private func installSelectionMonitor() {
        selectionMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Don't intercept when editing or when a text field is active
            guard self.editingId == nil else { return event }
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSText {
                return event
            }

            // Cmd+Z to undo (works even without selection)
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z"
                && !event.modifierFlags.contains(.shift) {
                if self.store.canUndo {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        self.store.undo()
                    }
                    return nil
                }
                return event
            }

            guard let id = self.selectedId else { return event }

            // Delete (backspace) or Forward Delete
            if event.keyCode == 51 || event.keyCode == 117 {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.store.deleteItem(id)
                }
                self.selectedId = nil
                return nil
            }

            // Cmd+D to duplicate
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "d" {
                self.duplicateItem(id)
                return nil
            }

            // Escape to deselect
            if event.keyCode == 53 {
                self.selectedId = nil
                return nil
            }

            return event
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
    @Binding var selectedId: UUID?
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
            // Double-click empty space to create, single-click to deselect
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onCreateItem() }
            .simultaneousGesture(TapGesture().onEnded { selectedId = nil })
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
            TextField("New item...", text: $editingTitle, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1...5)
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
        .background { cardBackground(selected: false) }
        .overlay { cardBorder(selected: false) }
        .overlay(alignment: .leading) { cardCategoryStrip(color: catColor, selected: false) }
    }

    // MARK: - Board Card

    @ViewBuilder
    private func boardCard(item: GardenItem) -> some View {
        let catColor = CategoryColor.color(for: item.category)
        let isTarget = dropTargetId == item.id
        let isSelected = selectedId == item.id

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
        .background { cardBackground(selected: isSelected) }
        .overlay { cardBorder(selected: isSelected) }
        .overlay(alignment: .leading) { cardCategoryStrip(color: catColor, selected: isSelected) }
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
        .simultaneousGesture(TapGesture().onEnded {
            selectedId = item.id
        })
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

    // MARK: - Card Chrome (shared between board card & inline edit card)

    @ViewBuilder
    private func cardBackground(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.controlBackgroundColor))
            .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
    }

    @ViewBuilder
    private func cardBorder(selected: Bool) -> some View {
        if selected {
            // Selected: accent gradient border (Flow's accent-border pattern)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        } else {
            // Normal: gradient stroke — bright top edge fading to dark bottom
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
    }

    @ViewBuilder
    private func cardCategoryStrip(color: Color, selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: selected ? 4 : 3)
            .padding(.vertical, 1)
    }
}
