import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
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
