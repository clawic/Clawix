import SwiftUI

/// Lucide `clipboard-list` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct ClipboardListIcon: View {
    var size: CGFloat = 16

    var body: some View {
        ClipboardListIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct ClipboardListIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(Path(roundedRect: CGRect(x: 8, y: 2, width: 8, height: 4), cornerSize: CGSize(width: 1, height: 1), style: .continuous), transform: xform)
        path.addPath(SVGPathBuilder.build("M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M12 11h4"), transform: xform)
        path.addPath(SVGPathBuilder.build("M12 16h4"), transform: xform)
        path.addPath(SVGPathBuilder.build("M8 11h.01"), transform: xform)
        path.addPath(SVGPathBuilder.build("M8 16h.01"), transform: xform)
        return path
    }
}
