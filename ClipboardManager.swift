import AppKit
import Combine

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Pinned Favorites (persistent across sessions)

struct PinnedSnippet: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String
    let createdAt: Date

    init(content: String) {
        self.id = UUID()
        self.title = String(content.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
        self.content = content
        self.createdAt = Date()
    }
}

// MARK: - Persistent History Item (for menu bar long-term history)

enum MenuBarRetention: String, CaseIterable, Codable {
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"
    case forever = "forever"

    var label: String {
        switch self {
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        case .ninetyDays: return "90 days"
        case .forever: return "Forever"
        }
    }
}

struct PersistentHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let textContent: String
    let preview: String
    let sourceApp: String?
    let timestamp: Date
    let isImage: Bool

    init(from item: ClipboardItem) {
        self.id = item.id
        self.textContent = item.content
        self.preview = item.preview
        self.sourceApp = item.sourceApp
        self.timestamp = item.timestamp
        self.isImage = item.isImage
    }
}

// MARK: - Clipboard Item

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let content: String
    let preview: String
    let timestamp: Date
    let sourceApp: String?
    var isImage: Bool = false
    var image: NSImage?
    var thumbnail: NSImage?
    var imageSize: NSSize?

    init(content: String, sourceApp: String? = nil) {
        self.id = UUID()
        self.content = content
        self.preview = String(content.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
        self.timestamp = Date()
        self.sourceApp = sourceApp
    }

    init(image: NSImage, sourceApp: String? = nil) {
        self.id = UUID()
        self.isImage = true
        self.image = image
        self.imageSize = image.size
        self.content = ""
        let w = Int(image.size.width)
        let h = Int(image.size.height)
        self.preview = "Image — \(w) × \(h)"
        self.timestamp = Date()
        self.sourceApp = sourceApp

        // Generate thumbnail (max 120pt on longest side)
        let maxThumb: CGFloat = 120
        let scale = min(maxThumb / image.size.width, maxThumb / image.size.height, 1.0)
        let thumbSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let thumb = NSImage(size: thumbSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        thumb.unlockFocus()
        self.thumbnail = thumb
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published var items: [ClipboardItem] = []
    @Published var pinnedItems: [PinnedSnippet] = []
    @Published var sessionDuration: TimeInterval = 1800 // 30 minutes default
    @Published var maxRemember: Int = 50
    @Published var displayInMenu: Int = 20
    @Published var removeDuplicates: Bool = true
    @Published var menuBarHistory: [PersistentHistoryItem] = []
    @Published var menuBarRetention: MenuBarRetention = .forever
    @Published var appearanceMode: AppearanceMode = .system

    private var lastChangeCount: Int = 0
    private var pollTimer: Timer?
    private var sessionTimer: Timer?
    private var screenshotTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadSettings()
        loadPinnedItems()
        loadMenuBarHistory()
        startPolling()
        startSessionTimer()
        startScreenshotMonitoring()
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        let duration = defaults.double(forKey: "sessionDuration")
        if duration > 0 { sessionDuration = duration }

        let remember = defaults.integer(forKey: "maxRemember")
        if remember > 0 { maxRemember = remember }

        let display = defaults.integer(forKey: "displayInMenu")
        if display > 0 { displayInMenu = display }

        if defaults.object(forKey: "removeDuplicates") != nil {
            removeDuplicates = defaults.bool(forKey: "removeDuplicates")
        }

        if let retentionStr = defaults.string(forKey: "menuBarRetention"),
           let retention = MenuBarRetention(rawValue: retentionStr) {
            menuBarRetention = retention
        }

        if let modeStr = defaults.string(forKey: "appearanceMode"),
           let mode = AppearanceMode(rawValue: modeStr) {
            appearanceMode = mode
        }
        applyAppearance()
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(sessionDuration, forKey: "sessionDuration")
        defaults.set(maxRemember, forKey: "maxRemember")
        defaults.set(displayInMenu, forKey: "displayInMenu")
        defaults.set(removeDuplicates, forKey: "removeDuplicates")
        defaults.set(menuBarRetention.rawValue, forKey: "menuBarRetention")
        defaults.set(appearanceMode.rawValue, forKey: "appearanceMode")
    }

    func applyAppearance() {
        NSApp.appearance = appearanceMode.nsAppearance
    }

    func startPolling() {
        pollTimer?.invalidate()
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        let pb = NSPasteboard.general
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName

        // Check for image first (tiff is universal, png for screenshots, also check JPEG)
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff, .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic")
        ]
        let hasImage = imageTypes.contains(where: { pb.data(forType: $0) != nil })

        // Also check for file URLs pointing to images (macOS screenshots sometimes use this)
        var imageFromFileURL: NSImage? = nil
        if !hasImage,
           let urlString = pb.string(forType: NSPasteboard.PasteboardType("public.file-url")),
           let url = URL(string: urlString) {
            let ext = url.pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "tiff", "heic"].contains(ext) {
                imageFromFileURL = NSImage(contentsOf: url)
            }
        }

        if let image = imageFromFileURL ?? (hasImage ? loadImageFromPasteboard(pb) : nil) {
            let newItem = ClipboardItem(image: image, sourceApp: frontApp)
            DispatchQueue.main.async {
                // Skip if the top item is already an image of the same size
                if let top = self.items.first, top.isImage,
                   top.imageSize == image.size { return }

                self.items.insert(newItem, at: 0)
                self.addToMenuBarHistory(newItem)

                if self.items.count > self.maxRemember {
                    self.items = Array(self.items.prefix(self.maxRemember))
                }
            }
            return
        }

        // Text content
        guard let content = pb.string(forType: .string),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let newItem = ClipboardItem(content: content, sourceApp: frontApp)

        DispatchQueue.main.async {
            // Avoid duplicates at the top
            if self.items.first?.content == content { return }

            // Remove duplicates if enabled (move to top)
            if self.removeDuplicates {
                self.items.removeAll { $0.content == content && !$0.isImage }
            }

            self.items.insert(newItem, at: 0)
            self.addToMenuBarHistory(newItem)

            // Trim to max remember limit
            if self.items.count > self.maxRemember {
                self.items = Array(self.items.prefix(self.maxRemember))
            }
        }
    }

    func paste(item: ClipboardItem) {
        NSPasteboard.general.clearContents()
        if item.isImage, let image = item.image {
            NSPasteboard.general.writeObjects([image])
        } else {
            NSPasteboard.general.setString(item.content, forType: .string)
        }
        // Update changeCount so the poll doesn't re-add this item
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func pasteMultiple(items: [ClipboardItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()

        let textItems = items.filter { !$0.isImage }
        let imageItems = items.filter { $0.isImage }

        if !textItems.isEmpty && imageItems.isEmpty {
            // Text only — join with newlines
            let combined = textItems.map { $0.content }.joined(separator: "\n")
            pb.setString(combined, forType: .string)
        } else if textItems.isEmpty && !imageItems.isEmpty {
            // Images only — write image(s)
            var objects: [NSPasteboardWriting] = []
            for item in imageItems {
                if let img = item.image { objects.append(img) }
            }
            pb.writeObjects(objects)
        } else {
            // Mixed text + images — build HTML with embedded base64 images
            var html = "<html><body>"
            for item in items {
                if item.isImage, let image = item.image,
                   let tiffData = image.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    let base64 = pngData.base64EncodedString()
                    let w = Int(image.size.width)
                    let h = Int(image.size.height)
                    html += "<img src=\"data:image/png;base64,\(base64)\" width=\"\(w)\" height=\"\(h)\" /><br>"
                } else if !item.isImage {
                    let escaped = item.content
                        .replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                        .replacingOccurrences(of: "\n", with: "<br>")
                    html += "<p style=\"margin:0\">\(escaped)</p>"
                }
            }
            html += "</body></html>"

            pb.declareTypes([.html, .string], owner: nil)
            if let htmlData = html.data(using: .utf8) {
                pb.setData(htmlData, forType: .html)
            }
            // Plain text fallback
            let plainText = textItems.map { $0.content }.joined(separator: "\n")
            pb.setString(plainText, forType: .string)
        }

        lastChangeCount = pb.changeCount
    }

    func stripFormattingFromClipboard() {
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string) else { return }
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount
    }

    func remove(item: ClipboardItem) {
        DispatchQueue.main.async {
            self.items.removeAll { $0.id == item.id }
        }
    }

    func clearAll() {
        DispatchQueue.main.async {
            self.items.removeAll()
        }
        resetSessionTimer()
    }

    func startSessionTimer() {
        sessionTimer?.invalidate()
        guard sessionDuration > 0 else { return }
        let timer = Timer(timeInterval: sessionDuration, repeats: false) { [weak self] _ in
            self?.clearAll()
        }
        RunLoop.main.add(timer, forMode: .common)
        sessionTimer = timer
    }

    func resetSessionTimer() {
        startSessionTimer()
    }

    func updateSessionDuration(_ duration: TimeInterval) {
        sessionDuration = duration
        saveSettings()
        startSessionTimer()
    }

    private func loadImageFromPasteboard(_ pb: NSPasteboard) -> NSImage? {
        if let data = pb.data(forType: .tiff) ?? pb.data(forType: .png)
                    ?? pb.data(forType: NSPasteboard.PasteboardType("public.jpeg"))
                    ?? pb.data(forType: NSPasteboard.PasteboardType("public.heic")) {
            return NSImage(data: data)
        }
        return nil
    }

    // MARK: - Screenshot Directory Monitoring

    private func screenshotSaveLocation() -> URL {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    func startScreenshotMonitoring() {
        screenshotTimer?.invalidate()

        // Create marker file — `find -newer` will compare against this file's modification time.
        // Only files NEWER than the marker are returned, so we never scan old files.
        let marker = screenshotMarkerPath
        let supportDir = (marker as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marker, contents: nil)

        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                self?.checkForNewScreenshots()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        screenshotTimer = timer
    }

    private var screenshotMarkerPath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("MindClip/.screenshot_marker").path
    }

    private func checkForNewScreenshots() {
        let dir = screenshotSaveLocation()
        let marker = screenshotMarkerPath

        guard FileManager.default.fileExists(atPath: marker) else { return }

        // `find -newer marker -print0` returns ONLY files newer than the marker.
        // -print0 uses null-byte separators — handles any filename encoding.
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.arguments = [
            dir.path, "-maxdepth", "1", "-type", "f",
            "(", "-name", "*.png", "-o", "-name", "*.jpg", "-o", "-name", "*.jpeg", "-o", "-name", "*.tiff", ")",
            "-newer", marker,
            "-print0"
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch { return }

        // CRITICAL: Read pipe data BEFORE waitUntilExit to avoid deadlock.
        // If find's output fills the pipe buffer (~64KB), waitUntilExit would
        // block forever waiting for find to finish, while find blocks waiting
        // for the pipe to drain.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // Update marker so next tick only finds newer files
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: marker
        )

        guard !data.isEmpty else { return }

        let paths = data.split(separator: 0).compactMap { String(data: Data($0), encoding: .utf8) }

        for path in paths {
            let fileURL = URL(fileURLWithPath: path)

            if let image = NSImage(contentsOf: fileURL) {
                let newItem = ClipboardItem(image: image, sourceApp: "Screenshot")
                DispatchQueue.main.async {
                    // Skip if top item is already same-size image
                    if let top = self.items.first, top.isImage,
                       top.imageSize == image.size { return }

                    self.items.insert(newItem, at: 0)
                    self.addToMenuBarHistory(newItem)
                    if self.items.count > self.maxRemember {
                        self.items = Array(self.items.prefix(self.maxRemember))
                    }
                }
            }
        }
    }

    // MARK: - Relative Time Helper

    static func relativeTime(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    // MARK: - Menu Bar History Persistence

    private var historyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MindClip")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("menuBarHistory.json")
    }

    func loadMenuBarHistory() {
        guard let data = try? Data(contentsOf: historyFileURL),
              let items = try? JSONDecoder().decode([PersistentHistoryItem].self, from: data) else { return }
        menuBarHistory = items
        applyMenuBarRetention()
    }

    func saveMenuBarHistory() {
        applyMenuBarRetention()
        guard let data = try? JSONEncoder().encode(menuBarHistory) else { return }
        try? data.write(to: historyFileURL, options: .atomic)
    }

    func addToMenuBarHistory(_ item: ClipboardItem) {
        // Skip images — only text is persisted in menu bar history
        guard !item.isImage else { return }

        let persistent = PersistentHistoryItem(from: item)

        if removeDuplicates {
            menuBarHistory.removeAll { $0.textContent == item.content }
        }

        menuBarHistory.insert(persistent, at: 0)
        saveMenuBarHistory()
    }

    func clearMenuBarHistory() {
        menuBarHistory.removeAll()
        saveMenuBarHistory()
    }

    private func applyMenuBarRetention() {
        switch menuBarRetention {
        case .sevenDays:
            menuBarHistory.removeAll { $0.timestamp < Date().addingTimeInterval(-7 * 24 * 3600) }
        case .thirtyDays:
            menuBarHistory.removeAll { $0.timestamp < Date().addingTimeInterval(-30 * 24 * 3600) }
        case .ninetyDays:
            menuBarHistory.removeAll { $0.timestamp < Date().addingTimeInterval(-90 * 24 * 3600) }
        case .forever:
            break
        }
        // Safety cap
        if menuBarHistory.count > 500 {
            menuBarHistory = Array(menuBarHistory.prefix(500))
        }
    }

    // MARK: - Pinned Favorites

    func loadPinnedItems() {
        guard let data = UserDefaults.standard.data(forKey: "pinnedItems"),
              let items = try? JSONDecoder().decode([PinnedSnippet].self, from: data) else { return }
        pinnedItems = items
    }

    func savePinnedItems() {
        guard let data = try? JSONEncoder().encode(pinnedItems) else { return }
        UserDefaults.standard.set(data, forKey: "pinnedItems")
    }

    func pinItem(content: String) {
        guard !pinnedItems.contains(where: { $0.content == content }) else { return }
        let snippet = PinnedSnippet(content: content)
        pinnedItems.insert(snippet, at: 0)
        savePinnedItems()
    }

    func unpinItem(_ snippet: PinnedSnippet) {
        pinnedItems.removeAll { $0.id == snippet.id }
        savePinnedItems()
    }

    func isPinned(content: String) -> Bool {
        pinnedItems.contains { $0.content == content }
    }
}
