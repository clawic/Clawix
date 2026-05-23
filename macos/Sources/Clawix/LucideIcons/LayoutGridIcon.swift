import SwiftUI

/// Lucide `layout-grid` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct LayoutGridIcon: View {
    var size: CGFloat = 16

    var body: some View {
        LayoutGridIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct LayoutGridIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(Path(roundedRect: CGRect(x: 3, y: 3, width: 7, height: 7), cornerSize: CGSize(width: 1, height: 1), style: .continuous), transform: xform)
        path.addPath(Path(roundedRect: CGRect(x: 14, y: 3, width: 7, height: 7), cornerSize: CGSize(width: 1, height: 1), style: .continuous), transform: xform)
        path.addPath(Path(roundedRect: CGRect(x: 14, y: 14, width: 7, height: 7), cornerSize: CGSize(width: 1, height: 1), style: .continuous), transform: xform)
        path.addPath(Path(roundedRect: CGRect(x: 3, y: 14, width: 7, height: 7), cornerSize: CGSize(width: 1, height: 1), style: .continuous), transform: xform)
        return path
    }
}
