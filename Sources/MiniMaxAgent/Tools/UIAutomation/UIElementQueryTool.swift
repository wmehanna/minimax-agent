import AppKit
import ApplicationServices
import Foundation

// MARK: - UIElement

/// Represents a UI element retrieved via the macOS Accessibility API.
public struct UIElement: Sendable, Equatable, Identifiable {
    /// Unique identifier derived from the element's role and title
    public let id: String

    /// AX role (e.g. "AXButton", "AXTextField")
    public let role: String

    /// Human-readable title or label
    public let title: String?

    /// Current value (text content, toggle state, etc.)
    public let value: String?

    /// Whether the element is currently enabled
    public let isEnabled: Bool

    /// Whether the element is focused
    public let isFocused: Bool

    /// Bounding frame in screen coordinates
    public let frame: CGRect

    /// Child elements (one level deep)
    public let children: [UIElement]

    public init(
        id: String,
        role: String,
        title: String?,
        value: String?,
        isEnabled: Bool,
        isFocused: Bool,
        frame: CGRect,
        children: [UIElement] = []
    ) {
        self.id = id
        self.role = role
        self.title = title
        self.value = value
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.frame = frame
        self.children = children
    }
}

// MARK: - UIElementQuery

/// Criteria for filtering UI elements.
public struct UIElementQuery: Sendable {
    /// Filter by AX role (e.g. "AXButton")
    public let role: String?

    /// Filter by title (substring match, case-insensitive)
    public let titleContains: String?

    /// Filter by value (substring match, case-insensitive)
    public let valueContains: String?

    /// Restrict to enabled elements only
    public let enabledOnly: Bool

    /// Maximum number of results (0 = unlimited)
    public let limit: Int

    public init(
        role: String? = nil,
        titleContains: String? = nil,
        valueContains: String? = nil,
        enabledOnly: Bool = false,
        limit: Int = 0
    ) {
        self.role = role
        self.titleContains = titleContains
        self.valueContains = valueContains
        self.enabledOnly = enabledOnly
        self.limit = limit
    }
}

// MARK: - UIElementAction

/// Actions that can be performed on a UI element.
public enum UIElementAction: String, Sendable, CaseIterable {
    case press = "AXPress"
    case showMenu = "AXShowMenu"
    case raise = "AXRaise"
    case increment = "AXIncrement"
    case decrement = "AXDecrement"
    case confirm = "AXConfirm"
    case cancel = "AXCancel"
    case pick = "AXPick"
}

// MARK: - UIElementInteractionResult

/// Result of a UI element interaction.
public struct UIElementInteractionResult: Sendable {
    public let action: UIElementAction
    public let elementRole: String
    public let elementTitle: String?
    public let success: Bool
    public let errorDescription: String?

    public init(
        action: UIElementAction,
        elementRole: String,
        elementTitle: String?,
        success: Bool,
        errorDescription: String? = nil
    ) {
        self.action = action
        self.elementRole = elementRole
        self.elementTitle = elementTitle
        self.success = success
        self.errorDescription = errorDescription
    }
}

// MARK: - UIElementQueryError

public enum UIElementQueryError: Error, LocalizedError, Sendable {
    case accessibilityPermissionDenied
    case applicationNotFound(bundleID: String)
    case elementNotFound
    case actionFailed(action: String, axError: Int32)
    case invalidTarget

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission denied. Grant access in System Settings > Privacy & Security > Accessibility."
        case .applicationNotFound(let id):
            return "Application not found: \(id)"
        case .elementNotFound:
            return "No UI element matching the query was found"
        case .actionFailed(let action, let code):
            return "Action '\(action)' failed with AX error code \(code)"
        case .invalidTarget:
            return "Target element is no longer valid"
        }
    }
}

// MARK: - UIElementQueryTool

/// Tool for querying and interacting with UI elements via the macOS Accessibility API.
///
/// Phase 9 / Section 9.2 — UI element query and interaction
///
/// Usage:
/// ```swift
/// let tool = UIElementQueryTool()
///
/// // Query all buttons in the frontmost app
/// let buttons = try tool.queryFrontmostApp(query: UIElementQuery(role: "AXButton"))
///
/// // Click the first "OK" button
/// if let ok = buttons.first(where: { $0.title == "OK" }) {
///     try tool.perform(.press, on: ok)
/// }
/// ```
public struct UIElementQueryTool: Sendable {

    public init() {}

    // MARK: - Accessibility Check

    /// Returns true if Accessibility API access is granted.
    public func isAccessibilityEnabled() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Query

    /// Query UI elements from the frontmost application.
    /// - Parameter query: The filter criteria
    /// - Returns: Matching UI elements in top-down traversal order
    /// - Throws: UIElementQueryError
    public func queryFrontmostApp(query: UIElementQuery = UIElementQuery()) throws -> [UIElement] {
        guard isAccessibilityEnabled() else {
            throw UIElementQueryError.accessibilityPermissionDenied
        }

        let systemElement = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemElement, kAXFocusedApplicationAttribute as CFString, &focusedApp)

