import SwiftUI

struct HistoryView: View {
    @ObservedObject private var manager = ClipboardManager.shared
    @State private var searchText = ""
    @State private var hoveredId: UUID? = nil

    var filteredItems: [ClipboardItem] {
        if searchText.isEmpty { return manager.items }
        return manager.items.filter { $0.preview.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 10) {
                // Search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.metadataText)
                    TextField("Search history...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(Theme.Typography.body)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(Theme.inputBackground)
                )

                // Clear all
                Button(action: { manager.clearAll() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("Clear All")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                            .fill(Theme.destructiveBackground)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.5)

            // Items list
            if filteredItems.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: searchText.isEmpty ? "clipboard" : "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.metadataText)
                    Text(searchText.isEmpty ? "No items yet" : "No results")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.subtleText)
                    if searchText.isEmpty {
                        Text("Copy something to get started")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.metadataText)
                    }
                }
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredItems) { item in
                            HistoryRow(
                                item: item,
                                isHovered: hoveredId == item.id,
                                onCopy: {
                                    manager.paste(item: item)
                                },
                                onDelete: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        manager.remove(item: item)
                                    }
                                }
                            )
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    hoveredId = hovering ? item.id : nil
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                // Footer
                HStack {
                    Text("\(filteredItems.count) item\(filteredItems.count == 1 ? "" : "s")")
                        .font(Theme.Typography.metadata)
                        .foregroundStyle(Theme.metadataText)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color(.windowBackgroundColor))
    }
}

struct HistoryRow: View {
    let item: ClipboardItem
    let isHovered: Bool
    var onCopy: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(item.preview)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .lineSpacing(1)
                    .foregroundStyle(.primary.opacity(isHovered ? 1.0 : 0.85))

                HStack(spacing: 6) {
                    if let source = item.sourceApp {
                        HStack(spacing: 3) {
                            Image(systemName: "app.fill")
                                .font(.system(size: 8))
                            Text(source)
                        }
                        .font(Theme.Typography.metadata)
                        .foregroundStyle(Theme.metadataText)
                    }

                    Text(item.timestamp, style: .relative)
                        .font(Theme.Typography.metadata)
                        .foregroundStyle(Theme.metadataText)
                }
            }

            Spacer()

            // Actions
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                                    .fill(Theme.badgeFill)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")

                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.metadataText)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous)
                                    .fill(Theme.badgeFill)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(isHovered ? Theme.rowHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onCopy() }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
