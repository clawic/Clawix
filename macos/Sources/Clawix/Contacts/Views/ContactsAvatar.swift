import SwiftUI
import ImageIO

struct ContactsAvatar: View {
    let contact: Contact
    var size: CGFloat
    var hoverable: Bool = false

    @State private var hovered: Bool = false
    private static let maxPhotoPixelSize = 256

    var body: some View {
        ZStack {
            if let data = contact.photoData,
               let img = Self.downsampledImage(from: data, maxPixelSize: Self.maxPhotoPixelSize) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(ContactsTokens.AvatarPalette.color(for: contact.id))
                Text(contact.initials)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(hoverable && hovered ? 1.04 : 1.0)
        .animation(ContactsTokens.Motion.avatarHover, value: hovered)
        .onHover { hov in
            guard hoverable else { return }
            hovered = hov
        }
    }

    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
