import SwiftUI

/// Lucide `fingerprint` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct FingerprintIcon: View {
    var size: CGFloat = 16

    var body: some View {
        FingerprintIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct FingerprintIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M12 10a2 2 0 0 0-2 2c0 1.02-.1 2.51-.26 4"), transform: xform)
        path.addPath(SVGPathBuilder.build("M14 13.12c0 2.38 0 6.38-1 8.88"), transform: xform)
        path.addPath(SVGPathBuilder.build("M17.29 21.02c.12-.6.43-2.3.5-3.02"), transform: xform)
        path.addPath(SVGPathBuilder.build("M2 12a10 10 0 0 1 18-6"), transform: xform)
        path.addPath(SVGPathBuilder.build("M2 16h.01"), transform: xform)
        path.addPath(SVGPathBuilder.build("M21.8 16c.2-2 .131-5.354 0-6"), transform: xform)
        path.addPath(SVGPathBuilder.build("M5 19.5C5.5 18 6 15 6 12a6 6 0 0 1 .34-2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M8.65 22c.21-.66.45-1.32.57-2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M9 6.8a6 6 0 0 1 9 5.2v2"), transform: xform)
        return path
    }
}
