import AppKit
import SwiftUI

extension View {
    /// Tag a control so an agent instance can address it by a stable id. Always
    /// applies an `accessibilityIdentifier` (which also enriches the standard
    /// accessibility tree the control bus reads), and, only inside an agent
    /// instance, records role/label metadata. Free in normal user builds.
    func clxControl(_ id: String, role: String = "control", label: String = "") -> some View {
        accessibilityIdentifier(id)
            .modifier(ClxControlRegistration(id: id, role: role, label: label, activate: nil, setValue: nil))
    }

    /// Variant that also registers an activation closure, used as a deterministic
    /// fallback when the accessibility press path is unavailable.
    func clxControl(
        _ id: String,
        role: String = "control",
        label: String = "",
        activate: @escaping () -> Void
    ) -> some View {
        accessibilityIdentifier(id)
            .modifier(ClxControlRegistration(id: id, role: role, label: label, activate: activate, setValue: nil))
    }

    /// Variant that lets the control bus set text-like values without AX.
    /// This is only registered inside isolated agent instances.
    func clxControl(
        _ id: String,
        role: String = "control",
        label: String = "",
        setValue: @escaping (String) -> Void
    ) -> some View {
        accessibilityIdentifier(id)
            .modifier(ClxControlRegistration(id: id, role: role, label: label, activate: nil, setValue: setValue))
    }
}

private struct ClxControlRegistration: ViewModifier {
    let id: String
    let role: String
    let label: String
    let activate: (() -> Void)?
    let setValue: ((String) -> Void)?
    @State private var registrationToken = UUID()

    func body(content: Content) -> some View {
        Group {
            if ClxAgentInstance.isAgent {
                content
                    .background(
                        ClxControlFrameProbe(id: id, token: registrationToken)
                            .allowsHitTesting(false)
                    )
                    .onAppear {
                        ClxControlRegistry.shared.upsert(
                            id: id,
                            token: registrationToken,
                            role: role,
                            label: label,
                            activate: activate,
                            setValue: setValue
                        )
                    }
                    .onDisappear {
                        ClxControlRegistry.shared.remove(id: id, token: registrationToken)
                        ClxControlRegistry.shared.removeObservedView(id: id, token: registrationToken)
                    }
            } else {
                content
            }
        }
    }
}

private struct ClxControlFrameProbe: NSViewRepresentable {
    let id: String
    let token: UUID

    func makeNSView(context: Context) -> ClxControlFrameProbeView {
        ClxControlFrameProbeView(id: id, token: token)
    }

    func updateNSView(_ nsView: ClxControlFrameProbeView, context: Context) {
        nsView.update(id: id, token: token)
    }

    static func dismantleNSView(_ nsView: ClxControlFrameProbeView, coordinator: ()) {
        ClxControlRegistry.shared.removeObservedView(id: nsView.id, token: nsView.token)
    }
}

private final class ClxControlFrameProbeView: NSView {
    private(set) var id: String
    private(set) var token: UUID

    init(id: String, token: UUID) {
        self.id = id
        self.token = token
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(id nextId: String, token nextToken: UUID) {
        if id != nextId || token != nextToken {
            ClxControlRegistry.shared.removeObservedView(id: id, token: token)
            id = nextId
            token = nextToken
        }
        register()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        register()
    }

    override func layout() {
        super.layout()
        register()
    }

    private func register() {
        guard window != nil else { return }
        ClxControlRegistry.shared.upsertObservedView(id: id, token: token, view: self)
    }
}
