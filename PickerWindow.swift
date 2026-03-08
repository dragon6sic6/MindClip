import AppKit
import SwiftUI

/// Borderless window that can become key and suppresses all beeps.
private class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func noResponder(for eventSelector: Selector) {}
    override func keyDown(with event: NSEvent) {
        // Swallow all key events to prevent system beep.
        // Actual handling is done via the local NSEvent monitor.
    }
}

class PickerWindow: NSObject {
    private var window: NSWindow?
    private var hostingView: NSHostingView<PickerView>?
    private var clickOutsideMonitor: Any?
    private var keyMonitorLocal: Any?
    private var previousApp: NSRunningApplication?
    private let navState = PickerNavState()

    /// Called whenever the picker is dismissed (by selection, click-outside, or escape).
    var onDismiss: (() -> Void)?

    /// Reference to the keyboard monitor so we can use its synthetic paste helper.
    var keyboardMonitor: KeyboardMonitor?

    override init() {
        super.init()
        setupWindow()
    }

    deinit {
        removeClickMonitor()
        removeKeyMonitor()
    }

    private func setupWindow() {
        let pickerView = PickerView(navState: navState, onSelect: { [weak self] item in
            self?.selectItem(item)
        }, onPasteMultiple: { [weak self] items in
            self?.selectMultipleItems(items)
        }, onDismiss: { [weak self] in
            self?.dismiss()
        }, onOpenSettings: {
            NotificationCenter.default.post(name: .openSettings, object: nil)
        })

        let hosting = NSHostingView(rootView: pickerView)
        self.hostingView = hosting

        let win = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        win.contentView = hosting
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .popUpMenu
        win.hasShadow = true
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        self.window = win
    }

    func showPicker() {
        // Save the app that was active before we steal focus
        previousApp = NSWorkspace.shared.frontmostApplication

        // Reset keyboard navigation
        navState.selectedIndex = 0

        // Recreate view with fresh state
        let pickerView = PickerView(navState: navState, onSelect: { [weak self] item in
            self?.selectItem(item)
        }, onPasteMultiple: { [weak self] items in
            self?.selectMultipleItems(items)
        }, onDismiss: { [weak self] in
            self?.dismiss()
        }, onOpenSettings: {
            NotificationCenter.default.post(name: .openSettings, object: nil)
        })
        hostingView?.rootView = pickerView

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let winWidth: CGFloat = 560
            let winHeight: CGFloat = min(CGFloat(ClipboardManager.shared.items.count) * 72 + 100, 500)
            let x = screenFrame.midX - winWidth / 2
            let y = screenFrame.midY - winHeight / 2
            window?.setFrame(NSRect(x: x, y: y, width: winWidth, height: winHeight), display: true)
        }

