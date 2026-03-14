import SwiftUI

struct QuickGuideView: View {
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            // App icon
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            Spacer().frame(height: 20)

            // Headline
            Text("One shortcut. Two superpowers.")
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)

            Spacer().frame(height: 32)

            // Cards
            VStack(spacing: 10) {
                // Tap card — subdued, "you already know this"
                HStack(spacing: 16) {
                    keyCombo(highlight: false)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tap")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Pastes normally — business as usual.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.metadataText)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
                )

                // Hold card — the hero
                HStack(spacing: 16) {
                    keyCombo(highlight: true)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("Hold")
                                .font(.system(size: 16, weight: .bold))
                            Text("  for 1 second")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text("Opens the picker — browse and paste\nfrom your clipboard history.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Color.accentColor.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1.5)
                )
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 28)

            // Tagline
            Text("That's it. Hold for a second and the magic happens.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.metadataText)
                .multilineTextAlignment(.center)

            Spacer()

            // Dismiss button
            Button(action: { onDismiss?() }) {
                Text("Got it")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 14)

            Text("by Mindact")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
                .padding(.bottom, 16)
        }
        .frame(width: 440, height: 520)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Keyboard Key Combo (⌘ + V as separate keys)

    @ViewBuilder
    func keyCombo(highlight: Bool) -> some View {
        HStack(spacing: 5) {
            macKey("⌘", highlight: highlight)
            Text("+")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(highlight ? .secondary : Theme.metadataText)
            macKey("V", highlight: highlight)
        }
    }

    @ViewBuilder
    func macKey(_ label: String, highlight: Bool) -> some View {
        let keyColor: Color = highlight
            ? Color(nsColor: NSColor(white: 0.15, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.25, alpha: 1.0))
        let borderColor: Color = highlight
            ? Color(nsColor: NSColor(white: 0.30, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.35, alpha: 1.0))
        let textColor: Color = highlight ? .white : Color(nsColor: NSColor(white: 0.85, alpha: 1.0))

        Text(label)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundColor(textColor)
            .frame(width: 36, height: 36)
            .background(
                ZStack {
                    // Bottom shadow layer (3D depth)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.black.opacity(0.5))
                        .offset(y: 1.5)

                    // Main key surface
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    keyColor.opacity(1.0),
                                    keyColor.opacity(0.85)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Top highlight
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    borderColor.opacity(0.8),
                                    borderColor.opacity(0.3)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
            )
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
    }
}
