import AppKit
import ClawHostKit
import CommanderCore
import Foundation

@MainActor
final class SystemTelemetryStatusItemController {
    static let shared = SystemTelemetryStatusItemController()

    private var model: SystemTelemetryMenuBarModel?
    private var items: [String: NSStatusItem] = [:]
    private var timer: Timer?
    private var isStarted = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        model = SystemTelemetryMenuBarModel(bridge: SystemTelemetryBridge(execute: { request in
            let data: CommanderCore.JSONValue
            switch (request.resource, request.action) {
            case ("telemetry", "snapshot"), ("snapshot", "get"):
                data = SystemTelemetry.snapshot()
            case ("widgets", "list"):
                data = SystemTelemetry.defaultWidgets()
            default:
                return CommandResponse(
                    ok: false,
                    data: nil,
                    error: CommanderError.invalidCommand("Unsupported system telemetry status item request").payload,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            }
            return CommandResponse(
                ok: true,
                data: data,
                error: nil,
                meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
            )
        }))
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

    private func refreshNow() async {
        guard let model else { return }
        await model.refresh()
        render(model: model)
    }

    private func render(model: SystemTelemetryMenuBarModel) {
        let widgets = model.widgets
        let activeIDs = Set(widgets.map(\.id))

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
            item.menu = makeMenu(for: widget, model: model, title: title)
        }
    }

    private func makeItem(for widget: SystemTelemetryWidget) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        item.button?.title = widget.title
        item.button?.toolTip = widget.title
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
        } else {
            let loading = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            loading.isEnabled = false
            menu.addItem(loading)
        }

        menu.addItem(NSMenuItem.separator())
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        return menu
    }

    @objc private func refreshFromMenu() {
        Task { await refreshNow() }
    }

    private static func menuValue(_ sample: SystemTelemetrySample) -> String {
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

    private func shortMetricName(_ key: String) -> String {
        key
            .replacingOccurrences(of: "system.", with: "")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

}
