import SwiftUI
import AppKit
import ApplicationServices
import Combine

extension Notification.Name {
    static let openSettings = Notification.Name("MindClipOpenSettings")
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

    private var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )

        if trusted {
            startKeyboardMonitor()
            updateMenuStatus()
        } else {
            showAccessibilityAlert()
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "MindClip Needs Accessibility Permission"
        alert.informativeText = "MindClip needs Accessibility access to detect Cmd+V.\n\nFind MindClip in the list and toggle it ON."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }

        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Menu bar

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "MindClip")
            button.image?.isTemplate = true
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
                if item.isImage {
                    preview = item.preview
                } else {
                    preview = String(item.preview.prefix(60))
                        .replacingOccurrences(of: "\n", with: " ")
                }
                let menuEntry = NSMenuItem(
                    title: preview,
                    action: item.isImage ? nil : #selector(historyItemClicked(_:)),
                    keyEquivalent: index < 9 ? "\(index + 1)" : ""
                )
                menuEntry.target = self
                menuEntry.tag = index
                if !item.isImage {
                    if let source = item.sourceApp {
                        menuEntry.toolTip = "\(source) · \(item.textContent.prefix(200))"
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
            let settingsView = SettingsView()
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
        guard !item.isImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.textContent, forType: .string)
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
