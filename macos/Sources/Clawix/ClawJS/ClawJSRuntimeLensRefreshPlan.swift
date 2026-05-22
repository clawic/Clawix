import Foundation

struct ClawJSRuntimeLensRefreshPlan: Equatable {
    let runtimes: [ClawJSRuntimeLensID]

    static func scoped(to runtime: ClawJSRuntimeLensID) -> ClawJSRuntimeLensRefreshPlan {
        ClawJSRuntimeLensRefreshPlan(runtimes: [runtime])
    }
}
