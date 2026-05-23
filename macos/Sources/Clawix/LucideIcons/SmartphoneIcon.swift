import SwiftUI

/// Lucide `smartphone` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct SmartphoneIcon: View {
    var size: CGFloat = 16

    var body: some View {
        SmartphoneIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct SmartphoneIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(Path(roundedRect: CGRect(x: 5, y: 2, width: 14, height: 20), cornerSize: CGSize(width: 2, height: 2), style: .continuous), transform: xform)
        path.addPath(SVGPathBuilder.build("M12 18h.01"), transform: xform)
        return path
    }
}
