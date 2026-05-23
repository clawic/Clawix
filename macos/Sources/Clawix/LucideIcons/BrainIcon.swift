import SwiftUI

/// Lucide `brain` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct BrainIcon: View {
    var size: CGFloat = 16

    var body: some View {
        BrainIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct BrainIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M12 5a3 3 0 1 0-5.997.125 4 4 0 0 0-2.526 5.77 4 4 0 0 0 .556 6.588A4 4 0 1 0 12 18Z"), transform: xform)
        path.addPath(SVGPathBuilder.build("M12 5a3 3 0 1 1 5.997.125 4 4 0 0 1 2.526 5.77 4 4 0 0 1-.556 6.588A4 4 0 1 1 12 18Z"), transform: xform)
        path.addPath(SVGPathBuilder.build("M15 13a4.5 4.5 0 0 1-3-4 4.5 4.5 0 0 1-3 4"), transform: xform)
        path.addPath(SVGPathBuilder.build("M17.599 6.5a3 3 0 0 0 .399-1.375"), transform: xform)
        path.addPath(SVGPathBuilder.build("M6.003 5.125A3 3 0 0 0 6.401 6.5"), transform: xform)
        path.addPath(SVGPathBuilder.build("M3.477 10.896a4 4 0 0 1 .585-.396"), transform: xform)
        path.addPath(SVGPathBuilder.build("M19.938 10.5a4 4 0 0 1 .585.396"), transform: xform)
        path.addPath(SVGPathBuilder.build("M6 18a4 4 0 0 1-1.967-.516"), transform: xform)
        path.addPath(SVGPathBuilder.build("M19.967 17.484A4 4 0 0 1 18 18"), transform: xform)
        return path
    }
}
