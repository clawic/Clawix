import SwiftUI

/// Lucide `wand-sparkles` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct WandSparklesIcon: View {
    var size: CGFloat = 16

    var body: some View {
        WandSparklesIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct WandSparklesIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("m21.64 3.64-1.28-1.28a1.21 1.21 0 0 0-1.72 0L2.36 18.64a1.21 1.21 0 0 0 0 1.72l1.28 1.28a1.2 1.2 0 0 0 1.72 0L21.64 5.36a1.2 1.2 0 0 0 0-1.72"), transform: xform)
        path.addPath(SVGPathBuilder.build("m14 7 3 3"), transform: xform)
        path.addPath(SVGPathBuilder.build("M5 6v4"), transform: xform)
        path.addPath(SVGPathBuilder.build("M19 14v4"), transform: xform)
        path.addPath(SVGPathBuilder.build("M10 2v2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M7 8H3"), transform: xform)
        path.addPath(SVGPathBuilder.build("M21 16h-4"), transform: xform)
        path.addPath(SVGPathBuilder.build("M11 3H9"), transform: xform)
        return path
    }
}
