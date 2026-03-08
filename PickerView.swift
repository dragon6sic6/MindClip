import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Keyboard Navigation State

class PickerNavState: ObservableObject {
    @Published var selectedIndex: Int = 0
    var scrollOnChange = false  // only scroll for keyboard nav, not mouse hover

    // Triggers from PickerWindow keyboard handler
    @Published var selectAllTrigger = false
    @Published var pasteSelectedTrigger = false
    @Published var deselectAllTrigger = false
}

struct PickerView: View {
    @ObservedObject private var manager = ClipboardManager.shared
    @ObservedObject var navState: PickerNavState
    var onSelect: (ClipboardItem) -> Void
    var onPasteMultiple: (([ClipboardItem]) -> Void)? = nil
    var onDismiss: () -> Void
    var onOpenSettings: (() -> Void)? = nil

    @State private var hoveredId: UUID? = nil
    @State private var appeared = false
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var selectedIds: Set<UUID> = []

    var isMultiSelectMode: Bool { !selectedIds.isEmpty }

    var filteredItems: [ClipboardItem] {
        if searchText.isEmpty { return manager.items }
        return manager.items.filter {
            $0.isImage ? "image".localizedCaseInsensitiveContains(searchText) :
            $0.preview.localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedItems: [ClipboardItem] {
        filteredItems.filter { selectedIds.contains($0.id) }
    }

    func toggleSelection(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedIds.contains(id) {
                selectedIds.remove(id)
            } else {
                selectedIds.insert(id)
            }
        }
    }

    var body: some View {
        ZStack {
            // Opaque background
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 10)

            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("Clipboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    // Session timer badge
                    SessionTimerBadge()

                    // Search toggle button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSearch.toggle()
                            if !showSearch { searchText = "" }
                        }
                    }) {
                        Image(systemName: showSearch ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                            .font(.system(size: 16))
                            .foregroundColor(showSearch ? .accentColor : .secondary)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    // Settings button
                    Button(action: {
                        onDismiss()
                        onOpenSettings?()
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    // Clear all button
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            manager.clearAll()
                        }
                        onDismiss()
                    }) {
                        Label("Clear", systemImage: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    // Close button
                    Button(action: { onDismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // Search bar (toggled)
                if showSearch {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()
                    .opacity(0.5)

                // Items list
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            // Pinned favorites section
                            if !manager.pinnedItems.isEmpty && searchText.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 9))
                                        .rotationEffect(.degrees(45))
                                    Text("Favorites")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.top, 2)

                                ForEach(manager.pinnedItems) { snippet in
                                    PinnedItemRow(
                                        snippet: snippet,
                                        onSelect: {
                                            onSelect(ClipboardItem(content: snippet.content))
                                        },
                                        onUnpin: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                manager.unpinItem(snippet)
                                            }
                                        }
                                    )
                                }

                                Divider().opacity(0.3)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 2)
                            }

                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardItemRow(
                                    item: item,
                                    index: index,
                                    isHighlighted: hoveredId == item.id || (navState.selectedIndex == index && hoveredId == nil),
                                    isSelected: selectedIds.contains(item.id),
                                    isMultiSelectMode: isMultiSelectMode,
                                    isPinned: !item.isImage && manager.isPinned(content: item.content),
                                    onSelect: {
                                        if isMultiSelectMode {
                                            toggleSelection(item.id)
                                        } else {
                                            onSelect(item)
                                        }
                                    },
                                    onToggleSelect: {
                                        toggleSelection(item.id)
                                    },
                                    onDelete: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            selectedIds.remove(item.id)
                                            manager.remove(item: item)
                                        }
                                    },
                                    onPin: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            if manager.isPinned(content: item.content) {
                                                if let pin = manager.pinnedItems.first(where: { $0.content == item.content }) {
                                                    manager.unpinItem(pin)
                                                }
                                            } else {
                                                manager.pinItem(content: item.content)
                                            }
                                        }
                                    }
                                )
                                .id(item.id)
                                .onHover { hovering in
                                    hoveredId = hovering ? item.id : nil
                                    if hovering {
                                        navState.selectedIndex = index
                                    }
                                }
                                .transition(.opacity)
                            }

                            if filteredItems.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.tertiary)
                                    Text("No results")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 24)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: navState.selectedIndex) { newIndex in
                        guard navState.scrollOnChange else { return }
                        navState.scrollOnChange = false
                        guard newIndex >= 0, newIndex < filteredItems.count else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(filteredItems[newIndex].id, anchor: .center)
                        }
                    }
                }

                // Footer — switches between normal hints and multi-select bar
                if isMultiSelectMode {
                    // Multi-select footer
                    HStack(spacing: 10) {
                        Text("\(selectedIds.count) selected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedIds.removeAll()
                            }
                        }) {
                            Text("Deselect All")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            let items = selectedItems
                            selectedIds.removeAll()
                            onPasteMultiple?(items)
                        }) {
                            Label("Paste \(selectedIds.count) item\(selectedIds.count == 1 ? "" : "s")", systemImage: "doc.on.clipboard")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.accentColor, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .transition(.opacity)
                } else {
                    // Normal footer hints
                    HStack(spacing: 12) {
                        footerHint(icon: "arrow.up.arrow.down", text: "Navigate")
                        footerHint(icon: "return", text: "Paste")
                        footerHint(icon: "command", text: "Click Multi")
                        Spacer()
                        Text("\(manager.items.count) item\(manager.items.count == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .transition(.opacity)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            withAnimation {
                appeared = true
            }
        }
        .onChange(of: searchText) { _ in
            navState.selectedIndex = 0
        }
        // Keyboard triggers from PickerWindow
        .onChange(of: navState.selectAllTrigger) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                for item in filteredItems {
                    selectedIds.insert(item.id)
                }
            }
        }
        .onChange(of: navState.deselectAllTrigger) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedIds.removeAll()
            }
        }
        .onChange(of: navState.pasteSelectedTrigger) { _ in
            guard isMultiSelectMode else { return }
            let items = selectedItems
            selectedIds.removeAll()
            onPasteMultiple?(items)
        }
    }

    @ViewBuilder
    func footerHint(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10))
        }
        .foregroundStyle(.tertiary)
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let index: Int
    let isHighlighted: Bool
    let isSelected: Bool
    let isMultiSelectMode: Bool
    let isPinned: Bool
    var onSelect: () -> Void
    var onToggleSelect: () -> Void
    var onDelete: () -> Void
    var onPin: () -> Void

    @State private var showDelete = false

    var body: some View {
        HStack(spacing: 10) {
            // Selection checkbox / Index badge
            ZStack {
                if isSelected {
                    // Selected checkmark
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 26, height: 26)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    // Normal index badge
                    Circle()
                        .fill(index == 0 ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08))
                        .frame(width: 26, height: 26)
                    if item.isImage {
                        Image(systemName: "photo")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(index == 0 ? .accentColor : .secondary)
                    } else {
                        Text(index < 9 ? "\(index + 1)" : "\u{2022}")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(index == 0 ? .accentColor : .secondary)
                    }
                }
            }

            // Content preview
            if item.isImage, let thumbnail = item.thumbnail {
                // Image thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )

                    HStack(spacing: 4) {
                        if let size = item.imageSize {
                            Text("\(Int(size.width))\u{00D7}\(Int(size.height))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        if let source = item.sourceApp {
                            Text("\u{00B7}")
                                .foregroundStyle(.quaternary)
                            Text(source)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Text("\u{00B7}")
                            .foregroundStyle(.quaternary)
                        Text(ClipboardManager.relativeTime(from: item.timestamp))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                // Text preview
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.preview)
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                        .help(item.content.count > 80 ? String(item.content.prefix(500)) : "")

                    HStack(spacing: 4) {
                        if let source = item.sourceApp {
                            Text(source)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Text(ClipboardManager.relativeTime(from: item.timestamp))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Action icons (always visible, brighter on hover)
            HStack(spacing: 4) {
                // Pin / Unpin (text items only)
                if !item.isImage {
                    Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                        .font(.system(size: 12))
                        .foregroundColor(isPinned ? .accentColor : .secondary)
                        .rotationEffect(.degrees(45))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                        .highPriorityGesture(TapGesture().onEnded { onPin() })
                }

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded { onSelect() })

                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded { onDelete() })
            }
            .padding(.trailing, 4)
            .opacity(isHighlighted || isSelected ? 1.0 : 0.3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, item.isImage ? 10 : 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.15)
                        : (isHighlighted
                            ? (index == 0 ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.07))
                            : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.5) :
                    (isHighlighted ? Color.accentColor.opacity(0.2) : Color.clear),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            // Check if Command key is held
            if NSEvent.modifierFlags.contains(.command) {
                onToggleSelect()
            } else {
                onSelect()
            }
        }
        .onDrag {
            if item.isImage, let image = item.image, let tiffData = image.tiffRepresentation {
                return NSItemProvider(item: tiffData as NSData, typeIdentifier: UTType.tiff.identifier)
            }
            return NSItemProvider(object: item.content as NSString)
        }
    }
}


// MARK: - Pinned Item Row

struct PinnedItemRow: View {
    let snippet: PinnedSnippet
    var onSelect: () -> Void
    var onUnpin: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundColor(.accentColor)
                .rotationEffect(.degrees(45))

            Text(snippet.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundColor(.primary.opacity(0.85))
                .help(snippet.content.count > 50 ? String(snippet.content.prefix(500)) : "")

            Spacer()

            Button(action: onUnpin) {
                Image(systemName: "pin.slash.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.3)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
        .onDrag {
            NSItemProvider(object: snippet.content as NSString)
        }
    }
}

// MARK: - Session Timer Badge

struct SessionTimerBadge: View {
    @ObservedObject private var manager = ClipboardManager.shared
    @State private var timeLeft: String = ""
    @State private var timer: Timer? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 10))
            Text(timeLeft)
                .font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .onAppear {
            updateTime()
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                updateTime()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    func updateTime() {
        let duration = manager.sessionDuration
        if duration >= 3600 {
            timeLeft = "\(Int(duration / 3600))h session"
        } else {
            timeLeft = "\(Int(duration / 60))min session"
        }
    }
}