        window?.alphaValue = 0
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil) // Prevent search field auto-focus
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window?.animator().alphaValue = 1
        })

        // Dismiss on click outside
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let win = self.window, win.isVisible else { return }
            let clickLocation = NSEvent.mouseLocation
            if !win.frame.contains(clickLocation) {
                self.dismiss()
            }
        }

        // Local key monitor for keyboard navigation — swallow ALL key events
        // to prevent the system beep. Only pass through if a text field has focus.
        keyMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return nil }

            // If a text field has focus (search), let events through
            if let responder = self.window?.firstResponder, responder is NSTextView {
                if event.type == .keyDown && event.keyCode == 53 { // Escape still dismisses
                    self.dismiss()
                    return nil
                }
                // Allow ⌘A in search field
                if event.type == .keyDown && event.keyCode == 0 && event.modifierFlags.contains(.command) {
                    // Let ⌘A work as select-all in the text field
                    return event
                }
                return event
            }

            // Handle key actions, then swallow the event
            if event.type == .keyDown {
                self.handleLocalKey(event)
            }
            return nil
        }
    }

    private func handleLocalKey(_ event: NSEvent) {
        let itemCount = ClipboardManager.shared.items.count
        let hasCommand = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 53: // Escape
            // Async so monitor returns nil before monitor is removed
            DispatchQueue.main.async { [weak self] in self?.dismiss() }
        case 126: // Arrow Up
            navState.scrollOnChange = true
            navState.selectedIndex = max(0, navState.selectedIndex - 1)
        case 125: // Arrow Down
            navState.scrollOnChange = true
            navState.selectedIndex = min(max(0, itemCount - 1), navState.selectedIndex + 1)
        case 0: // A key
            if hasCommand {
                // ⌘A — select all
                navState.selectAllTrigger.toggle()
            }
        case 36: // Enter / Return
            if hasCommand {
                // ⌘Enter — paste selected items
                navState.pasteSelectedTrigger.toggle()
            } else {
                let idx = navState.selectedIndex
                DispatchQueue.main.async { [weak self] in self?.selectItemAtIndex(idx) }
            }
        default:
            // Number keys 1-9 quick-paste
            if let chars = event.charactersIgnoringModifiers, let num = Int(chars), num >= 1, num <= 9 {
                DispatchQueue.main.async { [weak self] in self?.selectItemAtIndex(num - 1) }
            }
        }
    }

    private func selectItemAtIndex(_ index: Int) {
        let items = ClipboardManager.shared.items
        guard index >= 0, index < items.count else { return }
        selectItem(items[index])
    }

    func hidePicker() {
        removeClickMonitor()
        removeKeyMonitor()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window?.animator().alphaValue = 0
        }, completionHandler: {
            self.window?.orderOut(nil)
        })
    }

    /// Dismiss the picker and notify the delegate (AppDelegate / KeyboardMonitor).
    func dismiss() {
        hidePicker()
        onDismiss?()
    }

    private func selectItem(_ item: ClipboardItem) {
        NSLog("MindClip: selectItem called — \(item.preview.prefix(40))")

        // 1. Copy to clipboard
        ClipboardManager.shared.paste(item: item)

        // 2. Close window immediately
        removeClickMonitor()
        removeKeyMonitor()
        window?.orderOut(nil)
        onDismiss?()

        // 3. Reactivate the previous app, then paste into it
        let appToActivate = previousApp
        previousApp = nil

        NSLog("MindClip: reactivating \(appToActivate?.localizedName ?? "nil")")
        appToActivate?.activate(options: .activateIgnoringOtherApps)

        // Give the app time to regain focus, then send Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            NSLog("MindClip: posting synthetic paste")
            self?.keyboardMonitor?.postSyntheticPaste()
        }

        // Show "Copied" toast as visual feedback
        showToast("Copied")
    }

    private func selectMultipleItems(_ items: [ClipboardItem]) {
        guard !items.isEmpty else { return }
        NSLog("MindClip: selectMultipleItems called — \(items.count) items")

        // 1. Copy all to clipboard
        ClipboardManager.shared.pasteMultiple(items: items)

        // 2. Close window immediately
        removeClickMonitor()
        removeKeyMonitor()
        window?.orderOut(nil)
        onDismiss?()

        // 3. Reactivate the previous app, then paste into it
        let appToActivate = previousApp
        previousApp = nil

        NSLog("MindClip: reactivating \(appToActivate?.localizedName ?? "nil")")
        appToActivate?.activate(options: .activateIgnoringOtherApps)

        // Give the app time to regain focus, then send Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            NSLog("MindClip: posting synthetic paste")
            self?.keyboardMonitor?.postSyntheticPaste()
        }

        // Show toast
        showToast("Pasted \(items.count) items")
    }

    private var toastWindow: NSWindow?

    private func showToast(_ message: String) {
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        let padding: CGFloat = 24
        let width = label.frame.width + padding * 2
        let height: CGFloat = 36

        let toast = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.level = .popUpMenu
        toast.hasShadow = true
        toast.ignoresMouseEvents = true

        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = height / 2
        bg.layer?.masksToBounds = true

        label.frame = NSRect(x: padding, y: (height - label.frame.height) / 2, width: label.frame.width, height: label.frame.height)
        bg.addSubview(label)
        toast.contentView = bg

        if let screen = NSScreen.main {
            let x = screen.frame.midX - width / 2
            let y = screen.frame.midY - 80
            toast.setFrameOrigin(NSPoint(x: x, y: y))
        }

        toast.alphaValue = 0
        toast.orderFrontRegardless()
        toastWindow = toast

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            toast.animator().alphaValue = 1
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                toast.animator().alphaValue = 0
            }, completionHandler: {
                toast.orderOut(nil)
                self?.toastWindow = nil
            })
        }
    }

    private func removeClickMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitorLocal {
            NSEvent.removeMonitor(monitor)
            keyMonitorLocal = nil
        }
    }
}