        guard result == .success, let appRef = focusedApp else {
            throw UIElementQueryError.elementNotFound
        }

        // swiftlint:disable:next force_cast
        let appElement = appRef as! AXUIElement
        return try collectElements(from: appElement, query: query, depth: 0, maxDepth: 10)
    }

    /// Query UI elements from a specific application by bundle ID.
    /// - Parameters:
    ///   - bundleID: The target app's bundle identifier
    ///   - query: The filter criteria
    /// - Returns: Matching UI elements
    /// - Throws: UIElementQueryError
    public func queryApplication(bundleID: String, query: UIElementQuery = UIElementQuery()) throws -> [UIElement] {
        guard isAccessibilityEnabled() else {
            throw UIElementQueryError.accessibilityPermissionDenied
        }

        guard let app = runningApplication(bundleID: bundleID) else {
            throw UIElementQueryError.applicationNotFound(bundleID: bundleID)
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        return try collectElements(from: appElement, query: query, depth: 0, maxDepth: 10)
    }

    // MARK: - Interaction

    /// Perform an action on a UI element.
    /// - Parameters:
    ///   - action: The action to perform
    ///   - element: The target element (use the element's `id` to re-look it up if needed)
    ///   - bundleID: If provided, resolves the element from this app; otherwise uses frontmost app
    /// - Returns: Interaction result
    /// - Throws: UIElementQueryError
    @discardableResult
    public func perform(_ action: UIElementAction, onElementWithTitle title: String, role: String? = nil, bundleID: String? = nil) throws -> UIElementInteractionResult {
        guard isAccessibilityEnabled() else {
            throw UIElementQueryError.accessibilityPermissionDenied
        }

        let query = UIElementQuery(role: role, titleContains: title, enabledOnly: true, limit: 1)
        let elements: [UIElement]

        if let bid = bundleID {
            elements = try queryApplication(bundleID: bid, query: query)
        } else {
            elements = try queryFrontmostApp(query: query)
        }

        guard let element = elements.first else {
            throw UIElementQueryError.elementNotFound
        }

        return try performAction(action, onElement: element, bundleID: bundleID)
    }

    /// Perform an action directly using a resolved UIElement.
    /// - Parameters:
    ///   - action: The action to perform
    ///   - element: The resolved element
    ///   - bundleID: Optional bundle ID for resolving the AXUIElement
    /// - Returns: Interaction result
    @discardableResult
    public func performAction(_ action: UIElementAction, onElement element: UIElement, bundleID: String? = nil) throws -> UIElementInteractionResult {
        guard isAccessibilityEnabled() else {
            throw UIElementQueryError.accessibilityPermissionDenied
        }

        // Re-resolve the AXUIElement from the app
        let query = UIElementQuery(role: element.role, titleContains: element.title, limit: 1)
        let candidates: [AXUIElement]

        if let bid = bundleID, let app = runningApplication(bundleID: bid) {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            candidates = rawElements(from: appElement, matching: query, depth: 0, maxDepth: 10)
        } else {
            let systemElement = AXUIElementCreateSystemWide()
            var focusedApp: CFTypeRef?
            guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
                  let appRef = focusedApp else {
                throw UIElementQueryError.elementNotFound
            }
            // swiftlint:disable:next force_cast
            let appElement = appRef as! AXUIElement
            candidates = rawElements(from: appElement, matching: query, depth: 0, maxDepth: 10)
        }

        guard let axElement = candidates.first else {
            throw UIElementQueryError.invalidTarget
        }

        let axResult = AXUIElementPerformAction(axElement, action.rawValue as CFString)
        let success = axResult == .success

        return UIElementInteractionResult(
            action: action,
            elementRole: element.role,
            elementTitle: element.title,
            success: success,
            errorDescription: success ? nil : "AX error \(axResult.rawValue)"
        )
    }

    /// Set a value on a text field or other settable element.
    /// - Parameters:
    ///   - value: The new value to set
    ///   - title: Title/label of the target element
    ///   - bundleID: Optional bundle ID
    public func setValue(_ value: String, onElementWithTitle title: String, bundleID: String? = nil) throws {
        guard isAccessibilityEnabled() else {
            throw UIElementQueryError.accessibilityPermissionDenied
        }

        let query = UIElementQuery(titleContains: title, limit: 1)
        let candidates: [AXUIElement]

        if let bid = bundleID, let app = runningApplication(bundleID: bid) {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            candidates = rawElements(from: appElement, matching: query, depth: 0, maxDepth: 10)
        } else {
            let systemElement = AXUIElementCreateSystemWide()
            var focusedApp: CFTypeRef?
            guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
                  let appRef = focusedApp else {
                throw UIElementQueryError.elementNotFound
            }
            // swiftlint:disable:next force_cast
            let appElement = appRef as! AXUIElement
            candidates = rawElements(from: appElement, matching: query, depth: 0, maxDepth: 10)
        }

        guard let axElement = candidates.first else {
            throw UIElementQueryError.elementNotFound
        }

        AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, value as CFTypeRef)
    }

    // MARK: - Private Helpers

    private func runningApplication(bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    private func frameAttribute(_ element: AXUIElement) -> CGRect {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        var position = CGPoint.zero
        var size = CGSize.zero

        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
           let posAXValue = posValue {
            AXValueGetValue(posAXValue as! AXValue, AXValueType.cgPoint, &position)
        }

        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let sizeAXValue = sizeValue {
            AXValueGetValue(sizeAXValue as! AXValue, AXValueType.cgSize, &size)
        }

        return CGRect(origin: position, size: size)
    }

    private func childElements(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return []
        }
        return children
    }

    private func makeUIElement(_ axElement: AXUIElement, children: [UIElement] = []) -> UIElement? {
        guard let role = stringAttribute(axElement, kAXRoleAttribute as String) else { return nil }

        let title = stringAttribute(axElement, kAXTitleAttribute as String)
        let value = stringAttribute(axElement, kAXValueAttribute as String)
        let isEnabled = boolAttribute(axElement, kAXEnabledAttribute as String)
        let isFocused = boolAttribute(axElement, kAXFocusedAttribute as String)
        let frame = frameAttribute(axElement)

        let idSource = "\(role)|\(title ?? "")|\(frame.origin.x)|\(frame.origin.y)"
        let id = String(idSource.hashValue)

        return UIElement(
            id: id,
            role: role,
            title: title,
            value: value,
            isEnabled: isEnabled,
            isFocused: isFocused,
            frame: frame,
            children: children
        )
    }

    private func matches(_ element: AXUIElement, query: UIElementQuery) -> Bool {
        if let roleFilter = query.role {
            guard let role = stringAttribute(element, kAXRoleAttribute as String),
                  role == roleFilter else { return false }
        }

        if let titleFilter = query.titleContains {
            guard let title = stringAttribute(element, kAXTitleAttribute as String),
                  title.localizedCaseInsensitiveContains(titleFilter) else { return false }
        }

        if let valueFilter = query.valueContains {
            guard let value = stringAttribute(element, kAXValueAttribute as String),
                  value.localizedCaseInsensitiveContains(valueFilter) else { return false }
        }

        if query.enabledOnly {
            guard boolAttribute(element, kAXEnabledAttribute as String) else { return false }
        }

        return true
    }

    private func collectElements(from axElement: AXUIElement, query: UIElementQuery, depth: Int, maxDepth: Int) throws -> [UIElement] {
        var results: [UIElement] = []

        if query.limit > 0 && results.count >= query.limit { return results }

        if matches(axElement, query: query) {
            let childUIElements = depth < maxDepth
                ? (try? collectChildren(of: axElement, query: UIElementQuery(), depth: depth + 1, maxDepth: depth + 1)) ?? []
                : []

            if let uiElement = makeUIElement(axElement, children: childUIElements) {
                results.append(uiElement)
            }
        }

        if depth < maxDepth {
            for child in childElements(axElement) {
                if query.limit > 0 && results.count >= query.limit { break }
                let childResults = try collectElements(from: child, query: query, depth: depth + 1, maxDepth: maxDepth)
                results.append(contentsOf: childResults)
            }
        }

        return results
    }

    private func collectChildren(of axElement: AXUIElement, query: UIElementQuery, depth: Int, maxDepth: Int) throws -> [UIElement] {
        var results: [UIElement] = []
        for child in childElements(axElement) {
            if let uiElement = makeUIElement(child) {
                results.append(uiElement)
            }
        }
        return results
    }

    private func rawElements(from axElement: AXUIElement, matching query: UIElementQuery, depth: Int, maxDepth: Int) -> [AXUIElement] {
        var results: [AXUIElement] = []

        if query.limit > 0 && results.count >= query.limit { return results }

        if matches(axElement, query: query) {
            results.append(axElement)
        }

        if depth < maxDepth {
            for child in childElements(axElement) {
                if query.limit > 0 && results.count >= query.limit { break }
                results.append(contentsOf: rawElements(from: child, matching: query, depth: depth + 1, maxDepth: maxDepth))
            }
        }

        return results
    }
}

// MARK: - Tool Protocol Conformance

extension UIElementQueryTool: Tool {
    public var toolIdentifier: String { "ui-element-query" }
    public var toolName: String { "UIElementQuery" }
    public var toolCategory: String { "UIAutomation" }
}
