import SwiftUI
import UniformTypeIdentifiers

struct ToolRowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

final class ToolRowFrameStore: ObservableObject {
    var byId: [String: CGRect] = [:]
}

struct ToolsReorderableList: View {
    let tools: [SidebarToolEntry]
    let selectedRoute: SidebarRoute
    let onSelect: (SidebarRoute) -> Void
    let onReorder: (String, String?) -> Void

    @State private var draggingId: String? = nil
    @State private var targetIndex: Int? = nil
    @State private var mouseUpMonitor: Any? = nil
    @State private var dragChipPanel: DragChipPanel? = nil
    @StateObject private var rowFrames = ToolRowFrameStore()
    @StateObject private var scrollBox = EnclosingScrollViewBox()
    @State private var autoScroller: PinnedDragAutoScroller? = nil

    /// Slot height used both as the row height and the gap height during
    /// drag. The two cancel out so the list height stays constant while
    /// the gap migrates between slots. Matches the natural intrinsic
    /// height of `DatabaseToolRow` / `SecretsToolRow` (~28 pt: 6 pt
    /// vertical padding + ~16 pt content).
    static let rowSlotHeight: CGFloat = 28
    private let baseSpacing: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tools.enumerated()), id: \.element.id) { (i, entry) in
                slotZone(entry: entry, slot: i)
            }
            trailingSlotZone
        }
        .background(EnclosingScrollViewLocator(box: scrollBox).allowsHitTesting(false))
        .onAppear { installMouseUpMonitor() }
        .onDisappear {
            cleanupDragChip()
            removeMouseUpMonitor()
        }
        .onPreferenceChange(ToolRowFrameKey.self) { rowFrames.byId = $0 }
        .onChange(of: tools.map(\.id)) { _, _ in
            // Defensive sweep: any external mutation to the tools array
            // (filter toggle, reorder) clears lingering drag state so a
            // stale gap can never persist.
            guard draggingId != nil || targetIndex != nil else {
                cleanupDragChip()
                return
            }
            cleanupDragChip()
            targetIndex = nil
            draggingId = nil
        }
    }

    @ViewBuilder
    private func slotZone(entry: SidebarToolEntry, slot: Int) -> some View {
        let isDragging = draggingId == entry.id
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ToolRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { id, chosen in performReorder(toolId: id, beforeIndex: chosen) }
                ))
            ToolDisplayRow(
                entry: entry,
                isSelected: selectedRoute == entry.route,
                onTap: { onSelect(entry.route) }
            )
            .background(WindowDragInhibitor())
            .opacity(isDragging ? 0 : 1)
            .frame(height: isDragging ? 0 : nil, alignment: .top)
            .clipped()
            .allowsHitTesting(!isDragging)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ToolRowFrameKey.self,
                        value: [entry.id: proxy.frame(in: .global)]
                    )
                }
            )
            .onDrag {
                handleDragStart(entry: entry)
                let provider = NSItemProvider()
                let urlString = "\(clawixToolURLScheme)://\(entry.id)"
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.url.identifier,
                    visibility: .ownProcess
                ) { completion in
                    completion(urlString.data(using: .utf8), nil)
                    return nil
                }
                provider.suggestedName = entry.titleString
                return provider
            } preview: {
                Color.clear.frame(width: 1, height: 1)
            }
            .onDrop(of: [.url], delegate: ToolRowDropDelegate(
                computeSlot: { y in y < Self.rowSlotHeight / 2 ? slot : slot + 1 },
                onSet: { setTarget(slot: $0) },
                onPerform: { id, chosen in performReorder(toolId: id, beforeIndex: chosen) }
            ))
        }
    }

    @ViewBuilder
    private var trailingSlotZone: some View {
        let slot = tools.count
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ToolRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { id, chosen in performReorder(toolId: id, beforeIndex: chosen) }
                ))
            Color.clear
                .frame(height: SidebarRowMetrics.sectionEdgePadding)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ToolRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { id, chosen in performReorder(toolId: id, beforeIndex: chosen) }
                ))
        }
    }

    @ViewBuilder
    private func gapPlaceholder(at index: Int) -> some View {
        let isOpen = targetIndex == index
        let isFirst = index == 0
        let isLast = index == tools.count
        let baseHeight: CGFloat = (isFirst || isLast) ? 0 : baseSpacing
        Color.clear.frame(height: isOpen ? Self.rowSlotHeight : baseHeight)
    }

    private func handleDragStart(entry: SidebarToolEntry) {
        let src = tools.firstIndex(where: { $0.id == entry.id })
        targetIndex = src
        draggingId = entry.id
        let (anchor, width) = grabAnchor(for: entry)
        dragChipPanel?.close()
        let chip = ToolDragChipView(
            entry: entry,
            width: width,
            shadowInset: 24
        )
        dragChipPanel = DragChipPanel(
            content: AnyView(chip),
            grabAnchor: anchor,
            width: width,
            fallbackHeight: Self.rowSlotHeight
        )
        dragChipPanel?.show()
        autoScroller?.stop()
        let scroller = PinnedDragAutoScroller(box: scrollBox)
        scroller.start()
        autoScroller = scroller
    }

    private func grabAnchor(for entry: SidebarToolEntry) -> (CGPoint, CGFloat) {
        let fallbackWidth: CGFloat = 240
        guard let rowFrame = rowFrames.byId[entry.id] else {
            return (CGPoint(x: 30, y: 14), fallbackWidth)
        }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView
        else {
            return (CGPoint(x: 30, y: 14), rowFrame.width)
        }
        let cursorScreen = NSEvent.mouseLocation
        let cursorInWindow = window.convertPoint(fromScreen: cursorScreen)
        let cursorSwiftUI = CGPoint(
            x: cursorInWindow.x,
            y: contentView.frame.height - cursorInWindow.y
        )
        let dx = cursorSwiftUI.x - rowFrame.origin.x
        let dy = cursorSwiftUI.y - rowFrame.origin.y
        return (CGPoint(x: dx, y: dy), rowFrame.width)
    }

    private func cleanupDragChip() {
        dragChipPanel?.close()
        dragChipPanel = nil
        autoScroller?.stop()
        autoScroller = nil
    }

    private func setTarget(slot: Int) {
        guard draggingId != nil else { return }
        guard targetIndex != slot else { return }
        withAnimation(toolReorderMoveAnimation) {
            targetIndex = slot
        }
    }

    private func performReorder(toolId: String, beforeIndex: Int) {
        cleanupDragChip()
        // Skip a no-op drop onto the source's own slot (either the gap
        // immediately above or the slot immediately below it). Otherwise
        // we'd churn the persisted order and re-fire the onChange watcher
        // on every drop that didn't actually move anything.
        if let src = tools.firstIndex(where: { $0.id == toolId }),
           (beforeIndex == src || beforeIndex == src + 1) {
            targetIndex = nil
            draggingId = nil
            return
        }
        let beforeId: String? = (beforeIndex < tools.count) ? tools[beforeIndex].id : nil
        onReorder(toolId, beforeId)
        targetIndex = nil
        draggingId = nil
    }

    private func installMouseUpMonitor() {
        guard mouseUpMonitor == nil else { return }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            DispatchQueue.main.async {
                cleanupDragChip()
                guard draggingId != nil || targetIndex != nil else { return }
                targetIndex = nil
                draggingId = nil
            }
            return event
        }
    }

    private func removeMouseUpMonitor() {
        if let m = mouseUpMonitor {
            NSEvent.removeMonitor(m)
            mouseUpMonitor = nil
        }
    }
}

