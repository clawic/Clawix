import SwiftUI

/// Lucide `circle-user` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct CircleUserIcon: View {
    var size: CGFloat = 16

    var body: some View {
        CircleUserIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct CircleUserIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20), transform: xform)
        path.addEllipse(in: CGRect(x: 9, y: 7, width: 6, height: 6), transform: xform)
        path.addPath(SVGPathBuilder.build("M7 20.662V19a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v1.662"), transform: xform)
        return path
    }
}
