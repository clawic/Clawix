import AppKit
import ClawHostKit
import CommanderCore
import Foundation

@MainActor
final class SystemTelemetryStatusItemController {
    static let shared = SystemTelemetryStatusItemController()
    private static let combinedPanelItemID = "system.telemetry.combined-panel"

    private var model: SystemTelemetryMenuBarModel?
    private var items: [String: NSStatusItem] = [:]
    private var timer: Timer?
    private var isStarted = false
    private let monitorRecorder = SystemTelemetryMonitorRecorder()
    private let historyReader = SystemTelemetryHistoryReader()

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        model = SystemTelemetryMenuBarModel(
            bridge: .localStatusBridge(historyReader: historyReader),
            configuration: { SystemTelemetryMenuBarConfiguration.load() }
        )
        Task { await refreshNow() }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshNow()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        items.values.forEach { NSStatusBar.system.removeStatusItem($0) }
        items.removeAll()
        model = nil
        isStarted = false
    }

    private func refreshNow(forceHistory: Bool = false) async {
        guard let model else { return }
        await model.refresh(forceHistory: forceHistory)
        render(model: model)
        _ = await monitorRecorder.recordIfDue()
    }

    private func render(model: SystemTelemetryMenuBarModel) {
        let widgets = model.widgets
        var activeIDs = Set(widgets.map(\.id))
        if model.shouldShowCombinedPanel {
            activeIDs.insert(Self.combinedPanelItemID)
        }

        for staleID in items.keys where !activeIDs.contains(staleID) {
            if let item = items.removeValue(forKey: staleID) {
                NSStatusBar.system.removeStatusItem(item)
            }
        }

        for widget in widgets {
            let item = items[widget.id] ?? makeItem(for: widget)
            items[widget.id] = item
            let title = model.title(for: widget)
            item.button?.title = title
            item.button?.toolTip = widget.title
            item.button?.contentTintColor = Self.tintColor(for: model.severity(for: widget))
            item.menu = makeMenu(for: widget, model: model, title: title)
        }

        if model.shouldShowCombinedPanel {
            let item = items[Self.combinedPanelItemID] ?? makeCombinedPanelItem()
            items[Self.combinedPanelItemID] = item
            let title = model.combinedPanelTitle()
            item.button?.title = title
            item.button?.toolTip = "System indicators"
            item.button?.contentTintColor = Self.tintColor(for: model.combinedPanelSeverity())
            item.menu = makeCombinedPanelMenu(model: model, title: title)
        }
    }

    private func makeItem(for widget: SystemTelemetryWidget) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        item.button?.title = widget.title
        item.button?.toolTip = widget.title
        return item
    }

    private func makeCombinedPanelItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        item.button?.title = "System"
        item.button?.toolTip = "System indicators"
        return item
    }

    private func makeMenu(
        for widget: SystemTelemetryWidget,
        model: SystemTelemetryMenuBarModel,
        title: String
    ) -> NSMenu {
        let menu = NSMenu()
        let header = NSMenuItem(title: widget.title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        if let snapshot = model.snapshot {
            addHistoryGraphItems(to: menu, for: [widget], model: model)
            if model.hasHistoryGraph(for: widget) {
                menu.addItem(NSMenuItem.separator())
            }
            for key in widget.metricKeys {
                let value = snapshot.sample(for: key).map(Self.menuValue) ?? "Unavailable"
                let item = NSMenuItem(title: "\(shortMetricName(key)): \(value)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
            let updated = NSMenuItem(title: "Updated \(snapshot.capturedAt)", action: nil, keyEquivalent: "")
            updated.isEnabled = false
            menu.addItem(updated)
            if !snapshot.unavailableMetricKeys.isEmpty {
                let unavailable = NSMenuItem(
                    title: "\(snapshot.unavailableMetricKeys.count) metrics require host providers",
                    action: nil,
                    keyEquivalent: ""
                )
                unavailable.isEnabled = false
                menu.addItem(unavailable)
            }
            addProviderItems(to: menu, model: model)
            addPanelItems(to: menu, model: model, currentWidgetID: widget.id)
        } else {
            let loading = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            loading.isEnabled = false
            menu.addItem(loading)
        }

        menu.addItem(NSMenuItem.separator())
        if addWidgetConfigurationItems(to: menu, model: model) {
            menu.addItem(NSMenuItem.separator())
        }
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        return menu
    }

    private func makeCombinedPanelMenu(model: SystemTelemetryMenuBarModel, title: String) -> NSMenu {
        let menu = NSMenu()
        let header = NSMenuItem(title: "System indicators", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        let rows = model.combinedPanelRows(limit: 12)
        if rows.isEmpty {
            let empty = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for row in rows {
                let item = NSMenuItem(title: row, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        if let snapshot = model.snapshot {
            addHistoryGraphItems(to: menu, for: model.panelWidgets, model: model, limit: 3)
            menu.addItem(NSMenuItem.separator())
            let updated = NSMenuItem(title: "Updated \(snapshot.capturedAt)", action: nil, keyEquivalent: "")
            updated.isEnabled = false
            menu.addItem(updated)
            if !snapshot.unavailableMetricKeys.isEmpty {
                let unavailable = NSMenuItem(
                    title: "\(snapshot.unavailableMetricKeys.count) metrics require host providers",
                    action: nil,
                    keyEquivalent: ""
                )
                unavailable.isEnabled = false
                menu.addItem(unavailable)
            }
        }

        addProviderItems(to: menu, model: model)
        menu.addItem(NSMenuItem.separator())
        if addWidgetConfigurationItems(to: menu, model: model) {
            menu.addItem(NSMenuItem.separator())
        }
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        return menu
    }

    private func addProviderItems(to menu: NSMenu, model: SystemTelemetryMenuBarModel) {
        let rows = model.providerStatusRows(limit: 6)
        guard !rows.isEmpty else { return }
        menu.addItem(NSMenuItem.separator())
        let header = NSMenuItem(title: "Providers", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for row in rows {
            let item = NSMenuItem(title: row, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    private func addHistoryGraphItems(
        to menu: NSMenu,
        for widgets: [SystemTelemetryWidget],
        model: SystemTelemetryMenuBarModel,
        limit: Int = 1
    ) {
        var added = 0
        for widget in widgets where added < limit {
            guard let history = model.historyGraph(for: widget) else { continue }
            let item = NSMenuItem(title: "\(widget.title) history graph", action: nil, keyEquivalent: "")
            item.view = SystemTelemetryHistoryGraphView(history: history, title: widget.title)
            item.isEnabled = false
            menu.addItem(item)
            added += 1
        }
    }

    private func addWidgetConfigurationItems(to menu: NSMenu, model: SystemTelemetryMenuBarModel) -> Bool {
        guard !model.allWidgets.isEmpty else { return false }
        let header = NSMenuItem(title: "Menu bar indicators", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let configuration = SystemTelemetryMenuBarConfiguration.load()
        let enabledIDs = configuration.enabledWidgetIDs(for: model.allWidgets)
        for widget in model.allWidgets {
            let item = NSMenuItem(title: widget.title, action: #selector(toggleWidgetFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = widget.id
            item.state = enabledIDs.contains(widget.id) ? .on : .off
            menu.addItem(item)
        }

        let reset = NSMenuItem(title: "Reset indicators", action: #selector(resetWidgetConfigurationFromMenu), keyEquivalent: "")
        reset.target = self
        reset.isEnabled = configuration.enabledWidgetIDs != nil
        menu.addItem(reset)
        return true
    }

    private func addPanelItems(to menu: NSMenu, model: SystemTelemetryMenuBarModel, currentWidgetID: String) {
        let panelWidgets = model.panelWidgets.filter { $0.id != currentWidgetID }
        guard !panelWidgets.isEmpty else { return }
        menu.addItem(NSMenuItem.separator())
        let header = NSMenuItem(title: "Combined panel", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for panelWidget in panelWidgets {
            let item = NSMenuItem(title: model.title(for: panelWidget), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    @objc private func refreshFromMenu() {
        Task { await refreshNow(forceHistory: true) }
    }

    @objc private func toggleWidgetFromMenu(_ sender: NSMenuItem) {
        guard let widgetID = sender.representedObject as? String,
              let model else { return }
        let next = SystemTelemetryMenuBarConfiguration
            .load()
            .toggling(widgetID: widgetID, widgets: model.allWidgets)
        next.save()
        Task { await refreshNow(forceHistory: true) }
    }

    @objc private func resetWidgetConfigurationFromMenu() {
        SystemTelemetryMenuBarConfiguration.default.save()
        Task { await refreshNow(forceHistory: true) }
    }

    private static func menuValue(_ sample: SystemTelemetrySample) -> String {
        if let stringValue = sample.stringValue {
            return truncate(stringValue, limit: 64)
        }
        switch sample.unit {
        case "bytes":
            return ByteCountFormatter.string(fromByteCount: Int64(sample.value), countStyle: .memory)
        case "seconds":
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.day, .hour, .minute]
            formatter.unitsStyle = .abbreviated
            return formatter.string(from: sample.value) ?? "\(Int(sample.value))s"
        case "load":
            return String(format: "%.2f", sample.value)
        case "percent":
            return "\(Int(sample.value.rounded()))%"
        default:
            return String(format: "%.0f %@", sample.value, sample.unit)
        }
    }

    private static func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let end = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<end])
    }

    private static func tintColor(for severity: SystemTelemetryMenuBarSeverity) -> NSColor? {
        switch severity {
        case .normal:
            return nil
        case .warning:
            return .systemOrange
        case .critical:
            return .systemRed
        case .unavailable:
            return .secondaryLabelColor
        }
    }

    private func shortMetricName(_ key: String) -> String {
        key
            .replacingOccurrences(of: "system.", with: "")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

}
