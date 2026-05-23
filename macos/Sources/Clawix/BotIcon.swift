import SwiftUI

/// Custom bot icon used for the Agents surface and the Personalization
/// settings row. Body is a true platform-style continuous-corner squircle
/// (app-icon corner math, E = 6 on a 20x15 box), antenna terminates in a
/// squircle elbow, ears and eyes share the brand mark's vocabulary so the
/// glyph reads as part of the family.
///
/// Two appearance variants:
/// - Dark mode: outline body + antenna with the ears and eyes filled in (the
///   variant the user signed off on).
/// - Light mode: the body reads as a filled mask with the eyes punched out
///   (empty, showing the background through), the ears filled, and the same
///   outline drawn as a border on top.
struct BotIcon: View {
    var size: CGFloat = 16
    var lineWidth: CGFloat = 1.4

    var body: some View {
        ZStack {
            BotStrokedShape()
                .stroke(style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                ))
            BotFilledShape()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 24-grid mapper

private func botGridMapper(_ rect: CGRect) -> (CGFloat, CGFloat) -> CGPoint {
    let s = min(rect.width, rect.height) / 24
    let dx = (rect.width  - 24 * s) / 2
    let dy = (rect.height - 24 * s) / 2
    return { x, y in CGPoint(x: dx + x * s, y: dy + y * s) }
}

// MARK: - Geometry pieces

/// Body squircle: 20x15 at (2, 7), E = 6. Three cubic beziers per corner
/// with the magic numbers used for app icon masks.
private func botBody(into path: inout Path, _ p: (CGFloat, CGFloat) -> CGPoint) {
    path.move(to: p(8, 7))
    path.addLine(to: p(16, 7))
    path.addCurve(to: p(19.990, 7.414),
                  control1: p(18.118, 7),     control2: p(19.180, 7))
    path.addCurve(to: p(21.586, 9.010),
                  control1: p(20.692, 7.774), control2: p(21.226, 8.308))
    path.addCurve(to: p(22, 13),
                  control1: p(22, 9.820),     control2: p(22, 10.882))
    path.addLine(to: p(22, 16))
    path.addCurve(to: p(21.586, 19.990),
                  control1: p(22, 18.118),    control2: p(22, 19.180))
    path.addCurve(to: p(19.990, 21.586),
                  control1: p(21.226, 20.692), control2: p(20.692, 21.226))
    path.addCurve(to: p(16, 22),
                  control1: p(19.180, 22),    control2: p(18.118, 22))
    path.addLine(to: p(8, 22))
    path.addCurve(to: p(4.010, 21.586),
                  control1: p(5.882, 22),     control2: p(4.820, 22))
    path.addCurve(to: p(2.414, 19.990),
                  control1: p(3.308, 21.226), control2: p(2.774, 20.692))
    path.addCurve(to: p(2, 16),
                  control1: p(2, 19.180),     control2: p(2, 18.118))
    path.addLine(to: p(2, 13))
    path.addCurve(to: p(2.414, 9.010),
                  control1: p(2, 10.882),     control2: p(2, 9.820))
    path.addCurve(to: p(4.010, 7.414),
                  control1: p(2.774, 8.308),  control2: p(3.308, 7.774))
    path.addCurve(to: p(8, 7),
                  control1: p(4.820, 7),      control2: p(5.882, 7))
    path.closeSubpath()
}

/// Antenna: stem from body top to (12, 4), squircle elbow (E = 1) bending
/// left, then horizontal arm to (8, 3).
private func botAntenna(into path: inout Path, _ p: (CGFloat, CGFloat) -> CGPoint) {
    path.move(to: p(12, 7))
    path.addLine(to: p(12, 4))
    path.addCurve(to: p(11.931, 3.335),
                  control1: p(12, 3.647),     control2: p(12, 3.470))
    path.addCurve(to: p(11.665, 3.069),
                  control1: p(11.871, 3.218), control2: p(11.782, 3.129))
    path.addCurve(to: p(11, 3),
                  control1: p(11.530, 3),     control2: p(11.353, 3))
    path.addLine(to: p(8, 3))
}

private func botEars(into path: inout Path, _ p: (CGFloat, CGFloat) -> CGPoint) {
    botHorizontalPill(into: &path, at: (0, 14), p: p)
    botHorizontalPill(into: &path, at: (22, 14), p: p)
}

private func botEyes(into path: inout Path, _ p: (CGFloat, CGFloat) -> CGPoint) {
    botVerticalEye(into: &path, at: (7.7, 13.5), p: p)
    botVerticalEye(into: &path, at: (14.7, 12.5), p: p)
}

// MARK: - Shapes

struct BotStrokedShape: Shape {
    func path(in rect: CGRect) -> Path {
        let p = botGridMapper(rect)
        var path = Path()
        botBody(into: &path, p)
        botAntenna(into: &path, p)
        return path
    }
}

/// Dark variant fill: ears + eyes solid.
private struct BotFilledShape: Shape {
    func path(in rect: CGRect) -> Path {
        let p = botGridMapper(rect)
        var path = Path()
        botEars(into: &path, p)
        botEyes(into: &path, p)
        return path
    }
}

/// Light variant mask: body silhouette with the eyes as even-odd holes.
private struct BotBodyEyeHolesShape: Shape {
    func path(in rect: CGRect) -> Path {
        let p = botGridMapper(rect)
        var path = Path()
        botBody(into: &path, p)
        botEyes(into: &path, p)
        return path
    }
}

/// Light variant: ears filled solid (kept out of the even-odd body so they
/// stay opaque rather than cancelling against the silhouette).
private struct BotEarsShape: Shape {
    func path(in rect: CGRect) -> Path {
        let p = botGridMapper(rect)
        var path = Path()
        botEars(into: &path, p)
        return path
    }
}

// MARK: - Pills

/// 2x1 horizontal squircle pill, E = 0.5.
private func botHorizontalPill(
    into path: inout Path,
    at origin: (CGFloat, CGFloat),
    p: (CGFloat, CGFloat) -> CGPoint
) {
    let (ox, oy) = origin
    path.move(to: p(ox + 0.5, oy))
    path.addLine(to: p(ox + 1.5, oy))
    path.addCurve(to: p(ox + 1.833, oy + 0.035),
                  control1: p(ox + 1.677, oy),
                  control2: p(ox + 1.765, oy))
    path.addCurve(to: p(ox + 1.966, oy + 0.168),
                  control1: p(ox + 1.891, oy + 0.065),
                  control2: p(ox + 1.936, oy + 0.109))
    path.addCurve(to: p(ox + 2, oy + 0.5),
                  control1: p(ox + 2, oy + 0.235),
                  control2: p(ox + 2, oy + 0.324))
    path.addCurve(to: p(ox + 1.966, oy + 0.833),
                  control1: p(ox + 2, oy + 0.677),
                  control2: p(ox + 2, oy + 0.765))
    path.addCurve(to: p(ox + 1.833, oy + 0.966),
                  control1: p(ox + 1.936, oy + 0.891),
                  control2: p(ox + 1.891, oy + 0.936))
    path.addCurve(to: p(ox + 1.5, oy + 1),
                  control1: p(ox + 1.765, oy + 1),
                  control2: p(ox + 1.677, oy + 1))
    path.addLine(to: p(ox + 0.5, oy + 1))
    path.addCurve(to: p(ox + 0.168, oy + 0.966),
                  control1: p(ox + 0.324, oy + 1),
                  control2: p(ox + 0.235, oy + 1))
    path.addCurve(to: p(ox + 0.035, oy + 0.833),
                  control1: p(ox + 0.109, oy + 0.936),
                  control2: p(ox + 0.065, oy + 0.891))
    path.addCurve(to: p(ox, oy + 0.5),
                  control1: p(ox, oy + 0.765),
                  control2: p(ox, oy + 0.677))
    path.addCurve(to: p(ox + 0.035, oy + 0.168),
                  control1: p(ox, oy + 0.324),
                  control2: p(ox, oy + 0.235))
    path.addCurve(to: p(ox + 0.168, oy + 0.035),
                  control1: p(ox + 0.065, oy + 0.109),
                  control2: p(ox + 0.109, oy + 0.065))
    path.addCurve(to: p(ox + 0.5, oy),
                  control1: p(ox + 0.235, oy),
                  control2: p(ox + 0.324, oy))
    path.closeSubpath()
}

/// 1.6x3 vertical squircle pill, E = 0.8.
private func botVerticalEye(
    into path: inout Path,
    at origin: (CGFloat, CGFloat),
    p: (CGFloat, CGFloat) -> CGPoint
) {
    let (ox, oy) = origin
    path.move(to: p(ox + 0.8, oy))
    path.addCurve(to: p(ox + 1.332, oy + 0.055),
                  control1: p(ox + 1.082, oy),
                  control2: p(ox + 1.224, oy))
    path.addCurve(to: p(ox + 1.545, oy + 0.268),
                  control1: p(ox + 1.426, oy + 0.103),
                  control2: p(ox + 1.497, oy + 0.174))
    path.addCurve(to: p(ox + 1.6, oy + 0.8),
                  control1: p(ox + 1.6, oy + 0.376),
                  control2: p(ox + 1.6, oy + 0.518))
    path.addLine(to: p(ox + 1.6, oy + 2.2))
    path.addCurve(to: p(ox + 1.545, oy + 2.732),
                  control1: p(ox + 1.6, oy + 2.482),
                  control2: p(ox + 1.6, oy + 2.624))
    path.addCurve(to: p(ox + 1.332, oy + 2.945),
                  control1: p(ox + 1.497, oy + 2.826),
                  control2: p(ox + 1.426, oy + 2.897))
    path.addCurve(to: p(ox + 0.8, oy + 3),
                  control1: p(ox + 1.224, oy + 3),
                  control2: p(ox + 1.082, oy + 3))
    path.addCurve(to: p(ox + 0.268, oy + 2.945),
                  control1: p(ox + 0.518, oy + 3),
                  control2: p(ox + 0.376, oy + 3))
    path.addCurve(to: p(ox + 0.055, oy + 2.732),
                  control1: p(ox + 0.174, oy + 2.897),
                  control2: p(ox + 0.103, oy + 2.826))
    path.addCurve(to: p(ox, oy + 2.2),
                  control1: p(ox, oy + 2.624),
                  control2: p(ox, oy + 2.482))
    path.addLine(to: p(ox, oy + 0.8))
    path.addCurve(to: p(ox + 0.055, oy + 0.268),
                  control1: p(ox, oy + 0.518),
                  control2: p(ox, oy + 0.376))
    path.addCurve(to: p(ox + 0.268, oy + 0.055),
                  control1: p(ox + 0.103, oy + 0.174),
                  control2: p(ox + 0.174, oy + 0.103))
    path.addCurve(to: p(ox + 0.8, oy),
                  control1: p(ox + 0.376, oy),
                  control2: p(ox + 0.518, oy))
    path.closeSubpath()
}
