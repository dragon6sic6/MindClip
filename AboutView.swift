import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(nsImage: NSImage.appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .padding(.bottom, 4)

            Text("MindClip")
                .font(.system(size: 20, weight: .bold))

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)

            Text("by Mindact")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.metadataText)

            Spacer()

            Divider().opacity(0.3)

            Text("A lightweight clipboard manager for macOS.")
                .font(Theme.Typography.settingsDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button(action: {
                NotificationCenter.default.post(name: .showQuickGuide, object: nil)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("How to Use")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .frame(width: 300, height: 280)
        .background(Color(.windowBackgroundColor))
    }
}
