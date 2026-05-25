import AppKit
import SwiftUI
import ClawixCore

struct ChatScrollDeclarativeAnchors: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .defaultScrollAnchor(.top, for: .alignment)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
        } else {
            content
        }
    }
}

struct ChatScrollUpSentinel: ViewModifier {
    let threshold: CGFloat
    let onTrigger: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: ChatScrollUpGeometryState.self) { geom in
                let realOverflow = geom.contentSize.height
                    > geom.containerSize.height - geom.contentInsets.top - geom.contentInsets.bottom + 1
                let nearTop = geom.contentOffset.y < threshold && realOverflow
                return ChatScrollUpGeometryState(
                    isNearTop: nearTop,
                    contentHeightBucket: nearTop ? Int(geom.contentSize.height.rounded()) : 0
                )
            } action: { oldState, newState in
                if newState.isNearTop,
                   !oldState.isNearTop || oldState.contentHeightBucket != newState.contentHeightBucket {
                    onTrigger()
                }
            }
        } else {
            content
        }
    }
}

private struct ChatScrollUpGeometryState: Equatable {
    let isNearTop: Bool
    let contentHeightBucket: Int
}

/// Reports whether the reader has scrolled meaningfully away from the
/// bottom of an overflowing transcript, driving the scroll-to-bottom
/// button's visibility. macOS 15+ only (mirrors `ChatScrollUpSentinel`);
/// on macOS 14 the flag stays `false` and the button never shows, which
/// is acceptable degradation.
struct ChatScrollBottomSentinel: ViewModifier {
    /// Distance from the tail, in points, past which the button appears.
    let threshold: CGFloat
    @Binding var awayFromBottom: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: ChatScrollBottomGeometryState.self) { geom in
                let visible = geom.containerSize.height
                    - geom.contentInsets.top - geom.contentInsets.bottom
                let realOverflow = geom.contentSize.height > visible + 1
                let distanceFromBottom = geom.contentSize.height
                    - (geom.contentOffset.y + visible)
                let probeBucket = realOverflow
                    ? Int(max(0, distanceFromBottom) / 320)
                    : 0
                return ChatScrollBottomGeometryState(
                    isAwayFromBottom: realOverflow && distanceFromBottom > threshold,
                    probeBucket: probeBucket
                )
            } action: { oldState, newState in
                if oldState.probeBucket != newState.probeBucket {
                    RenderProbe.tick("ChatScroll.position")
                }
                if awayFromBottom != newState.isAwayFromBottom {
                    awayFromBottom = newState.isAwayFromBottom
                }
            }
        } else {
            content
        }
    }
}

private struct ChatScrollBottomGeometryState: Equatable {
    let isAwayFromBottom: Bool
    let probeBucket: Int
}

struct WorkPillAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct BranchPillAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
