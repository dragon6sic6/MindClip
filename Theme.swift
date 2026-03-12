import SwiftUI
import AppKit

// MARK: - MindClip Theme System

enum Theme {

    // MARK: - Dynamic Colors (auto-adapt to light/dark)

    static let cardBackground = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.06)
            : NSColor(white: 0.0, alpha: 0.04)
    }))

    static let cardBorder = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.10)
            : NSColor(white: 0.0, alpha: 0.08)
    }))

    static let rowHover = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.12 : 0.08)
    }))

    static let rowSelected = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.20 : 0.14)
    }))

    static let subtleText = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.labelColor.withAlphaComponent(0.60)
            : NSColor.labelColor.withAlphaComponent(0.55)
    }))

    static let metadataText = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.labelColor.withAlphaComponent(0.45)
            : NSColor.labelColor.withAlphaComponent(0.40)
    }))

    static let separator = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.12)
            : NSColor(white: 0.0, alpha: 0.08)
    }))

    static let badgeFill = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.08)
            : NSColor(white: 0.0, alpha: 0.06)
    }))

    static let inputBackground = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.06)
            : NSColor(white: 0.0, alpha: 0.05)
    }))

    static let destructiveBackground = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.systemRed.withAlphaComponent(0.15)
            : NSColor.systemRed.withAlphaComponent(0.10)
    }))

    // MARK: - Corner Radii

    enum Radius {
        static let window: CGFloat = 20
        static let card: CGFloat = 12
        static let row: CGFloat = 10
        static let button: CGFloat = 8
        static let badge: CGFloat = 6
    }

    // MARK: - Spacing

    enum Spacing {
        static let cardPadding: CGFloat = 16
        static let sectionGap: CGFloat = 14
        static let rowVertical: CGFloat = 10
        static let rowHorizontal: CGFloat = 14
        static let itemGap: CGFloat = 4
    }

    // MARK: - Typography

    enum Typography {
        static let header = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 13)
        static let caption = Font.system(size: 11)
        static let metadata = Font.system(size: 10)
        static let badge = Font.system(size: 11, weight: .semibold, design: .rounded)
        static let settingsLabel = Font.system(size: 12)
        static let settingsDescription = Font.system(size: 11.5)
    }
}

// MARK: - Reusable View Modifiers

extension View {
    func themeCard() -> some View {
        self
            .padding(Theme.Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
    }
}
