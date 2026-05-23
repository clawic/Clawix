import SwiftUI

/// Lucide `house` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct HouseIcon: View {
    var size: CGFloat = 16

    var body: some View {
        HouseIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct HouseIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        // Minimalist: outer house only (the door path is dropped).
        path.addPath(SVGPathBuilder.build("M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"), transform: xform)
        // Widen ~12% around the house centre for a stockier silhouette.
        let cx = dx + 12 * s
        let widen = CGAffineTransform(translationX: cx, y: 0)
            .scaledBy(x: 1.12, y: 1)
            .translatedBy(x: -cx, y: 0)
        return path.applying(widen)
    }
}
