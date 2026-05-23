import SwiftUI

// MARK: - @ mention menu
//
// Inline file-mention picker shown when the composer draft ends with an `@`
// token. Lists matching project files (fuzzy by name); selecting one inserts
// its path as a mention. Mirrors the slash-command menu's chrome. Backed by
// `ProjectFileIndex`, so it stays responsive in large repos.

struct MentionFileItem: Identifiable {
    let id: String        // full path, unique
    let name: String
    let detail: String    // relative directory, for context
    let relativePath: String
    let url: URL
}

struct MentionMenu: View {
    let items: [MentionFileItem]
    let highlightedID: String?
    let onSelect: (MentionFileItem) -> Void
    let onHover: (MentionFileItem) -> Void

    var body: some View {
        Group {
            if items.isEmpty {
                Text("No files")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(MenuStyle.headerText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                ThinScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items.prefix(50)) { item in
                            MentionRow(
                                item: item,
                                isHighlighted: item.id == highlightedID,
                                onTap: { onSelect(item) },
                                onHover: { onHover(item) }
                            )
                        }
                    }
                    .padding(.vertical, MenuStyle.menuVerticalPadding)
                }
            }
        }
        .frame(maxWidth: 460, maxHeight: 300)
        .menuStandardBackground()
    }
}

private struct MentionRow: View {
    let item: MentionFileItem
    let isHighlighted: Bool
    let onTap: () -> Void
    let onHover: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                LucideIcon(.fileText, size: 12)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 14, alignment: .center)

                Text(item.name)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Color.gray(light: 0.19, dark: 0.86))
                    .lineLimit(1)
                    .layoutPriority(1)

                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(MenuStyle.rowSubtle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 2)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered || isHighlighted))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hovered = hovering
            if hovering { onHover() }
        }
    }
}
