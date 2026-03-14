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
    @Published var mergeTrigger = false
}

struct PickerView: View {
    @ObservedObject private var manager = ClipboardManager.shared
    @ObservedObject var navState: PickerNavState
    var onSelect: (ClipboardItem) -> Void
    var onPasteMultiple: (([ClipboardItem]) -> Void)? = nil
    var onMerge: (([ClipboardItem]) -> Void)? = nil
    var onDismiss: () -> Void
    var onOpenSettings: (() -> Void)? = nil

    enum PickerTab { case clipboard, snippets }

    @State private var hoveredId: UUID? = nil
    @State private var appeared = false
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var selectedIds: Set<UUID> = []
    @State private var activeTab: PickerTab = .clipboard
    @State private var snippetSavedFlash = false
    @State private var isAddingSnippetInline = false
    @State private var inlineSnippetTitle = ""
    @State private var inlineSnippetContent = ""
    @State private var showSaveSnippetEditor = false
    @State private var saveSnippetTitle = ""
    @State private var saveSnippetContent = ""
    @State private var editingSnippetId: UUID? = nil
    @State private var editSnippetTitle = ""
    @State private var editSnippetContent = ""

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

    var filteredPins: [QuickPin] {
        if searchText.isEmpty { return manager.quickPins }
        return manager.quickPins.filter {
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredSnippets: [PinnedSnippet] {
        if searchText.isEmpty { return manager.pinnedItems }
        return manager.pinnedItems.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.content.localizedCaseInsensitiveContains(searchText)
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
                    // Tab switcher
                    HStack(spacing: 0) {
                        pickerTabButton(.clipboard, icon: "doc.on.clipboard", label: "Clipboard")
                        pickerTabButton(.snippets, icon: "text.quote", label: "Snippets")
                    }
                    .background(Theme.badgeFill, in: Capsule())

                    if snippetSavedFlash {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                            Text("Saved")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.orange)
                        .transition(.opacity)
                    } else if activeTab == .clipboard {
                        SessionTimerBadge()
                    }

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

                    // Appearance toggle button
                    appearanceToggleButton

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

                    if activeTab == .clipboard {
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
                    }

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

                // Content — tab-switched
                if activeTab == .clipboard {
                    clipboardContent
                } else {
                    snippetsContent
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

                        // Merge button — only for 2+ text items
                        if selectedItems.filter({ !$0.isImage && !$0.isFile }).count >= 2 {
                            Button(action: {
                                let items = selectedItems
                                selectedIds.removeAll()
                                onMerge?(items)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.merge")
                                        .font(.system(size: 11))
                                    Text("Merge")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.badgeFill, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

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
        .overlay {
            // Save as snippet editor overlay
            if showSaveSnippetEditor {
                ZStack {
                    Color.black.opacity(0.3)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous))
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showSaveSnippetEditor = false
                            }
                        }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "text.quote")
                                .font(.system(size: 14))
                                .foregroundColor(.orange)
                            Text("Save as Snippet")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }

                        TextField("Snippet name", text: $saveSnippetTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))

                        ZStack(alignment: .topLeading) {
                            if saveSnippetContent.isEmpty {
                                Text("Content...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.metadataText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $saveSnippetContent)
                                .font(.system(size: 12))
                                .scrollContentBackground(.hidden)
                                .padding(6)
                        }
                        .frame(minHeight: 80, maxHeight: 140)
                        .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))

                        HStack(spacing: 8) {
                            Spacer()
                            Button("Cancel") {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showSaveSnippetEditor = false
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                            Button("Save Snippet") {
                                let title = saveSnippetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                let content = saveSnippetContent.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !content.isEmpty else { return }
                                let finalTitle = title.isEmpty ? String(content.prefix(50)) : title
                                manager.addSnippet(title: finalTitle, content: content)
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showSaveSnippetEditor = false
                                }
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    snippetSavedFlash = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        snippetSavedFlash = false
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.accentColor, in: Capsule())
                            .disabled(saveSnippetContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.windowBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.cardBorder, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 4)
                    .padding(24)
                }
                .transition(.opacity)
            }

            // Edit snippet overlay
            if editingSnippetId != nil {
                ZStack {
                    Color.black.opacity(0.3)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous))
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                editingSnippetId = nil
                            }
                        }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "pencil")
                                .font(.system(size: 14))
                                .foregroundColor(.orange)
                            Text("Edit Snippet")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }

                        TextField("Snippet name", text: $editSnippetTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))

                        ZStack(alignment: .topLeading) {
                            if editSnippetContent.isEmpty {
                                Text("Content...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.metadataText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $editSnippetContent)
                                .font(.system(size: 12))
                                .scrollContentBackground(.hidden)
                                .padding(6)
                        }
                        .frame(minHeight: 80, maxHeight: 140)
                        .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))

                        HStack(spacing: 8) {
                            Spacer()
                            Button("Cancel") {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    editingSnippetId = nil
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                            Button("Save") {
                                if let id = editingSnippetId {
                                    let title = editSnippetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let content = editSnippetContent.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !content.isEmpty else { return }
                                    let finalTitle = title.isEmpty ? String(content.prefix(50)) : title
                                    manager.updateSnippet(id: id, title: finalTitle, content: content)
                                }
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    editingSnippetId = nil
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.accentColor, in: Capsule())
                            .disabled(editSnippetContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.windowBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.cardBorder, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 4)
                    .padding(24)
                }
                .transition(.opacity)
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
        .onChange(of: navState.mergeTrigger) { _ in
            guard isMultiSelectMode else { return }
            let textItems = selectedItems.filter { !$0.isImage && !$0.isFile }
            guard textItems.count >= 2 else { return }
            selectedIds.removeAll()
            onMerge?(textItems)
        }
    }

    // MARK: - Tab Button

    @ViewBuilder
    func pickerTabButton(_ tab: PickerTab, icon: String, label: String) -> some View {
        let isActive = activeTab == tab
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeTab = tab
                searchText = ""
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: isActive ? .semibold : .medium))
            }
            .foregroundStyle(isActive ? Color.white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? Color.accentColor : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Appearance Toggle

    private var appearanceIconName: String {
        switch manager.appearanceMode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    private var appearanceTooltip: String {
        switch manager.appearanceMode {
        case .system: return "Theme: System"
        case .light: return "Theme: Light"
        case .dark: return "Theme: Dark"
        }
    }

    private var appearanceToggleButton: some View {
        Button(action: {
            let modes: [AppearanceMode] = [.system, .light, .dark]
            if let idx = modes.firstIndex(of: manager.appearanceMode) {
                manager.appearanceMode = modes[(idx + 1) % modes.count]
            } else {
                manager.appearanceMode = .system
            }
            manager.saveSettings()
            manager.applyAppearance()
        }) {
            Image(systemName: appearanceIconName)
                .font(.system(size: 14))
                .foregroundStyle(manager.appearanceMode == .system ? Color.secondary : Color.accentColor)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(appearanceTooltip)
    }

    // MARK: - Clipboard Tab Content

    var clipboardContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Theme.Spacing.itemGap) {
                    // Pinned section (temporary quick pins)
                    if !filteredPins.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .rotationEffect(.degrees(45))
                            Text("Pinned")
                                .font(.system(size: 11, weight: .medium))

                            Spacer()

                            Text("\(filteredPins.count)")
                                .font(Theme.Typography.metadata)
                                .foregroundStyle(Theme.metadataText)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.top, 2)

                        ForEach(filteredPins) { pin in
                            QuickPinRow(
                                pin: pin,
                                onSelect: {
                                    onSelect(ClipboardItem(content: pin.content))
                                },
                                onUnpin: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        manager.unpinQuickPin(pin)
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
                                        if let pin = manager.quickPins.first(where: { $0.content == item.content }) {
                                            manager.unpinQuickPin(pin)
                                        }
                                    } else {
                                        manager.pinItem(content: item.content)
                                    }
                                }
                            },
                            onSaveSnippet: {
                                saveSnippetTitle = String(item.content.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
                                saveSnippetContent = item.content
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showSaveSnippetEditor = true
                                }
                            },
                            onPastePlain: {
                                onSelect(ClipboardItem(content: item.content))
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
    }

    // MARK: - Snippets Tab Content

    var snippetsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.Spacing.itemGap) {
                // Inline add form
                if isAddingSnippetInline {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Name", text: $inlineSnippetTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(8)
                            .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))

                        ZStack(alignment: .topLeading) {
                            if inlineSnippetContent.isEmpty {
                                Text("Content...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.metadataText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $inlineSnippetContent)
                                .font(.system(size: 12))
                                .scrollContentBackground(.hidden)
                                .padding(4)
                        }
                        .frame(minHeight: 50, maxHeight: 80)
                        .background(Theme.inputBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))

                        HStack(spacing: 6) {
                            Spacer()
                            Button("Cancel") {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isAddingSnippetInline = false
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                            Button("Save") {
                                let title = inlineSnippetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                let content = inlineSnippetContent.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !content.isEmpty else { return }
                                let finalTitle = title.isEmpty ? String(content.prefix(50)) : title
                                manager.addSnippet(title: finalTitle, content: content)
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isAddingSnippetInline = false
                                    inlineSnippetTitle = ""
                                    inlineSnippetContent = ""
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor, in: Capsule())
                            .disabled(inlineSnippetContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .fill(Theme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ForEach(filteredSnippets) { snippet in
                    SnippetRow(
                        snippet: snippet,
                        onSelect: {
                            onSelect(ClipboardItem(content: snippet.content))
                        },
                        onEdit: {
                            editSnippetTitle = snippet.title
                            editSnippetContent = snippet.content
                            withAnimation(.easeInOut(duration: 0.2)) {
                                editingSnippetId = snippet.id
                            }
                        },
                        onRemove: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                manager.removeSnippet(snippet)
                            }
                        }
                    )
                }

                // Add button
                if !isAddingSnippetInline {
                    Button(action: {
                        inlineSnippetTitle = ""
                        inlineSnippetContent = ""
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isAddingSnippetInline = true
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Add Snippet")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                    }
                    .buttonStyle(.plain)
                }

                if filteredSnippets.isEmpty && !manager.pinnedItems.isEmpty && !isAddingSnippetInline {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.metadataText)
                        Text("No matching snippets")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.metadataText)
                    }
                    .padding(.vertical, 24)
                } else if manager.pinnedItems.isEmpty && !isAddingSnippetInline {
                    VStack(spacing: 10) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.metadataText)
                        Text("No snippets yet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.subtleText)
                        Text("Tap + above or save from clipboard")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.metadataText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 32)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
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
    var onSaveSnippet: (() -> Void)? = nil
    var onPastePlain: (() -> Void)? = nil

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
                // Left color bar for images/files/merged
                if item.isMerged {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.mergedAccent.opacity(0.6))
                        .frame(width: 3)
                        .padding(.vertical, 2)
                        .padding(.trailing, 8)
                } else if item.isImage {
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
                            .help(isPinned ? "Unpin" : "Pin")

                        // Save as snippet
                        if let onSaveSnippet = onSaveSnippet {
                            actionButton(
                                icon: "text.quote",
                                color: .orange
                            ) { onSaveSnippet() }
                                .help("Save as Snippet")
                        }

                        // Paste as plain text
                        if let onPastePlain = onPastePlain {
                            actionButton(
                                icon: "doc.plaintext",
                                color: .secondary
                            ) { onPastePlain() }
                                .help("Paste as Plain Text")
                        }
                    }

                    actionButton(icon: "doc.on.doc", color: .secondary) { onSelect() }
                        .help("Paste")
                    actionButton(icon: "xmark", color: .secondary, fontSize: 10, fontWeight: .semibold) { onDelete() }
                        .help("Remove")
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
            if item.isMerged {
                HStack(spacing: 3) {
                    Image(systemName: "link")
                        .font(.system(size: 8, weight: .semibold))
                    Text("Merged \(item.mergedCount)")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(Theme.mergedAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.mergedBadgeBackground, in: Capsule())
                Text("\u{00B7}").foregroundStyle(Theme.metadataText)
            }
            if let extra = extra {
                Text(extra)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.metadataText)
                Text("\u{00B7}").foregroundStyle(Theme.metadataText)
            }
            if let source = item.sourceApp, !item.isMerged {
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


// MARK: - Quick Pin Row (temporary pin)

struct QuickPinRow: View {
    let pin: QuickPin
    var onSelect: () -> Void
    var onUnpin: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
                .rotationEffect(.degrees(45))

            Text(String(pin.content.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines))
                .font(Theme.Typography.body)
                .lineLimit(1)
                .foregroundColor(.primary)
                .help(pin.content.count > 50 ? String(pin.content.prefix(500)) : "")

            Spacer()

            if isHovered {
                Image(systemName: "pin.slash.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                            .fill(Theme.badgeFill)
                    )
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded { onUnpin() })
                    .help("Unpin")
                    .padding(.trailing, 2)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Spacing.rowHorizontal)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(isHovered ? Theme.rowHover : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
        .onDrag {
            NSItemProvider(object: pin.content as NSString)
        }
    }
}

// MARK: - Snippet Row (permanent named template)

struct SnippetRow: View {
    let snippet: PinnedSnippet
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.quote")
                .font(.system(size: 11))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(snippet.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                if snippet.title != String(snippet.content.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines) {
                    Text(String(snippet.content.prefix(60)))
                        .font(Theme.Typography.caption)
                        .lineLimit(1)
                        .foregroundStyle(Theme.metadataText)
                }
            }
            .help(snippet.content.count > 50 ? String(snippet.content.prefix(500)) : "")

            Spacer()

            if isHovered {
                HStack(spacing: 4) {
                    snippetActionButton(icon: "pencil", color: .orange) { onEdit() }
                        .help("Edit Snippet")
                    snippetActionButton(icon: "xmark", color: .secondary, fontSize: 10, fontWeight: .semibold) { onRemove() }
                        .help("Remove")
                }
                .padding(.trailing, 2)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Spacing.rowHorizontal)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(isHovered ? Theme.rowHover : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
        .onDrag {
            NSItemProvider(object: snippet.content as NSString)
        }
    }

    @ViewBuilder
    func snippetActionButton(
        icon: String,
        color: Color,
        fontSize: CGFloat = 12,
        fontWeight: Font.Weight = .regular,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: icon)
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundColor(color)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                    .fill(Theme.badgeFill)
            )
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded { action() })
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
