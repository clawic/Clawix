import SwiftUI

/// Lucide `smile` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct SmileIcon: View {
    var size: CGFloat = 16

    var body: some View {
        SmileIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct SmileIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20), transform: xform)
        path.addPath(SVGPathBuilder.build("M8 14s1.5 2 4 2 4-2 4-2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M 9 9 L 9.01 9"), transform: xform)
        path.addPath(SVGPathBuilder.build("M 15 9 L 15.01 9"), transform: xform)
        return path
    }
}
