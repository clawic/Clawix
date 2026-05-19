import AppKit

final class SystemTelemetryHistoryGraphView: NSView {
    static let preferredSize = NSSize(width: 220, height: 64)

    let history: SystemTelemetryHistory
    let title: String

    var pointCount: Int {
        history.chart.points.count
    }

    init(history: SystemTelemetryHistory, title: String) {
        self.history = history
        self.title = title
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(title) history graph")
        setAccessibilityValue(accessibilitySummary)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.controlBackgroundColor.withAlphaComponent(0.65).setFill()
        bounds.fill()

        let chartRect = bounds.insetBy(dx: 10, dy: 10)
        drawGrid(in: chartRect)

        let points = history.chart.points
        guard points.count >= 2 else {
            drawEmpty(in: chartRect)
            return
        }

        let values = points.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let valueSpan = max(maxValue - minValue, 0.0001)
        let firstTime = points.first?.timestampMS ?? 0
        let lastTime = points.last?.timestampMS ?? firstTime
        let timeSpan = max(lastTime - firstTime, 1)
        let coordinates = points.map { point in
            CGPoint(
                x: chartRect.minX + chartRect.width * CGFloat((point.timestampMS - firstTime) / timeSpan),
                y: chartRect.maxY - chartRect.height * CGFloat((point.value - minValue) / valueSpan)
            )
        }

        drawFill(points: coordinates, bottomY: chartRect.maxY)
        drawLine(points: coordinates)
        drawExtrema(minValue: minValue, maxValue: maxValue, in: chartRect)
    }

    private var accessibilitySummary: String {
        let values = history.chart.points.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return "No retained history points"
        }
        return "\(pointCount) retained points, min \(format(minValue)), max \(format(maxValue))"
    }

    private func drawGrid(in rect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.18).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        for fraction in [0.25, 0.5, 0.75] {
            let y = rect.minY + rect.height * CGFloat(fraction)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.line(to: CGPoint(x: rect.maxX, y: y))
        }
        path.stroke()
    }

    private func drawEmpty(in rect: NSRect) {
        let text = "Need 2+ points"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawFill(points: [CGPoint], bottomY: CGFloat) {
        guard let first = points.first, let last = points.last else { return }
        let path = NSBezierPath()
        path.move(to: CGPoint(x: first.x, y: bottomY))
        for point in points {
            path.line(to: point)
        }
        path.line(to: CGPoint(x: last.x, y: bottomY))
        path.close()
        NSColor.systemBlue.withAlphaComponent(0.16).setFill()
        path.fill()
    }

    private func drawLine(points: [CGPoint]) {
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            if index == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        path.lineWidth = 1.7
        NSColor.systemBlue.setStroke()
        path.stroke()
    }

    private func drawExtrema(minValue: Double, maxValue: Double, in rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        format(maxValue).draw(at: CGPoint(x: rect.minX, y: rect.minY - 1), withAttributes: attributes)
        format(minValue).draw(at: CGPoint(x: rect.minX, y: rect.maxY - 11), withAttributes: attributes)
    }

    private func format(_ value: Double) -> String {
        if value == floor(value) { return String(Int(value)) }
        return String(format: "%.2f", value)
    }
}
