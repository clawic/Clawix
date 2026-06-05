import SwiftUI

/// Lucide checklist glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct ListTodoIcon: View {
    var size: CGFloat = 16

    var body: some View {
        ListTodoIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct ListTodoIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(Path(roundedRect: CGRect(x: 3, y: 5, width: 6, height: 6), cornerSize: CGSize(width: 1, height: 1), style: .continuous), transform: xform)
        path.addPath(SVGPathBuilder.build("m3 17 2 2 4-4"), transform: xform)
        path.addPath(SVGPathBuilder.build("M13 6h8"), transform: xform)
        path.addPath(SVGPathBuilder.build("M13 12h8"), transform: xform)
        path.addPath(SVGPathBuilder.build("M13 18h8"), transform: xform)
        return path
    }
}
