import SwiftUI

/// Lucide `rss` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct RssIcon: View {
    var size: CGFloat = 16

    var body: some View {
        RssIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct RssIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M4 11a9 9 0 0 1 9 9"), transform: xform)
        path.addPath(SVGPathBuilder.build("M4 4a16 16 0 0 1 16 16"), transform: xform)
        path.addEllipse(in: CGRect(x: 4, y: 18, width: 2, height: 2), transform: xform)
        return path
    }
}
