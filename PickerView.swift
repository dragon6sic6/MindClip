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
            if $0.isImage {
                return "image".localizedCaseInsensitiveContains(searchText)
            } else if $0.isFile {
                return ($0.fileName ?? "").localizedCaseInsensitiveContains(searchText)
                    || "file".localizedCaseInsensitiveContains(searchText)
            } else {
                return $0.preview.localizedCaseInsensitiveContains(searchText)
            }
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
            RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous)
                .fill(Color(.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous)
                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 8)

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    // Session timer badge
                    SessionTimerBadge()

                    // Item count badge
                    Text("\(manager.items.count) item\(manager.items.count == 1 ? "" : "s")")
                        .font(Theme.Typography.metadata)
                        .foregroundStyle(Theme.metadataText)

                    Spacer()

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
                            .background(Theme.badgeFill, in: Capsule())
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
                            .foregroundStyle(Theme.metadataText)
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(Theme.Typography.body)

                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.metadataText)
                            }
                            .buttonStyle(.plain)

                            Text("\(filteredItems.count) of \(manager.items.count)")
                                .font(Theme.Typography.metadata)
                                .foregroundStyle(Theme.metadataText)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()
                    .opacity(0.5)

                // Items list
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: Theme.Spacing.itemGap) {
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
                                    isPinned: !item.isImage && !item.isFile && manager.isPinned(content: item.content),
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

                            if filteredItems.isEmpty && !manager.items.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 24))
                                        .foregroundStyle(Theme.metadataText)
                                    Text("No results")
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.metadataText)
                                }
                                .padding(.vertical, 24)
                            } else if manager.items.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.system(size: 28))
                                        .foregroundStyle(Theme.metadataText)
                                    Text("Nothing copied yet")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Theme.subtleText)
                                    Text("Copy something with ⌘C to get started")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.metadataText)
                                }
                                .padding(.vertical, 32)
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
                                .background(Theme.badgeFill, in: Capsule())
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .transition(.opacity)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous))
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
                .font(Theme.Typography.metadata)
        }
        .foregroundStyle(Theme.metadataText)
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
                } else if index == 0 {
                    // Most recent — accent filled
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 26, height: 26)
                    badgeContent
                        .foregroundColor(.accentColor)
                } else if index < 9 {
                    // Items 1-8 — outline circle
                    Circle()
                        .strokeBorder(Theme.metadataText, lineWidth: 1)
                        .frame(width: 26, height: 26)
                    badgeContent
                        .foregroundColor(.secondary)
                } else {
                    // Items 9+ — small dot
                    Circle()
                        .fill(Theme.metadataText)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 26, height: 26)

            // Content type indicator + preview
            HStack(spacing: 0) {
                // Left color bar for images/files
                if item.isImage {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor.opacity(0.4))
                        .frame(width: 3)
                        .padding(.vertical, 2)
                        .padding(.trailing, 8)
                } else if item.isFile {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.green.opacity(0.4))
                        .frame(width: 3)
                        .padding(.vertical, 2)
                        .padding(.trailing, 8)
                }

                // Content preview
                if item.isFile, let icon = item.fileIcon {
                    fileContent(icon: icon)
                } else if item.isImage, let thumbnail = item.thumbnail {
                    imageContent(thumbnail: thumbnail)
                } else {
                    textContent
                }
            }

            Spacer()

            // Action icons (visible on hover)
            if isHighlighted || isSelected {
                HStack(spacing: 4) {
                    // Pin / Unpin (text items only)
                    if !item.isImage && !item.isFile {
                        actionButton(
                            icon: isPinned ? "pin.slash.fill" : "pin.fill",
                            color: isPinned ? .accentColor : .secondary,
                            rotation: 45
                        ) { onPin() }
                    }

                    actionButton(icon: "doc.on.doc", color: .secondary) { onSelect() }
                    actionButton(icon: "xmark", color: .secondary, fontSize: 10, fontWeight: .semibold) { onDelete() }
                }
                .padding(.trailing, 2)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Spacing.rowHorizontal)
        .padding(.vertical, (item.isImage || item.isFile) ? Theme.Spacing.rowVertical : 9)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(
                    isSelected
                        ? Theme.rowSelected
                        : (isHighlighted ? Theme.rowHover : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.4) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                onToggleSelect()
            } else {
                onSelect()
            }
        }
        .onDrag {
            if item.isFile, let url = item.fileURL {
                return NSItemProvider(object: url as NSURL)
            } else if item.isImage, let image = item.image, let tiffData = image.tiffRepresentation {
                return NSItemProvider(item: tiffData as NSData, typeIdentifier: UTType.tiff.identifier)
            }
            return NSItemProvider(object: item.content as NSString)
        }
    }

    // MARK: - Badge Content

    @ViewBuilder
    var badgeContent: some View {
        if item.isFile {
            Image(systemName: "doc")
                .font(.system(size: 11, weight: .semibold))
        } else if item.isImage {
            Image(systemName: "photo")
                .font(.system(size: 11, weight: .semibold))
        } else {
            Text(index < 9 ? "\(index + 1)" : "\u{2022}")
                .font(Theme.Typography.badge)
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    func fileContent(icon: NSImage) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName ?? "Unknown file")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                metadataLine(
                    extra: item.fileSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                )
            }
        }
    }

    @ViewBuilder
    func imageContent(thumbnail: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 80)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                        .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
                )

            HStack(spacing: 4) {
                if let size = item.imageSize {
                    Text("\(Int(size.width))\u{00D7}\(Int(size.height))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.metadataText)
                }
                metadataLine()
            }
        }
    }

    @ViewBuilder
    var textContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.preview)
                .font(Theme.Typography.body)
                .lineLimit(2)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .foregroundColor(.primary)
                .help(item.content.count > 80 ? String(item.content.prefix(500)) : "")

            metadataLine()
        }
    }

    // MARK: - Metadata Line

    @ViewBuilder
    func metadataLine(extra: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let extra = extra {
                Text(extra)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.metadataText)
                Text("\u{00B7}").foregroundStyle(Theme.metadataText)
            }
            if let source = item.sourceApp {
                Text(source)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.metadataText)
                Text("\u{00B7}").foregroundStyle(Theme.metadataText)
            }
            Text(ClipboardManager.relativeTime(from: item.timestamp))
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.metadataText)
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    func actionButton(
        icon: String,
        color: Color,
        rotation: Double = 0,
        fontSize: CGFloat = 12,
        fontWeight: Font.Weight = .regular,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: icon)
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundColor(color)
            .rotationEffect(.degrees(rotation))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                    .fill(Theme.badgeFill)
            )
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded { action() })
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

            if isHovered {
                Button(action: onUnpin) {
                    Image(systemName: "pin.slash.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(isHovered ? Theme.rowHover : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
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
        .foregroundStyle(Theme.metadataText)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.badgeFill, in: Capsule())
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
