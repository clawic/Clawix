import SwiftUI

/// Lucide `sliders-horizontal` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct SlidersHorizontalIcon: View {
    var size: CGFloat = 16

    var body: some View {
        SlidersHorizontalIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct SlidersHorizontalIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M 21 4 L 14 4"), transform: xform)
        path.addPath(SVGPathBuilder.build("M 10 4 L 3 4"), transform: xform)
        path.addPath(SVGPathBuilder.build("M 21 12 L 12 12"), transform: xform)
        path.addPath(SVGPathBuilder.build("M 8 12 L 3 12"), transform: xform)
        path.addPath(SVGPathBuilder.build("M 21 20 L 16 20"), transform: xform)
        path.addPath(SVGPathBuilder.build("M 12 20 L 3 20"), transform: xform)
        path.addPath(SVGPathBuilder.build("M 14 2 L 14 6"), transform: xform)
        path.addPath(SVGPathBuilder.build("M 8 10 L 8 14"), transform: xform)
        path.addPath(SVGPathBuilder.build("M 16 18 L 16 22"), transform: xform)
        return path
    }
}
