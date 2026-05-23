import SwiftUI

/// Lucide `monitor` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct MonitorIcon: View {
    var size: CGFloat = 16

    var body: some View {
        MonitorIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct MonitorIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(Path(roundedRect: CGRect(x: 2, y: 3, width: 20, height: 14), cornerSize: CGSize(width: 2, height: 2), style: .continuous), transform: xform)
        path.addPath(SVGPathBuilder.build("M 8 21 L 16 21"), transform: xform)
        path.addPath(SVGPathBuilder.build("M 12 17 L 12 21"), transform: xform)
        return path
    }
}
