import SwiftUI

/// Holds a `DesignStore.PollingLease` for as long as the Design surface it wraps
/// is on screen. Acquiring on `.task` and releasing on disappear means the
/// store's 4s disk-reload timer only ticks while a Design surface is visible
/// (P4 lease-gate): an idle app with no Design surface open never polls.
private struct DesignPollingLeaseModifier: ViewModifier {
    @State private var lease: DesignStore.PollingLease?

    func body(content: Content) -> some View {
        content
            .task {
                if lease == nil {
                    lease = DesignStore.shared.acquirePollingLease()
                }
            }
            .onDisappear {
                lease?.cancel()
                lease = nil
            }
    }
}

extension View {
    /// Keep `DesignStore` polling alive while this Design surface is on screen.
    func designPollingLease() -> some View {
        modifier(DesignPollingLeaseModifier())
    }
}
