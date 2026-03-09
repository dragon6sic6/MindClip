# MindClip

A lightweight clipboard manager for macOS. Copy things, pick from your history, paste faster.

Built by **Mindact**.

---

## How It Works

1. **Copy as usual** - MindClip runs in the menu bar and quietly saves everything you copy with `⌘C`.
2. **Hold ⌘V to pick** - Tap `⌘V` to paste normally. Hold it down to open a picker overlay showing your clipboard history.
3. **Click to paste** - Select any item from the picker and it gets pasted instantly.

## Features

- **Clipboard history** - Remembers up to 200 copied items (text, images, and files) per session
- **File support** - Copied files (PDFs, documents, archives, etc.) appear in the picker with native macOS icons
- **Multi-select paste** - Select multiple items in the picker and paste them together (text + files + images)
- **Screenshot capture** - Automatically detects new screenshots (⌘⇧4 / ⌘⇧3) and adds them to history
- **Image support** - Copies of images, screenshots, and photos all appear in the picker with thumbnails
- **Quick picker** - Hold `⌘V` to browse and select from history
- **Pinned favorites** - Pin frequently used snippets so they persist across sessions
- **Drag & drop** - Drag any item from the picker directly into another app
- **Keyboard navigation** - Arrow keys to navigate, Enter to paste, 1-9 for quick paste
- **Paste as plain text** - `⇧⌘V` strips formatting and pastes clean text
- **Search** - Toggle search in the picker to filter items
- **Smart duplicates** - Optionally removes duplicate entries automatically
- **Session duration** - Picker auto-clears after a set time (15 min to forever)
- **Persistent menu bar history** - Long-term history with native file type icons, including screenshots and files
- **Retention settings** - Keep menu bar history for 7 days, 30 days, 90 days, or forever
- **Source app labels** - See which app you copied from, with relative timestamps
- **Appearance mode** - System, Light, or Dark — the picker and settings follow your choice
- **Quick settings** - Access settings directly from the picker via the gear icon
- **Launch at login** - Optional auto-start when you log in
- **Lightweight** - No dock icon, no background noise, just a menu bar icon

## Install

1. Download **MindClip.dmg** from [Releases](https://github.com/dragon6sic6/MindClip/releases) (or build from source)
2. Open the DMG and drag **MindClip.app** to your Applications folder
3. Open MindClip
4. Grant **Accessibility** permission when prompted (required for `⌘V` detection)

> Signed and notarized by Apple (Developer ID: Mindact Solutions AB).

> **Note:** macOS requires you to manually enable Accessibility access in **System Settings > Privacy & Security > Accessibility**. Toggle MindClip ON.

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Copy to history | `⌘C` (works everywhere) |
| Open picker | Hold `⌘V` |
| Paste selected item | Enter or click |
| Quick paste | `1` - `9` (while picker is open) |
| Paste as plain text | `⇧⌘V` |
| Navigate items | `↑` `↓` |
| Dismiss picker | `Esc` |

## Settings

Access settings from the menu bar icon > **Settings...** (`⌘,`):

**Picker** - Controls the ⌘V picker overlay
- **Auto-clear after** - Session duration (15 min, 30 min, 1 hour, 2 hours, forever, or custom)
- **Max items** - Maximum items to keep in the picker (5-200)
- **Remove duplicates** - Automatically remove older copies of the same text

**Menu Bar History** - Long-term history that persists across sessions and restarts
- **Keep history for** - Retention period (7 days, 30 days, 90 days, or forever)
- **Show in menu** - How many items to display in the History submenu (5-100)

**General**
- **Appearance** - System, Light, or Dark mode
- **Launch at Login** - Start MindClip automatically when you log in

## Architecture

```
MindClipApp.swift       - App entry, menu bar, window management
ClipboardManager.swift  - Clipboard polling, dual history, settings persistence
KeyboardMonitor.swift   - Global ⌘V intercept via NSEvent monitors
PickerWindow.swift      - Borderless NSWindow hosting the floating picker
PickerView.swift        - SwiftUI picker overlay
HistoryView.swift       - History tab in settings
SettingsView.swift      - Card-based settings UI
WelcomeView.swift       - First-launch onboarding
AboutView.swift         - About window
```

## Build from Source

Requires Xcode 15+ and macOS 13+.

```bash
git clone https://github.com/dragon6sic6/MindClip.git
cd MindClip
xcodebuild -scheme MindClip -configuration Release
```

To build a Universal Binary (Apple Silicon + Intel):

```bash
xcodebuild -scheme MindClip -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
```

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission

## License

MIT
