import SwiftUI
import ServiceManagement
import Sparkle

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable {
    case general, picker, history, shortcuts, updates, about

    var label: String {
        switch self {
        case .general: return "General"
        case .picker: return "Picker"
        case .history: return "History"
        case .shortcuts: return "Shortcuts"
        case .updates: return "Updates"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .picker: return "rectangle.on.rectangle"
        case .history: return "clock.arrow.circlepath"
        case .shortcuts: return "keyboard"
        case .updates: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject private var manager = ClipboardManager.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var selectedDuration: DurationOption = .thirtyMinutes
    @State private var customMinutes: Int = 30
    @State private var showClearHistoryConfirm = false
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    enum DurationOption: CaseIterable {
        case fifteenMinutes, thirtyMinutes, oneHour, twoHours, untilQuit, custom

        var label: String {
            switch self {
            case .fifteenMinutes: return "15 min"
            case .thirtyMinutes: return "30 min"
            case .oneHour: return "1 hour"
            case .twoHours: return "2 hours"
            case .untilQuit: return "Forever"
            case .custom: return "Custom"
            }
        }

        var seconds: TimeInterval {
            switch self {
            case .fifteenMinutes: return 900
            case .thirtyMinutes: return 1800
            case .oneHour: return 3600
            case .twoHours: return 7200
            case .untilQuit: return 0
            case .custom: return 0
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: Sidebar
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    sidebarItem(tab)
                }
                Spacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .frame(width: 170)
            .background(Theme.cardBackground)

            // Divider
            Rectangle()
                .fill(Theme.separator)
                .frame(width: 1)

            // MARK: Content Pane
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    switch selectedTab {
                    case .general: generalContent()
                    case .picker: pickerContent()
                    case .history: historyContent()
                    case .shortcuts: shortcutsContent()
                    case .updates: updatesContent()
                    case .about: aboutContent()
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 560, minHeight: 440)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            let current = manager.sessionDuration
            if let match = DurationOption.allCases.first(where: { $0.seconds == current && $0 != .custom }) {
                selectedDuration = match
            } else if current == 0 {
                selectedDuration = .untilQuit
            } else {
                selectedDuration = .custom
                customMinutes = Int(current / 60)
            }
        }
    }

    // MARK: - Sidebar Item

    @ViewBuilder
    func sidebarItem(_ tab: SettingsTab) -> some View {
        let isActive = selectedTab == tab
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                    .frame(width: 20, alignment: .center)

                Text(tab.label)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .foregroundColor(isActive ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(isActive ? Theme.rowHover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - General Tab

    @ViewBuilder
    func generalContent() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Appearance")
            settingsRow {
                Text("Theme")
                    .font(Theme.Typography.settingsLabel)
                Spacer()
                Picker("", selection: Binding(
                    get: { manager.appearanceMode },
                    set: {
                        manager.appearanceMode = $0
                        manager.saveSettings()
                        manager.applyAppearance()
                    }
                )) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
        .themeCard()

        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Startup")
            settingsRow {
                Text("Launch at Login")
                    .font(Theme.Typography.settingsLabel)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            NSLog("MindClip: Launch at login error: \(error)")
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .themeCard()
    }

    // MARK: - Picker Tab

    @ViewBuilder
    func pickerContent() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Session Duration")

            Text("Hold ⌘V to browse and paste from recent copies.")
                .font(Theme.Typography.settingsDescription)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.metadataText)
                Text("Auto-clear after")
                    .font(Theme.Typography.settingsDescription)
                    .foregroundStyle(.secondary)
            }

            let columns = [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(DurationOption.allCases, id: \.self) { option in
                    durationButton(option)
                }
            }

            if selectedDuration == .custom {
                customStepper()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().opacity(0.3)

            settingsRow {
                Text("Max items")
                    .font(Theme.Typography.settingsLabel)
                Spacer()
                stepperControl(
                    value: Binding(
                        get: { manager.maxRemember },
                        set: { manager.maxRemember = $0; manager.saveSettings() }
                    ),
                    range: 5...200,
                    step: 5,
                    label: "\(manager.maxRemember)"
                )
            }

            Divider().opacity(0.3)

            settingsRow {
                Text("Remove duplicates")
                    .font(Theme.Typography.settingsLabel)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { manager.removeDuplicates },
                    set: { manager.removeDuplicates = $0; manager.saveSettings() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Divider().opacity(0.3)

            HStack {
                Spacer()
                destructiveButton("Clear Session", icon: "trash") {
                    manager.clearAll()
                }
            }
        }
        .themeCard()
    }

    // MARK: - History Tab

    @ViewBuilder
    func historyContent() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Menu Bar History")

            Text("Long-term history in the menu bar. Persists across sessions and restarts.")
                .font(Theme.Typography.settingsDescription)
                .foregroundStyle(.secondary)

            settingsRow {
                Text("Keep history for")
                    .font(Theme.Typography.settingsLabel)
                Spacer()
                Picker("", selection: Binding(
                    get: { manager.menuBarRetention },
                    set: {
                        manager.menuBarRetention = $0
                        manager.saveSettings()
                        manager.saveMenuBarHistory()
                    }
                )) {
                    ForEach(MenuBarRetention.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }

            Divider().opacity(0.3)

            settingsRow {
                Text("Show in menu")
                    .font(Theme.Typography.settingsLabel)
                Spacer()
                stepperControl(
                    value: Binding(
                        get: { manager.displayInMenu },
                        set: { manager.displayInMenu = $0; manager.saveSettings() }
                    ),
                    range: 5...100,
                    step: 5,
                    label: "\(manager.displayInMenu)"
                )
            }

            Divider().opacity(0.3)

            HStack {
                Spacer()
                destructiveButton("Clear History", icon: "trash") {
                    showClearHistoryConfirm = true
                }
            }
            .alert("Clear Menu Bar History?", isPresented: $showClearHistoryConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    manager.clearMenuBarHistory()
                }
            } message: {
                Text("This will permanently delete all saved history. This cannot be undone.")
            }
        }
        .themeCard()
    }

    // MARK: - Shortcuts Tab

    @ViewBuilder
    func shortcutsContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Keyboard Shortcuts")

            VStack(spacing: 8) {
                shortcutRow(icon: "doc.on.doc", text: "Copy anything", shortcut: "⌘C")
                shortcutRow(icon: "list.clipboard", text: "Show picker", shortcut: "Hold ⌘V")
                shortcutRow(icon: "arrow.up.doc", text: "Paste item", shortcut: "Enter")
                shortcutRow(icon: "number", text: "Quick paste", shortcut: "1-9")
                shortcutRow(icon: "textformat", text: "Paste plain text", shortcut: "⇧⌘V")
                shortcutRow(icon: "arrow.up.arrow.down", text: "Navigate", shortcut: "↑↓")
                shortcutRow(icon: "checkmark.square", text: "Multi-select", shortcut: "⌘ Click")
                shortcutRow(icon: "checkmark.rectangle.stack", text: "Select all", shortcut: "⌘A")
                shortcutRow(icon: "arrow.up.doc.on.clipboard", text: "Paste selected", shortcut: "⌘ Enter")
                shortcutRow(icon: "escape", text: "Dismiss", shortcut: "Esc")
            }
        }
        .themeCard()
    }

    // MARK: - Updates Tab

    @ViewBuilder
    func updatesContent() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Software Updates")

            settingsRow {
                Text("Check for updates automatically")
                    .font(Theme.Typography.settingsLabel)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Divider().opacity(0.3)

            Text("MindClip checks for updates in the background. When a new version is available, a red badge appears on the menu bar icon.")
                .font(Theme.Typography.settingsDescription)
                .foregroundStyle(.secondary)
        }
        .themeCard()
    }

    // MARK: - About Tab

    @ViewBuilder
    func aboutContent() -> some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage.appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)

            VStack(spacing: 4) {
                Text("MindClip")
                    .font(.system(size: 20, weight: .bold))

                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Text("by Mindact")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.metadataText)

            Divider().opacity(0.3)

            Text("A lightweight clipboard manager for macOS.")
                .font(Theme.Typography.settingsDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .themeCard()
    }

    // MARK: - Shared Components

    @ViewBuilder
    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.header)
    }

    @ViewBuilder
    func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
        }
    }

    @ViewBuilder
    func destructiveButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.destructiveBackground)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Duration Button

    @ViewBuilder
    func durationButton(_ option: DurationOption) -> some View {
        let isSelected = selectedDuration == option
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDuration = option
            }
            if option != .custom {
                manager.updateSessionDuration(option.seconds)
            }
        }) {
            Text(option.label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Theme.badgeFill)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom Stepper

    @ViewBuilder
    func customStepper() -> some View {
        HStack(spacing: 8) {
            Text("Duration:")
                .font(Theme.Typography.settingsLabel)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                Button(action: {
                    if customMinutes > 5 { customMinutes -= 5 }
                    manager.updateSessionDuration(TimeInterval(customMinutes * 60))
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("\(customMinutes) min")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(width: 56)

                Button(action: {
                    if customMinutes < 480 { customMinutes += 5 }
                    manager.updateSessionDuration(TimeInterval(customMinutes * 60))
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.badgeFill)
            )

            Spacer()
        }
    }

    // MARK: - Stepper Control

    @ViewBuilder
    func stepperControl(value: Binding<Int>, range: ClosedRange<Int>, step: Int, label: String) -> some View {
        HStack(spacing: 0) {
            Button(action: {
                let newVal = value.wrappedValue - step
                if newVal >= range.lowerBound { value.wrappedValue = newVal }
            }) {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .frame(width: 36)

            Button(action: {
                let newVal = value.wrappedValue + step
                if newVal <= range.upperBound { value.wrappedValue = newVal }
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(Theme.badgeFill)
        )
    }

    // MARK: - Shortcut Row

    @ViewBuilder
    func shortcutRow(icon: String, text: String, shortcut: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)

            Text(text)
                .font(Theme.Typography.settingsLabel)
                .foregroundStyle(Theme.subtleText)

            Spacer()

            Text(shortcut)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                        .fill(Theme.badgeFill)
                )
        }
    }
}
