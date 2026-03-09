import SwiftUI
import AppKit
import ApplicationServices
import Combine
import UniformTypeIdentifiers
import Sparkle

extension Notification.Name {
    static let openSettings = Notification.Name("MindClipOpenSettings")
}

extension NSImage {
    static var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSApp.applicationIconImage
    }
}

@main
struct MindClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var clipboardManager: ClipboardManager!
    var keyMonitor: KeyboardMonitor!
    var popoverWindow: PickerWindow?
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var welcomeWindow: NSWindow?
    private var historyItems: [NSMenuItem] = []
    private var accessibilityCheckTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let updaterController: SPUStandardUpdaterController

    override init() {
        // Register app icon under NSApplicationIcon name so Sparkle and system dialogs find it
        // (accessory apps don't get this automatically)
        let icon = NSImage.appIcon
        icon.setName(NSImage.applicationIconName)
        NSApp.applicationIconImage = icon
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }

    private var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Re-register app icon after setActivationPolicy (which may reset it)
        let icon = NSImage.appIcon
        icon.setName(NSImage.applicationIconName)
        NSApp.applicationIconImage = icon

        clipboardManager = ClipboardManager.shared
        setupMenuBar()

        // Rebuild menu whenever history changes so it's always fresh on click
        clipboardManager.$menuBarHistory
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)

        // Listen for settings open request from picker
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings), name: .openSettings, object: nil)

        if !hasCompletedOnboarding {
            showWelcome()
        } else {
            checkAccessibilityAndStart()
        }
    }

    // MARK: - Accessibility

    private func checkAccessibilityAndStart() {
        if AXIsProcessTrusted() {
            startKeyboardMonitor()
            updateMenuStatus()
        } else {
            // Silently poll — don't show extra dialogs (welcome view handles first launch)
            accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.accessibilityCheckTimer = nil
                    self?.startKeyboardMonitor()
                    self?.updateMenuStatus()
                }
            }
        }
    }

    private func startKeyboardMonitor() {
        keyMonitor = KeyboardMonitor(clipboardManager: clipboardManager)
        keyMonitor.onShowPicker = { [weak self] in self?.showPicker() }
        keyMonitor.onHidePicker = { [weak self] in self?.hidePicker() }
        keyMonitor.startMonitoring()
    }

    private func showAccessibilityAlert() {
        // Only used for non-first-launch scenarios (e.g. permission revoked)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: - Menu bar

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if let iconPath = Bundle.main.path(forResource: "menubar_icon", ofType: "png"),
               let icon = NSImage(contentsOfFile: iconPath) {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "MindClip")
                button.image?.isTemplate = true
            }
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(NSMenuItem(title: "MindClip", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let accessOK = AXIsProcessTrusted()
        let accessItem = NSMenuItem(
            title: accessOK ? "Accessibility: Enabled" : "Accessibility: NOT Enabled",
            action: accessOK ? nil : #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessItem.target = self
        menu.addItem(accessItem)

        let countItem = NSMenuItem(
            title: "History: \(ClipboardManager.shared.menuBarHistory.count) items",
            action: nil, keyEquivalent: ""
        )
        menu.addItem(countItem)

        menu.addItem(NSMenuItem.separator())

        // History submenu (reads from persistent menu bar history)
        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        let historySubmenu = NSMenu()
        let allHistory = ClipboardManager.shared.menuBarHistory
        let historySlice = Array(allHistory.prefix(ClipboardManager.shared.displayInMenu))
        if allHistory.isEmpty {
            let emptyItem = NSMenuItem(title: "No items yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historySubmenu.addItem(emptyItem)
        } else {
            for (index, item) in historySlice.enumerated() {
                let preview: String
                var itemIcon: NSImage? = nil
                let isScreenshot = item.isImage && item.filePath != nil
                if item.isImage && !isScreenshot {
                    preview = item.preview
                } else if isScreenshot, let name = item.fileName {
                    let dims = item.preview
                    preview = "\(name)  (\(dims))"
                    if let path = item.filePath {
                        itemIcon = NSWorkspace.shared.icon(forFile: path)
                    } else {
                        itemIcon = NSWorkspace.shared.icon(for: .png)
                    }
                } else if item.isFile, let name = item.fileName {
                    let sizeStr = item.fileSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                    preview = sizeStr != nil ? "\(name)  (\(sizeStr!))" : name
                    if let path = item.filePath {
                        itemIcon = NSWorkspace.shared.icon(forFile: path)
                    } else {
                        let ext = (name as NSString).pathExtension
                        if let utType = UTType(filenameExtension: ext) {
                            itemIcon = NSWorkspace.shared.icon(for: utType)
                        }
                    }
                } else {
                    preview = String(item.preview.prefix(60))
                        .replacingOccurrences(of: "\n", with: " ")
                }
                let menuEntry = NSMenuItem(
                    title: preview,
                    action: (item.isImage && !isScreenshot) ? nil : #selector(historyItemClicked(_:)),
                    keyEquivalent: index < 9 ? "\(index + 1)" : ""
                )
                if let icon = itemIcon {
                    icon.size = NSSize(width: 16, height: 16)
                    menuEntry.image = icon
                }
                menuEntry.target = self
                menuEntry.tag = index
                if isScreenshot, let path = item.filePath {
                    menuEntry.toolTip = "Screenshot\n\n\(path)"
                } else if item.isFile, let path = item.filePath {
                    if let source = item.sourceApp {
                        menuEntry.toolTip = "\(source)\n\n\(path)"
                    } else {
                        menuEntry.toolTip = path
                    }
                } else if !item.isImage {
                    let fullText = String(item.textContent.prefix(500))
                    if let source = item.sourceApp {
                        menuEntry.toolTip = "\(source)\n\n\(fullText)"
                    } else {
                        menuEntry.toolTip = fullText
                    }
                }
                historySubmenu.addItem(menuEntry)
            }
            historySubmenu.addItem(NSMenuItem.separator())

            // Retention submenu
            let retentionItem = NSMenuItem(title: "Keep History...", action: nil, keyEquivalent: "")
            let retentionSubmenu = NSMenu()
            for option in MenuBarRetention.allCases {
                let optionItem = NSMenuItem(
                    title: option.label,
                    action: #selector(setMenuBarRetention(_:)),
                    keyEquivalent: ""
                )
                optionItem.target = self
                optionItem.representedObject = option.rawValue
                if ClipboardManager.shared.menuBarRetention == option {
                    optionItem.state = .on
                }
                retentionSubmenu.addItem(optionItem)
            }
            retentionItem.submenu = retentionSubmenu
            historySubmenu.addItem(retentionItem)

            historySubmenu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            historySubmenu.addItem(clearItem)
        }
        historyItem.submenu = historySubmenu
        menu.addItem(historyItem)

        let aboutItem = NSMenuItem(title: "About MindClip", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        checkForUpdatesItem.target = updaterController
        menu.addItem(checkForUpdatesItem)

        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MindClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func updateMenuStatus() {
        rebuildMenu()
    }

    @objc func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView(updater: updaterController.updater)
            let hostingController = NSHostingController(rootView: settingsView)
            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "MindClip Settings"
            settingsWindow?.styleMask = [.titled, .closable, .resizable]
            settingsWindow?.setContentSize(NSSize(width: 400, height: 460))
            settingsWindow?.minSize = NSSize(width: 360, height: 420)
            settingsWindow?.isReleasedWhenClosed = false
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openAbout() {
        if aboutWindow == nil {
            let aboutView = AboutView()
            let hostingController = NSHostingController(rootView: aboutView)
            aboutWindow = NSWindow(contentViewController: hostingController)
            aboutWindow?.title = "About MindClip"
            aboutWindow?.styleMask = [.titled, .closable]
            aboutWindow?.setContentSize(NSSize(width: 300, height: 260))
            aboutWindow?.isReleasedWhenClosed = false
        }
        aboutWindow?.center()
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Welcome / Onboarding

    func showWelcome() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let welcomeView = WelcomeView {
            self.hasCompletedOnboarding = true
            self.welcomeWindow?.close()
            self.welcomeWindow = nil
            NSApp.setActivationPolicy(.accessory)
            self.checkAccessibilityAndStart()
        }
        let hostingController = NSHostingController(rootView: welcomeView)
        welcomeWindow = NSWindow(contentViewController: hostingController)
        welcomeWindow?.title = "Welcome to MindClip"
        welcomeWindow?.styleMask = [.titled, .closable]
        welcomeWindow?.setContentSize(NSSize(width: 400, height: 520))
        welcomeWindow?.isReleasedWhenClosed = false
        welcomeWindow?.center()
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }


    @objc func historyItemClicked(_ sender: NSMenuItem) {
        let index = sender.tag
        let history = ClipboardManager.shared.menuBarHistory
        guard index >= 0, index < history.count else { return }
        let item = history[index]
        let isScreenshot = item.isImage && item.filePath != nil
        guard !item.isImage || isScreenshot else { return }
        NSPasteboard.general.clearContents()
        if isScreenshot, let path = item.filePath {
            let url = URL(fileURLWithPath: path)
            NSPasteboard.general.writeObjects([url as NSURL])
        } else if item.isFile, let path = item.filePath {
            let url = URL(fileURLWithPath: path)
            NSPasteboard.general.writeObjects([url as NSURL])
        } else {
            NSPasteboard.general.setString(item.textContent, forType: .string)
        }
        // Update changeCount so poll doesn't re-add
        ClipboardManager.shared.updateChangeCount()

        // Auto-paste: send Cmd+V after a short delay for the menu to close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.keyMonitor.postSyntheticPaste()
        }
    }

    @objc func clearHistory() {
        ClipboardManager.shared.clearMenuBarHistory()
    }

    @objc func setMenuBarRetention(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let retention = MenuBarRetention(rawValue: rawValue) else { return }
        ClipboardManager.shared.menuBarRetention = retention
        ClipboardManager.shared.saveSettings()
        ClipboardManager.shared.saveMenuBarHistory()
    }

    // MARK: - Picker

    func showPicker() {
        guard ClipboardManager.shared.items.count > 0 else { return }

        if popoverWindow == nil {
            popoverWindow = PickerWindow()
            popoverWindow?.keyboardMonitor = keyMonitor
            popoverWindow?.onDismiss = { [weak self] in
                self?.keyMonitor.resetPickerState()
            }
        }
        popoverWindow?.showPicker()
    }

    func hidePicker() {
        popoverWindow?.hidePicker()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
}
