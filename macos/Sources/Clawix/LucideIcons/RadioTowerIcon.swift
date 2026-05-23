import SwiftUI

/// Lucide `radio-tower` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct RadioTowerIcon: View {
    var size: CGFloat = 16

    var body: some View {
        RadioTowerIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct RadioTowerIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M4.9 16.1C1 12.2 1 5.8 4.9 1.9"), transform: xform)
        path.addPath(SVGPathBuilder.build("M7.8 4.7a6.14 6.14 0 0 0-.8 7.5"), transform: xform)
        path.addEllipse(in: CGRect(x: 10, y: 7, width: 4, height: 4), transform: xform)
        path.addPath(SVGPathBuilder.build("M16.2 4.8c2 2 2.26 5.11.8 7.47"), transform: xform)
        path.addPath(SVGPathBuilder.build("M19.1 1.9a9.96 9.96 0 0 1 0 14.1"), transform: xform)
        path.addPath(SVGPathBuilder.build("M9.5 18h5"), transform: xform)
        path.addPath(SVGPathBuilder.build("m8 22 4-11 4 11"), transform: xform)
        return path
    }
}
