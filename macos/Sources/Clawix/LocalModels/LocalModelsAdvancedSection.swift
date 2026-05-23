import SwiftUI
import AppKit

/// Collapsed "Advanced" disclosure for the Local models page. Holds the
/// tuning knobs that most users never touch: context window, keep-alive,
/// storage location, hardware diagnostics. Hidden by default; `LocalModelsPage`
/// tracks the expanded/collapsed state via `advancedExpanded`.
extension LocalModelsPage {

    var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    advancedExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    LucideIcon.auto(advancedExpanded ? "chevron.down" : "chevron.right", size: 10)
                        .foregroundColor(Palette.textSecondary)
                    Text("Advanced")
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if advancedExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    SectionCard(title: "Performance") {
                        VStack(alignment: .leading, spacing: 14) {
                            contextWindowRow
                            Divider().background(Color.overlay(0.07))
                            keepAliveRow
                        }
                    }
                    SectionCard(title: "Storage") {
                        VStack(alignment: .leading, spacing: 12) {
                            storageLocationRow
                            Divider().background(Color.overlay(0.07))
                            revealRow
                        }
                    }
                    SectionCard(title: "Diagnostics") {
                        VStack(alignment: .leading, spacing: 8) {
                            infoRow("Acceleration", accelerationLabel)
                            infoRow("Runtime version", service.runtimeVersion ?? "unknown")
                            infoRow("Loaded models", "\(service.loadedModels.count)")
                            infoRow("Endpoint", LocalModelsDaemon.endpointDisplay)
                            infoRow("Models folder", LocalModelsDaemon.modelsDirectory.path)
                            infoRow("Logs", LocalModelsDaemon.logFileURL.path)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    var contextWindowRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Context window")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Text("\(service.contextLength) tokens")
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Palette.textSecondary)
                    .monospacedDigit()
            }
            CanonSlider(
                value: Binding(
                    get: { Double(service.contextLength) },
                    set: { service.contextLength = Int($0) }
                ),
                range: 1024...32768,
                step: 1024
            )
            Text("Bigger contexts use more memory and slow first-token latency. Applies on next runtime restart.")
                .font(BodyFont.system(size: 10.5))
                .foregroundColor(Palette.textSecondary)
        }
    }

    var keepAliveRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Keep model in memory")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text("How long to keep a model loaded after the last request.")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            SettingsDropdown(
                options: [
                    ("0", L10n.t("Immediate")),
                    ("5m", L10n.t("5 minutes")),
                    ("1h", L10n.t("1 hour")),
                    ("24h", L10n.t("Until quit")),
                    ("-1", L10n.t("Forever")),
                ],
                selection: Binding(
                    get: { service.keepAlive },
                    set: { service.keepAlive = $0 }
                ),
                minWidth: 130
            )
        }
    }

    var storageLocationRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Models folder")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(LocalModelsDaemon.modelsDirectory.path)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(humanSize(totalModelsSize))
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .monospacedDigit()
        }
    }

    var revealRow: some View {
        HStack(alignment: .center) {
            Text("Reveal in Finder")
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
            Spacer()
            Button("Open") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [LocalModelsDaemon.modelsDirectory]
                )
            }
            .buttonStyle(.borderless)
            .font(BodyFont.system(size: 11.5, wght: 500))
        }
    }

    var accelerationLabel: String {
        #if arch(arm64)
        return "Metal · Apple Silicon"
        #else
        return "CPU"
        #endif
    }

    var totalModelsSize: Int64 {
        service.installedModels.reduce(0) { $0 + $1.size }
    }
}

/// Canon slider: thin track on `overlay(0.10)`, a soft pastelBlue fill and a
/// neutral knob with a faint brand ring. Replaces the system `Slider`, which
/// reads as stock macOS chrome in the dark settings surface.
struct CanonSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0

    private let knob: CGFloat = 16
    private let trackHeight: CGFloat = 4

    private func fraction(_ v: Double) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max(0, (v - range.lowerBound) / span), 1))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = fraction(value)
            let cx = frac * w
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.overlay(0.10))
                    .frame(height: trackHeight)
                Capsule(style: .continuous)
                    .fill(LinearGradient(
                        colors: [Palette.pastelBlue.opacity(0.55), Palette.pastelBlue.opacity(0.85)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, cx), height: trackHeight)
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().stroke(Palette.pastelBlue.opacity(0.5), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .offset(x: max(0, min(w - knob, cx - knob / 2)))
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = min(max(0, g.location.x / max(1, w)), 1)
                        var raw = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
                        if step > 0 { raw = (raw / step).rounded() * step }
                        value = min(max(range.lowerBound, raw), range.upperBound)
                    }
            )
        }
        .frame(height: knob)
    }
}
