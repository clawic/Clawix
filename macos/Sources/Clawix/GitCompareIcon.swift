import SwiftUI

/// Git compare / review glyph: two nodes (top-left, bottom-right) joined by
/// two right-angled connectors, the Lucide "git-compare" silhouette. Used
/// for the review / changes side-panel tab and its launcher tile. Outline
/// language matches the rest of the custom icon family: 24-grid viewBox,
/// hairline stroke that scales with `size`, rounded caps and joins.
struct GitCompareIcon: View {
    var size: CGFloat = 13

    var body: some View {
        GitCompareIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 1.7 * (size / 24),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

private struct GitCompareIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var path = Path()

        // Top-left node.
        path.addEllipse(in: CGRect(x: rect.minX + 3 * s, y: rect.minY + 3 * s,
                                   width: 6 * s, height: 6 * s))
        // Bottom-right node.
        path.addEllipse(in: CGRect(x: rect.minX + 15 * s, y: rect.minY + 15 * s,
                                   width: 6 * s, height: 6 * s))

        // Connector from the top-left node across and down into the right column.
        path.move(to: p(13, 6))
        path.addLine(to: p(16, 6))
        path.addQuadCurve(to: p(18, 8), control: p(18, 6))
        path.addLine(to: p(18, 15))

        // Connector from the bottom-right node back and up into the left column.
        path.move(to: p(11, 18))
        path.addLine(to: p(8, 18))
        path.addQuadCurve(to: p(6, 16), control: p(6, 18))
        path.addLine(to: p(6, 9))

        return path
    }
}
