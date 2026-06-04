import SwiftUI

/// Holds an `AppsStore.PollingLease` for as long as the Apps surface it wraps is
/// on screen. The store's FSEvent stream stays on regardless (it is quiescent
/// when idle); this lease gates only the periodic rescue/fallback timers so an
/// idle app with no Apps surface open never ticks them (P4 lease-gate).
private struct AppsPollingLeaseModifier: ViewModifier {
    @State private var lease: AppsStore.PollingLease?

    func body(content: Content) -> some View {
        content
            .task {
                if lease == nil {
                    lease = AppsStore.shared.acquirePollingLease()
                }
            }
            .onDisappear {
                lease?.cancel()
                lease = nil
            }
    }
}

extension View {
    /// Keep `AppsStore`'s scheduled disk-reload timers alive while this Apps
    /// surface is on screen.
    func appsPollingLease() -> some View {
        modifier(AppsPollingLeaseModifier())
    }
}
