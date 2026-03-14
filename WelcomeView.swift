import SwiftUI

struct WelcomeView: View {
    var onGetStarted: () -> Void

    @State private var waitingForPermission = false
    @State private var permissionGranted = false
    @State private var showGuide = false
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            if showGuide {
                // MARK: - Quick Guide
                QuickGuideView(onDismiss: { onGetStarted() })
            } else if permissionGranted {
                // MARK: - All set
                readyContent
            } else if waitingForPermission {
                // MARK: - Waiting for permission
                waitingContent
            } else {
                // MARK: - Welcome
                welcomeContent
            }
        }
        .frame(width: 400, height: 480)
        .background(Color(.windowBackgroundColor))
        .onDisappear { pollTimer?.invalidate() }
    }

    // MARK: - Welcome (step 1)

    private var welcomeContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 80, height: 80)
                } else {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.accentColor)
                }

                Text("Welcome to MindClip")
                    .font(.system(size: 22, weight: .bold))

                Text("A lightweight clipboard manager for macOS")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 36)
            .padding(.bottom, 28)

            VStack(spacing: 0) {
                stepRow(
                    number: 1,
                    icon: "doc.on.doc",
                    title: "Copy as usual",
                    description: "MindClip quietly saves everything you copy with ⌘C.",
                    isLast: false
                )
                stepRow(
                    number: 2,
                    icon: "hand.tap",
                    title: "Hold ⌘V to pick",
                    description: "Tap ⌘V to paste normally. Hold it to open the picker.",
                    isLast: false
                )
                stepRow(
                    number: 3,
                    icon: "lock.shield",
                    title: "Grant Accessibility",
                    description: "MindClip needs Accessibility permission to detect ⌘V.",
                    isLast: true
                )
            }
            .padding(.horizontal, 28)

            Spacer()

            Button(action: requestPermission) {
                Text("Get Started")
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
            .padding(.horizontal, 28)
            .padding(.bottom, 12)

            Text("by Mindact")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Waiting for permission (step 2)

    private var waitingContent: some View {
        VStack(spacing: 20) {
            Spacer()

            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
            }

            Text("Enable Accessibility")
                .font(.system(size: 20, weight: .bold))

            VStack(spacing: 12) {
                instructionRow(number: 1, text: "System Settings is opening...")
                instructionRow(number: 2, text: "Find **MindClip** in the list")
                instructionRow(number: 3, text: "Toggle it **ON**")
            }
            .padding(.horizontal, 40)

            ProgressView()
                .scaleEffect(0.8)
                .padding(.top, 8)

            Text("Waiting for permission...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: openSystemSettings) {
                Text("Open System Settings Again")
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
    }

    // MARK: - All set (step 3) — brief checkmark, then guide

    private var readyContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("You're all set!")
                .font(.system(size: 22, weight: .bold))

            Text("MindClip is running in your menu bar.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showGuide = true
                }
            }
        }
    }

    // MARK: - Actions

    private func requestPermission() {
        // Trigger the macOS system permission prompt
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )

        if trusted {
            // Already granted (e.g. re-install) — skip straight to guide
            withAnimation(.easeInOut(duration: 0.3)) {
                showGuide = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                waitingForPermission = true
            }
            startPolling()
        }
    }

    private func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                withAnimation(.easeInOut(duration: 0.3)) {
                    permissionGranted = true
                }
            }
        }
    }

    // MARK: - UI helpers

    @ViewBuilder
    func stepRow(number: Int, icon: String, title: String, description: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 28, height: 28)
                    Text("\(number)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 20)
        }
    }

    @ViewBuilder
    func instructionRow(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 26, height: 26)
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accentColor)
            }
            Text(LocalizedStringKey(text))
                .font(.system(size: 13))
            Spacer()
        }
    }
}
