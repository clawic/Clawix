import AppKit
import ApplicationServices

/// Thin helpers over the accessibility API pointed at THIS process. An app can
/// introspect and act on its own accessibility tree without the Accessibility
/// (TCC) grant that controlling foreign apps requires, so this is the primary,
/// cursor-free, background-safe way an agent instance drives its own UI.
enum ClxAX {
    /// SwiftUI's `accessibilityIdentifier` surfaces as the "AXIdentifier"
    /// attribute; there is no public `kAX…` constant for it.
    static let identifierAttribute = "AXIdentifier"

    static func appElement() -> AXUIElement {
        AXUIElementCreateApplication(getpid())
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            // swiftlint:disable:next force_cast
            return CFBooleanGetValue((value as! CFBoolean))
        }
        return (value as? NSNumber)?.boolValue
    }

    static func number(_ element: AXUIElement, _ attribute: String) -> Double? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    static func setNumber(_ element: AXUIElement, _ attribute: String, _ number: Double) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, NSNumber(value: number)) == .success
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return (value as? [AXUIElement]) ?? []
    }

    /// Frame in screen coordinates (top-left origin, as AX reports it).
    static func frame(_ element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        // swiftlint:enable force_cast
        return CGRect(origin: point, size: size)
    }

    /// Depth-first walk with a node cap so a pathological tree can't run away.
    static func walk(_ root: AXUIElement, maxNodes: Int = 4000, _ visit: (AXUIElement, Int) -> Void) {
        var count = 0
        func recurse(_ element: AXUIElement, _ depth: Int) {
            if count >= maxNodes { return }
            count += 1
            visit(element, depth)
            for child in children(element) {
                if count >= maxNodes { return }
                recurse(child, depth + 1)
            }
        }
        recurse(root, 0)
    }

    /// First element whose AXIdentifier matches, searching this process's tree.
    static func find(identifier: String) -> AXUIElement? {
        var found: AXUIElement?
        walk(appElement()) { element, _ in
            guard found == nil else { return }
            if string(element, identifierAttribute) == identifier { found = element }
        }
        return found
    }

    static let pressableRoles: Set<String> = [
        "AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXLink",
    ]

    /// First pressable element whose visible title (or description) matches.
    /// Lets an agent click a labelled control even when it has no stable id.
    static func findPressable(title: String) -> AXUIElement? {
        var found: AXUIElement?
        walk(appElement()) { element, _ in
            guard found == nil else { return }
            guard let role = string(element, kAXRoleAttribute), pressableRoles.contains(role) else { return }
            let label = string(element, kAXTitleAttribute) ?? string(element, kAXDescriptionAttribute)
            if label == title { found = element }
        }
        return found
    }

    static func findScrollArea(target: String?) -> AXUIElement? {
        var found: AXUIElement?
        walk(appElement()) { element, _ in
            guard found == nil else { return }
            guard string(element, kAXRoleAttribute) == "AXScrollArea" else { return }
            if target == "sidebar" {
                guard let frame = frame(element), frame.width <= 500, frame.height >= 200 else { return }
            }
            found = element
        }
        return found
    }

    static func firstDescendant(of root: AXUIElement, role targetRole: String) -> AXUIElement? {
        var found: AXUIElement?
        func recurse(_ element: AXUIElement) {
            guard found == nil else { return }
            if string(element, kAXRoleAttribute) == targetRole {
                found = element
                return
            }
            for child in children(element) {
                recurse(child)
                if found != nil { return }
            }
        }
        recurse(root)
        return found
    }
}
