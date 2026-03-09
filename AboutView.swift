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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("by Mindact")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            Spacer()

            Divider().opacity(0.3)

            Text("A lightweight clipboard manager for macOS.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .frame(width: 300, height: 260)
        .background(Color(.windowBackgroundColor))
    }
}