struct ToolRowDropDelegate: DropDelegate {
    let computeSlot: (CGFloat) -> Int
    let onSet: (Int) -> Void
    let onPerform: (String, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.url])
    }

    func dropEntered(info: DropInfo) {
        onSet(computeSlot(info.location.y))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onSet(computeSlot(info.location.y))
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let slot = computeSlot(info.location.y)
        guard let provider = info.itemProviders(for: [.url]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
            guard let data,
                  let s = String(data: data, encoding: .utf8),
                  let url = URL(string: s),
                  url.scheme == clawixToolURLScheme
            else { return }
            // The id sits in the URL host slot. Tool ids in the catalog
            // are already lowercase so macOS's hostname canonicalisation
            // is a no-op.
            let id = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !id.isEmpty else { return }
            DispatchQueue.main.async {
                onPerform(id, slot)
            }
        }
        return true
    }
}

struct ToolDisplayRow: View {
    let entry: SidebarToolEntry
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        switch entry.icon {
        case .secrets:
            SecretsToolRow(isSelected: isSelected, onTap: onTap)
        case .system(let name):
            DatabaseToolRow(
                title: entry.titleString,
                systemIcon: name,
                route: entry.route,
                isSelected: isSelected,
                onTap: onTap
            )
        case .clawixLogo:
            AgentsToolRow(
                title: entry.titleString,
                route: entry.route,
                isSelected: isSelected,
                onTap: onTap
            )
        }
    }
}

struct AgentsToolRow: View {
    let title: String
    let route: SidebarRoute
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                ClawixLogoIcon(size: 13)
                    .frame(width: 15, height: 15)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(labelColor)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundFill)
            )
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var iconColor: Color {
        if isSelected { return .white }
        return (hovered ? Color.gray(light: 0.14, dark: 0.92) : Color.gray(light: 0.27, dark: 0.78))
    }

    private var labelColor: Color {
        isSelected ? .white : Color.gray(light: 0.14, dark: 0.92)
    }

    private var backgroundFill: Color {
        if isSelected { return Color.overlay(0.06) }
        if hovered    { return Color.overlay(0.035) }
        return .clear
    }
}

struct ToolDragChipView: View {
    let entry: SidebarToolEntry
    let width: CGFloat
    let shadowInset: CGFloat
    @EnvironmentObject private var vault: SecretsManager

    var body: some View {
        HStack(spacing: 11) {
            iconView
                .frame(width: 15, height: 15)
            Text(entry.title)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(Color.gray(light: 0.23, dark: 0.82))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: ToolsReorderableList.rowSlotHeight)
        .background(
            ZStack {
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                Color.overlay(0.035)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        )
        .padding(.trailing, 3)
        .frame(width: width, alignment: .leading)
        .shadow(color: .black.opacity(0.22), radius: 9, x: 0, y: 4)
        .padding(shadowInset)
    }

    @ViewBuilder
    private var iconView: some View {
        switch entry.icon {
        case .system(let name):
            LucideIcon.auto(name, size: 13.5)
                .foregroundColor(Color.gray(light: 0.23, dark: 0.82))
        case .secrets:
            SecretsIcon(
                size: 13.8,
                lineWidth: 1.28,
                color: Color.gray(light: 0.23, dark: 0.82),
                isLocked: vault.state == .locked || vault.state == .unlocking
            )
        case .clawixLogo:
            ClawixLogoIcon(size: 13.5)
                .foregroundColor(Color.gray(light: 0.23, dark: 0.82))
        }
    }
}
