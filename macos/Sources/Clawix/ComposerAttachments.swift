import SwiftUI
import AppKit
import ImageIO

// MARK: - Composer attachment chips

struct ComposerAttachmentRow: View {
    let attachments: [ComposerAttachment]
    let onRemove: (UUID) -> Void
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { att in
                    ComposerAttachmentChip(
                        attachment: att,
                        onRemove: { onRemove(att.id) },
                        onOpen: {
                            if att.isImage {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    appState.imagePreviewURL = att.url
                                }
                            }
                        }
                    )
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

struct ComposerAttachmentChip: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void
    let onOpen: () -> Void

    @State private var hovered = false
    @State private var removeHovered = false

    private var leadingSpacing: CGFloat {
        if attachment.isAppshot { return 7 }
        return attachment.isImage ? 6 : 4
    }

    var body: some View {
        HStack(spacing: leadingSpacing) {
            HStack(spacing: leadingSpacing) {
                iconView
                Text(attachment.displayName)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.94))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(0)
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }
            .help(chipHelp)
            Button(action: onRemove) {
                LucideIcon(.x, size: 11)
                    .foregroundColor(Color(white: removeHovered ? 1.0 : 0.78))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0.001)
            .accessibilityLabel(Text("\(L10n.t("Remove attachment")): \(attachment.filename)"))
            .accessibilityIdentifier("composer-attachment-remove-\(attachment.id.uuidString)")
            .accessibilityAction(named: Text(L10n.t("Remove attachment"))) {
                onRemove()
            }
            .onHover { removeHovered = $0 }
            .help(L10n.t("Remove attachment"))
            .layoutPriority(1)
        }
        .padding(.leading, attachment.isAppshot ? 5 : (attachment.isImage ? 9 : 7))
        .padding(.trailing, hovered ? 7 : 11)
        .padding(.vertical, 5)
        .frame(maxWidth: 220, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.03 : 0))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
        )
        .animation(.easeOut(duration: 0.14), value: hovered)
        .contentShape(Capsule(style: .continuous))
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var iconView: some View {
        if let appshot = attachment.appshot {
            AppshotChipIcon(url: attachment.url, bundleId: appshot.bundleId)
        } else if let annotation = attachment.annotation {
            BrowserAnnotationChipIcon(url: attachment.url, marker: annotation.marker)
        } else if attachment.isImage {
            ComposerAttachmentImageIcon(url: attachment.url)
        } else {
            FileChipIcon(size: 10)
                .foregroundColor(Color(white: 0.60))
                .frame(width: 18, height: 18)
        }
    }

    private var chipHelp: String {
        if let appshot = attachment.appshot {
            if let title = appshot.windowTitle, !title.isEmpty {
                return "\(appshot.appName) — \(title)"
            }
            return appshot.appName
        }
        if let annotation = attachment.annotation {
            if let title = annotation.pageTitle, !title.isEmpty {
                return "\(title) — \(annotation.pageURL)"
            }
            return annotation.pageURL
        }
        return attachment.isImage ? L10n.t("Click to enlarge") : attachment.url.path
    }
}

/// Browser-annotation chip leading glyph: a rounded thumbnail of the page
/// screenshot with the comment marker number badged at the bottom-trailing
/// corner, so the chip reads as "a comment pinned on this page".
struct BrowserAnnotationChipIcon: View {
    let url: URL
    let marker: Int

    @State private var image: NSImage?

    private let thumbWidth: CGFloat = 30
    private let thumbHeight: CGFloat = 22
    private let badge: CGFloat = 15

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(white: 0.16))
                .frame(width: thumbWidth, height: thumbHeight)
                .overlay {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: thumbWidth, height: thumbHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                )

            Text("\(marker)")
                .font(BodyFont.system(size: 9, wght: 700))
                .foregroundColor(.white)
                .frame(width: badge, height: badge)
                .background(
                    Circle().fill(Color(red: 0.23, green: 0.51, blue: 0.96))
                )
                .overlay(
                    Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5)
                )
                .offset(x: 4, y: 4)
        }
        .frame(width: thumbWidth + 4, height: thumbHeight + 4, alignment: .topLeading)
        .task(id: url.standardizedFileURL.path) {
            image = await Self.thumbnail(for: url)
        }
    }

    private static func thumbnail(for url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let cfURL = url as CFURL
            guard let source = CGImageSourceCreateWithURL(cfURL, nil) else {
                return NSImage(contentsOf: url)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return NSImage(contentsOf: url)
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }
}

/// Appshot chip leading glyph: a rounded thumbnail of the captured window
/// with the source app's icon badged at the bottom-trailing corner — the
/// "screenshot thumbnail + app icon badge" the chip is built around.
struct AppshotChipIcon: View {
    let url: URL
    let bundleId: String?

    @State private var image: NSImage?

    private let thumbWidth: CGFloat = 30
    private let thumbHeight: CGFloat = 22
    private let badge: CGFloat = 14

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(white: 0.16))
                .frame(width: thumbWidth, height: thumbHeight)
                .overlay {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: thumbWidth, height: thumbHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                )

            if let bundleId {
                AppIconImage(bundleId: bundleId, fallbackPath: "", size: badge)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color.black.opacity(0.35), lineWidth: 0.5)
                    )
                    .offset(x: 4, y: 4)
            }
        }
        .frame(width: thumbWidth + 4, height: thumbHeight + 4, alignment: .topLeading)
        .task(id: url.standardizedFileURL.path) {
            image = await AppshotChipIcon.thumbnail(for: url)
        }
    }

    private static func thumbnail(for url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let cfURL = url as CFURL
            guard let source = CGImageSourceCreateWithURL(cfURL, nil) else {
                return NSImage(contentsOf: url)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return NSImage(contentsOf: url)
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }
}

struct ComposerAttachmentImageIcon: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                FileChipIcon(size: 10)
                    .foregroundColor(Color(white: 0.60))
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
        .task(id: url.standardizedFileURL.path) {
            image = await Self.thumbnail(for: url)
        }
    }

    private static func thumbnail(for url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let cfURL = url as CFURL
            guard let source = CGImageSourceCreateWithURL(cfURL, nil) else {
                return NSImage(contentsOf: url)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 64
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return NSImage(contentsOf: url)
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }
}
