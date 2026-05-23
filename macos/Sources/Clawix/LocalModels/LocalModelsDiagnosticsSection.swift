import SwiftUI

extension LocalModelsPage {
    var diagnosticsSection: some View {
        SectionCard(title: "Diagnostics") {
            VStack(alignment: .leading, spacing: 8) {
                infoRow("Runtime version", service.runtimeVersion ?? "unknown")
                infoRow("Models folder", LocalModelsDaemon.modelsDirectory.path)
                infoRow("Logs", LocalModelsDaemon.logFileURL.path)
                infoRow("Endpoint", LocalModelsDaemon.endpointDisplay)
            }
        }
    }

    func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
        }
    }

    func actionRow(
        title: String,
        detail: String,
        buttonLabel: String,
        isEnabled: Bool = true,
        isWorking: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(buttonLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!isEnabled)
            }
        }
    }

    func badge(_ label: String) -> some View {
        Text(label)
            .font(BodyFont.system(size: 9.5, wght: 700))
            .foregroundColor(Palette.textPrimary.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.overlay(0.10)))
    }

    func humanSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func progressLabel(downloaded: Int64, total: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        let d = formatter.string(fromByteCount: downloaded)
        let t = formatter.string(fromByteCount: total)
        return "\(d) / \(t)"
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
            VStack(alignment: .leading, spacing: 0) {
                content()
                    .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.gray(light: 0.95, dark: 0.085))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.overlay(0.10), lineWidth: 0.6)
            )
        }
    }
}

extension LocalModelsDaemon.State {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
    var isStarting: Bool {
        if case .starting = self { return true }
        return false
    }
}
