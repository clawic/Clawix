import SwiftUI

/// Lucide `palette` glyph, path data replicated from the Lucide source
/// (lucide-react v0.469.0, ISC). Own Swift file so stroke weight and
/// proportions stay tunable, on the project's 24-in-28 grid with the
/// shared 2.5/28 stroke ratio to match `SearchIcon` / `GlobeIcon`.
struct PaletteIcon: View {
    var size: CGFloat = 16

    var body: some View {
        PaletteIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct PaletteIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addEllipse(in: CGRect(x: 13, y: 6, width: 1, height: 1), transform: xform)
        path.addEllipse(in: CGRect(x: 17, y: 10, width: 1, height: 1), transform: xform)
        path.addEllipse(in: CGRect(x: 8, y: 7, width: 1, height: 1), transform: xform)
        path.addEllipse(in: CGRect(x: 6, y: 12, width: 1, height: 1), transform: xform)
        path.addPath(SVGPathBuilder.build("M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z"), transform: xform)
        return path
    }
}
