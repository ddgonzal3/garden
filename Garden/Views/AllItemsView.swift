import SwiftUI
import AppKit

struct AllItemsView: View {
    @EnvironmentObject var store: BacklogStore
    @State private var dropTargetId: UUID?

    var body: some View {
        let _ = debugLog("[AllItemsView] body — categories: \(store.backlog.categories.count), activeItems: \(store.backlog.activeItems.count)")
        List {
            ForEach(store.backlog.categories, id: \.self) { category in
                let items = store.backlog.items(in: category)
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            ItemRow(item: item)
                                .overlay(alignment: .top) {
                                    if dropTargetId == item.id {
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.accentColor.opacity(0.6))
                                            .frame(height: 2)
                                            .padding(.horizontal, 4)
                                            .transition(.opacity)
                                    }
                                }
                                .draggable(item)
                                .dropDestination(for: GardenItem.self) { droppedItems, _ in
                                    guard let dropped = droppedItems.first, dropped.id != item.id else { return false }
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        store.moveItemBeforeTarget(dropped.id, targetId: item.id)
                                    }
                                    dropTargetId = nil
                                    return true
                                } isTargeted: { targeted in
                                    dropTargetId = targeted ? item.id : nil
                                }
                        }
                    } header: {
                        HStack {
                            Text(category)
                            Spacer()
                            Button(action: {
                                let newItem = GardenItem(title: "", category: category)
                                store.addItemToTop(newItem)
                            }) {
                                Image(systemName: "plus")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.trailing, 8)
                    }
                }
            }
        }
        .listStyle(.plain)
        .onAppear { ScrollViewHelper.configureAllScrollViews() }
    }
}

/// Finds all NSScrollViews in the app and forces thin overlay scrollers.
enum ScrollViewHelper {
    static func configureAllScrollViews() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for window in NSApp.windows {
                applyOverlayStyle(to: window.contentView)
            }
        }
    }

    private static func applyOverlayStyle(to view: NSView?) {
        guard let view = view else { return }
        if let scrollView = view as? NSScrollView {
            scrollView.scrollerStyle = .overlay
            scrollView.scrollerKnobStyle = .light
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
        }
        for subview in view.subviews {
            applyOverlayStyle(to: subview)
        }
    }
}
