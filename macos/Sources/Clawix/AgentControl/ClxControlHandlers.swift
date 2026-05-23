import AppKit
import ApplicationServices

struct ClxControlResult {
    let status: Int
    let json: [String: Any]
}

/// The control verbs an agent instance exposes over its loopback endpoint. All
/// run on the main actor (they touch the UI / accessibility tree). Actions
/// prefer the accessibility path (which runs the control's real action, e.g. a
/// SwiftUI Button's closure, with no cursor and no foreground requirement) and
/// fall back to the registered closure when accessibility cannot reach it.
@MainActor
enum ClxControlHandlers {
    static func handle(verb: String, args: [String: Any]) -> ClxControlResult {
        switch verb {
        case "ping":      return ok(["ok": true, "instanceId": ClxAgentInstance.instanceId])
        case "inventory": return inventory()
        case "click":     return click(args)
        case "type":      return typeText(args)
        case "state":     return state(args)
        case "capture":   return capture(args)
        case "close":     return closeWindow(args)
        case "quit":      return quitApp()
        default:          return ClxControlResult(status: 404, json: ["error": "unknown verb: \(verb)"])
        }
    }

    private static func ok(_ json: [String: Any]) -> ClxControlResult { ClxControlResult(status: 200, json: json) }
    private static func badRequest(_ message: String) -> ClxControlResult {
        ClxControlResult(status: 400, json: ["error": message])
    }

    private static let actionableRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXTextArea",
        "AXPopUpButton", "AXMenuButton", "AXSlider", "AXTabGroup", "AXLink",
        "AXSegmentedControl", "AXDisclosureTriangle", "AXComboBox",
    ]

    static func inventory() -> ClxControlResult {
        var controls: [[String: Any]] = []
        ClxAX.walk(ClxAX.appElement()) { element, depth in
            let id = ClxAX.string(element, ClxAX.identifierAttribute)
            let role = ClxAX.string(element, kAXRoleAttribute)
            let hasId = (id?.isEmpty == false)
            let isActionable = role.map { actionableRoles.contains($0) } ?? false
            guard hasId || isActionable else { return }
            var item: [String: Any] = ["depth": depth]
            if let id { item["id"] = id }
            if let role { item["role"] = role }
            if let title = ClxAX.string(element, kAXTitleAttribute) { item["title"] = title }
            if let description = ClxAX.string(element, kAXDescriptionAttribute) { item["description"] = description }
            if let value = ClxAX.string(element, kAXValueAttribute) { item["value"] = value }
            if let enabled = ClxAX.bool(element, kAXEnabledAttribute) { item["enabled"] = enabled }
            if let frame = ClxAX.frame(element) {
                item["frame"] = ["x": frame.origin.x, "y": frame.origin.y, "w": frame.size.width, "h": frame.size.height]
            }
            controls.append(item)
        }
        let known = Set(controls.compactMap { $0["id"] as? String })
        for descriptor in ClxControlRegistry.shared.all() where !known.contains(descriptor.id) {
            controls.append(["id": descriptor.id, "role": descriptor.role, "title": descriptor.label, "source": "registry"])
        }
        return ok(["instanceId": ClxAgentInstance.instanceId, "count": controls.count, "controls": controls])
    }

    static func click(_ args: [String: Any]) -> ClxControlResult {
        if let id = args["id"] as? String {
            if let element = ClxAX.find(identifier: id),
               AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
                return ok(["clicked": id, "via": "ax"])
            }
            if let descriptor = ClxControlRegistry.shared.get(id), let activate = descriptor.activate {
                activate()
                return ok(["clicked": id, "via": "closure"])
            }
            return ClxControlResult(status: 404, json: ["error": "control not found or not pressable: \(id)"])
        }
        if let title = args["title"] as? String {
            if let element = ClxAX.findPressable(title: title),
               AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
                return ok(["clicked": title, "via": "ax-title"])
            }
            return ClxControlResult(status: 404, json: ["error": "no pressable control titled: \(title)"])
        }
        return badRequest("missing id or title")
    }

    static func typeText(_ args: [String: Any]) -> ClxControlResult {
        guard let id = args["id"] as? String else { return badRequest("missing id") }
        guard let text = args["text"] as? String else { return badRequest("missing text") }
        if let element = ClxAX.find(identifier: id) {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString) == .success {
                return ok(["typed": id, "via": "ax"])
            }
        }
        if let descriptor = ClxControlRegistry.shared.get(id), let setValue = descriptor.setValue {
            setValue(text)
            return ok(["typed": id, "via": "closure"])
        }
        return ClxControlResult(status: 404, json: ["error": "control not found or not settable: \(id)"])
    }

    static func state(_ args: [String: Any]) -> ClxControlResult {
        guard let id = args["id"] as? String else { return badRequest("missing id") }
        guard let element = ClxAX.find(identifier: id) else {
            if ClxControlRegistry.shared.get(id) != nil { return ok(["id": id, "source": "registry"]) }
            return ClxControlResult(status: 404, json: ["error": "control not found: \(id)"])
        }
        var out: [String: Any] = ["id": id]
        if let role = ClxAX.string(element, kAXRoleAttribute) { out["role"] = role }
        if let value = ClxAX.string(element, kAXValueAttribute) { out["value"] = value }
        if let enabled = ClxAX.bool(element, kAXEnabledAttribute) { out["enabled"] = enabled }
        if let title = ClxAX.string(element, kAXTitleAttribute) { out["title"] = title }
        return ok(out)
    }

    static func capture(_ args: [String: Any]) -> ClxControlResult {
        let windowNumber = args["window"] as? Int
        let controlId = args["id"] as? String
        guard let data = ClxWindowCapture.capturePNG(windowNumber: windowNumber, controlId: controlId) else {
            return ClxControlResult(status: 500, json: ["error": "capture failed (no window?)"])
        }
        let outURL: URL
        if let path = args["path"] as? String, !path.isEmpty {
            outURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            let dir = ClawixPersistentSurfacePaths.homeChild("captures")
            outURL = dir.appendingPathComponent("capture-\(Int(Date().timeIntervalSince1970 * 1000)).png")
        }
        do {
            try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: outURL)
            return ok(["path": outURL.path, "bytes": data.count])
        } catch {
            return ClxControlResult(status: 500, json: ["error": "write failed: \(error.localizedDescription)"])
        }
    }

    static func closeWindow(_ args: [String: Any]) -> ClxControlResult {
        let target: NSWindow?
        if let number = args["window"] as? Int {
            target = NSApp.windows.first { $0.windowNumber == number }
        } else {
            target = NSApp.keyWindow ?? NSApp.windows.first
        }
        guard let window = target else { return ClxControlResult(status: 404, json: ["error": "no window"]) }
        window.performClose(nil)
        return ok(["closed": window.windowNumber])
    }

    static func quitApp() -> ClxControlResult {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.terminate(nil) }
        return ok(["quitting": true])
    }
}
