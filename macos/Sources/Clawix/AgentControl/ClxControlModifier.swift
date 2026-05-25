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
}

private struct ClxControlRegistration: ViewModifier {
    let id: String
    let role: String
    let label: String
    let activate: (() -> Void)?
    let setValue: ((String) -> Void)?
    @State private var registrationToken = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard ClxAgentInstance.isAgent else { return }
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
                guard ClxAgentInstance.isAgent else { return }
                ClxControlRegistry.shared.remove(id: id, token: registrationToken)
            }
    }
}
