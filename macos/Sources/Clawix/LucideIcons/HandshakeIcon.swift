import SwiftUI

/// Lucide `handshake` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct HandshakeIcon: View {
    var size: CGFloat = 16

    var body: some View {
        HandshakeIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct HandshakeIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("m11 17 2 2a1 1 0 1 0 3-3"), transform: xform)
        path.addPath(SVGPathBuilder.build("m14 14 2.5 2.5a1 1 0 1 0 3-3l-3.88-3.88a3 3 0 0 0-4.24 0l-.88.88a1 1 0 1 1-3-3l2.81-2.81a5.79 5.79 0 0 1 7.06-.87l.47.28a2 2 0 0 0 1.42.25L21 4"), transform: xform)
        path.addPath(SVGPathBuilder.build("m21 3 1 11h-2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M3 3 2 14l6.5 6.5a1 1 0 1 0 3-3"), transform: xform)
        path.addPath(SVGPathBuilder.build("M3 4h8"), transform: xform)
        return path
    }
}
