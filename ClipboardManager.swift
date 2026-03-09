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
    let isFile: Bool
    let filePath: String?
    let fileName: String?
    let fileSize: Int64?

    init(from item: ClipboardItem) {
        self.id = item.id
        self.textContent = item.content
        self.preview = item.preview
        self.sourceApp = item.sourceApp
        self.timestamp = item.timestamp
        self.isImage = item.isImage
        self.isFile = item.isFile
        self.filePath = item.fileURL?.path
        self.fileName = item.fileName
        self.fileSize = item.fileSize
    }

    // Codable: provide defaults for new fields missing from old data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        textContent = try container.decode(String.self, forKey: .textContent)
        preview = try container.decode(String.self, forKey: .preview)
        sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isImage = try container.decode(Bool.self, forKey: .isImage)
        isFile = try container.decodeIfPresent(Bool.self, forKey: .isFile) ?? false
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
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
    var isFile: Bool = false
    var fileURL: URL?
    var fileName: String?
    var fileSize: Int64?
    var fileIcon: NSImage?

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

    init(fileURL: URL, sourceApp: String? = nil) {
        self.id = UUID()
        self.isFile = true
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent
        self.content = fileURL.path
        self.preview = fileURL.lastPathComponent
        self.timestamp = Date()
        self.sourceApp = sourceApp

        // Get file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int64 {
            self.fileSize = size
        }

        // Get file icon from system
        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        icon.size = NSSize(width: 32, height: 32)
        self.fileIcon = icon
        self.thumbnail = icon
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

        // 1. Check for file URLs FIRST — Finder puts both public.file-url AND public.tiff
        //    (the file icon) on the pasteboard, so we must prioritize file URL detection.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            let imageExts: Set<String> = ["png", "jpg", "jpeg", "tiff", "heic", "gif", "bmp", "webp"]

            for url in urls {
                if imageExts.contains(url.pathExtension.lowercased()) {
                    // Image file — load the actual image
                    if let image = NSImage(contentsOf: url) {
                        let newItem = ClipboardItem(image: image, sourceApp: frontApp)
                        DispatchQueue.main.async {
                            if let top = self.items.first, top.isImage,
                               top.imageSize == image.size { return }
                            self.items.insert(newItem, at: 0)
                            self.addToMenuBarHistory(newItem)
                            if self.items.count > self.maxRemember {
                                self.items = Array(self.items.prefix(self.maxRemember))
                            }
                        }
                    }
                } else {
                    // Non-image file (PDF, ZIP, etc.)
                    let fileURL = url
                    DispatchQueue.main.async {
                        if let top = self.items.first, top.isFile, top.fileURL == fileURL { return }
                        let newItem = ClipboardItem(fileURL: fileURL, sourceApp: frontApp)
                        self.items.insert(newItem, at: 0)
                        self.addToMenuBarHistory(newItem)
                        if self.items.count > self.maxRemember {
                            self.items = Array(self.items.prefix(self.maxRemember))
                        }
                    }
                }
            }
            return
        }

        // 2. Check for image data (screenshots, in-app copies — no file URL involved)
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff, .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic")
        ]
        let hasImage = imageTypes.contains(where: { pb.data(forType: $0) != nil })

        if hasImage, let image = loadImageFromPasteboard(pb) {
            let newItem = ClipboardItem(image: image, sourceApp: frontApp)
            DispatchQueue.main.async {
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

        // 3. Text content
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

    private let filenamesPboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    func paste(item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if item.isFile, let url = item.fileURL {
            pb.writeObjects([url as NSURL])
            // Legacy filenames type — Chrome/web apps use this for proper filenames
            pb.addTypes([filenamesPboardType], owner: nil)
            pb.setPropertyList([url.path], forType: filenamesPboardType)
        } else if item.isImage, let image = item.image {
            pb.writeObjects([image])
        } else {
            pb.setString(item.content, forType: .string)
        }
        // Update changeCount so the poll doesn't re-add this item
        lastChangeCount = pb.changeCount
    }

    func pasteMultiple(items: [ClipboardItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()

        let textItems = items.filter { !$0.isImage && !$0.isFile }
        let imageItems = items.filter { $0.isImage }
        let fileItems = items.filter { $0.isFile }

        // ── Single-type fast paths ──────────────────────────────────

        if fileItems.count == items.count {
            // All files
            let urls = fileItems.compactMap { $0.fileURL as NSURL? }
            pb.writeObjects(urls)
            let paths = fileItems.compactMap { $0.fileURL?.path }
            pb.addTypes([filenamesPboardType], owner: nil)
            pb.setPropertyList(paths, forType: filenamesPboardType)
        }
        else if textItems.count == items.count {
            // All text
            pb.setString(textItems.map { $0.content }.joined(separator: "\n"), forType: .string)
        }
        else if imageItems.count == items.count {
            // All images
            pb.writeObjects(imageItems.compactMap { $0.image })
        }

        // ── Mixed content: unified RTFD + HTML approach ─────────────
        else {
            let plainText = textItems.map { $0.content }.joined(separator: "\n")

            // 1) Build RTFD with all items in selection order
            let attrStr = NSMutableAttributedString()
            for item in items {
                if item.isFile {
                    if let url = item.fileURL,
                       let wrapper = try? FileWrapper(url: url, options: .immediate) {
                        let attachment = NSTextAttachment(fileWrapper: wrapper)
                        attrStr.append(NSAttributedString(attachment: attachment))
                        attrStr.append(NSAttributedString(string: "\n"))
                    }
                } else if item.isImage, let image = item.image {
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    attrStr.append(NSAttributedString(attachment: attachment))
                    attrStr.append(NSAttributedString(string: "\n"))
                } else {
                    attrStr.append(NSAttributedString(string: item.content + "\n"))
                }
            }

            // 2) Build HTML (images + text; files are omitted from HTML)
            var html = "<html><head><meta charset=\"utf-8\"></head><body>"
            for item in items {
                if item.isImage, let image = item.image,
                   let tiffData = image.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    let base64 = pngData.base64EncodedString()
                    let w = Int(image.size.width)
                    let h = Int(image.size.height)
                    html += "<img src=\"data:image/png;base64,\(base64)\" width=\"\(w)\" height=\"\(h)\" /><br>"
                } else if !item.isImage && !item.isFile {
                    let escaped = item.content
                        .replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                        .replacingOccurrences(of: "\n", with: "<br>")
                    html += "<p style=\"margin:0\">\(escaped)</p>"
                }
            }
            html += "</body></html>"

            // 3) Declare all types we provide
            var types: [NSPasteboard.PasteboardType] = [.rtfd, .html, .string]
            if fileItems.count == 1 {
                types.append(NSPasteboard.PasteboardType("public.file-url"))
            }
            if !fileItems.isEmpty {
                types.append(filenamesPboardType)
            }
            pb.declareTypes(types, owner: nil)

            // 4) Set data for each type
            if let rtfdData = attrStr.rtfd(from: NSRange(location: 0, length: attrStr.length),
                                           documentAttributes: [:]) {
                pb.setData(rtfdData, forType: .rtfd)
            }
            if let htmlData = html.data(using: .utf8) {
                pb.setData(htmlData, forType: .html)
            }
            pb.setString(plainText, forType: .string)
            if fileItems.count == 1, let url = fileItems.first?.fileURL {
                pb.setString(url.absoluteString, forType: NSPasteboard.PasteboardType("public.file-url"))
            }
            if !fileItems.isEmpty {
                let paths = fileItems.compactMap { $0.fileURL?.path }
                pb.setPropertyList(paths, forType: filenamesPboardType)
            }
        }

        lastChangeCount = pb.changeCount
    }

    func updateChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
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
                var newItem = ClipboardItem(image: image, sourceApp: "Screenshot")
                newItem.fileURL = fileURL
                newItem.fileName = fileURL.lastPathComponent
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
        // Skip clipboard images (no file path) — screenshots with paths are allowed
        guard !item.isImage || item.fileURL != nil else { return }

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
