import SwiftUI

/// Lucide `git-branch` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct GitBranchLineIcon: View {
    var size: CGFloat = 16

    var body: some View {
        GitBranchLineIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct GitBranchLineIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M 6 3 L 6 15"), transform: xform)
        path.addEllipse(in: CGRect(x: 15, y: 3, width: 6, height: 6), transform: xform)
        path.addEllipse(in: CGRect(x: 3, y: 15, width: 6, height: 6), transform: xform)
        path.addPath(SVGPathBuilder.build("M18 9a9 9 0 0 1-9 9"), transform: xform)
        return path
    }
}
