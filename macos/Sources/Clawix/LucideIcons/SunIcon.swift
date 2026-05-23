import SwiftUI

/// Lucide `sun` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct SunIcon: View {
    var size: CGFloat = 16

    var body: some View {
        SunIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct SunIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addEllipse(in: CGRect(x: 8, y: 8, width: 8, height: 8), transform: xform)
        path.addPath(SVGPathBuilder.build("M12 2v2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M12 20v2"), transform: xform)
        path.addPath(SVGPathBuilder.build("m4.93 4.93 1.41 1.41"), transform: xform)
        path.addPath(SVGPathBuilder.build("m17.66 17.66 1.41 1.41"), transform: xform)
        path.addPath(SVGPathBuilder.build("M2 12h2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M20 12h2"), transform: xform)
        path.addPath(SVGPathBuilder.build("m6.34 17.66-1.41 1.41"), transform: xform)
        path.addPath(SVGPathBuilder.build("m19.07 4.93-1.41 1.41"), transform: xform)
        return path
    }
}
