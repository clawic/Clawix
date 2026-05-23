import SwiftUI

/// Owns the Publishing workspace store at the route boundary so opening chat or
/// launching the app does not construct or observe the Publishing service.
struct PublishingRootView<Content: View>: View {
    @StateObject private var store = PublishingWorkspaceStore()
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .environmentObject(store)
    }
}
