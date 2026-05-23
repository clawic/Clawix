import SwiftUI

/// Lucide `plug` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct PlugIcon: View {
    var size: CGFloat = 16

    var body: some View {
        PlugIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct PlugIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M12 22v-5"), transform: xform)
        path.addPath(SVGPathBuilder.build("M9 8V2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M15 8V2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M18 8v5a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V8Z"), transform: xform)
        return path
    }
}
