import XCTest
@testable import MiniMaxAgent

final class UIElementQueryToolTests: XCTestCase {

    private let tool = UIElementQueryTool()

    // MARK: - Tool Protocol

    func testToolIdentifier() {
        XCTAssertEqual(tool.toolIdentifier, "ui-element-query")
    }

    func testToolName() {
        XCTAssertEqual(tool.toolName, "UIElementQuery")
    }

    func testToolCategory() {
        XCTAssertEqual(tool.toolCategory, "UIAutomation")
    }

    // MARK: - UIElementQuery

    func testQueryDefaultValues() {
        let query = UIElementQuery()
        XCTAssertNil(query.role)
        XCTAssertNil(query.titleContains)
        XCTAssertNil(query.valueContains)
        XCTAssertFalse(query.enabledOnly)
        XCTAssertEqual(query.limit, 0)
    }

    func testQueryWithAllParameters() {
        let query = UIElementQuery(
            role: "AXButton",
            titleContains: "OK",
            valueContains: "checked",
            enabledOnly: true,
            limit: 5
        )
        XCTAssertEqual(query.role, "AXButton")
        XCTAssertEqual(query.titleContains, "OK")
        XCTAssertEqual(query.valueContains, "checked")
        XCTAssertTrue(query.enabledOnly)
        XCTAssertEqual(query.limit, 5)
    }

    // MARK: - UIElement

    func testUIElementInitialization() {
        let element = UIElement(
            id: "test-id",
            role: "AXButton",
            title: "Cancel",
            value: nil,
            isEnabled: true,
            isFocused: false,
            frame: CGRect(x: 10, y: 20, width: 80, height: 30)
        )

        XCTAssertEqual(element.id, "test-id")
        XCTAssertEqual(element.role, "AXButton")
        XCTAssertEqual(element.title, "Cancel")
        XCTAssertNil(element.value)
        XCTAssertTrue(element.isEnabled)
        XCTAssertFalse(element.isFocused)
        XCTAssertEqual(element.frame, CGRect(x: 10, y: 20, width: 80, height: 30))
        XCTAssertTrue(element.children.isEmpty)
    }

    func testUIElementWithChildren() {
        let child = UIElement(
            id: "child-id",
            role: "AXStaticText",
            title: "Label",
            value: nil,
            isEnabled: true,
            isFocused: false,
            frame: .zero
        )

        let parent = UIElement(
            id: "parent-id",
            role: "AXGroup",
            title: nil,
            value: nil,
            isEnabled: true,
            isFocused: false,
            frame: .zero,
            children: [child]
        )

        XCTAssertEqual(parent.children.count, 1)
        XCTAssertEqual(parent.children.first?.role, "AXStaticText")
    }

    func testUIElementEquality() {
        let a = UIElement(id: "same-id", role: "AXButton", title: "OK", value: nil, isEnabled: true, isFocused: false, frame: .zero)
        let b = UIElement(id: "same-id", role: "AXButton", title: "OK", value: nil, isEnabled: true, isFocused: false, frame: .zero)
        let c = UIElement(id: "other-id", role: "AXButton", title: "Cancel", value: nil, isEnabled: true, isFocused: false, frame: .zero)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - UIElementAction

    func testUIElementActionRawValues() {
        XCTAssertEqual(UIElementAction.press.rawValue, "AXPress")
        XCTAssertEqual(UIElementAction.showMenu.rawValue, "AXShowMenu")
        XCTAssertEqual(UIElementAction.raise.rawValue, "AXRaise")
        XCTAssertEqual(UIElementAction.increment.rawValue, "AXIncrement")
        XCTAssertEqual(UIElementAction.decrement.rawValue, "AXDecrement")
        XCTAssertEqual(UIElementAction.confirm.rawValue, "AXConfirm")
        XCTAssertEqual(UIElementAction.cancel.rawValue, "AXCancel")
        XCTAssertEqual(UIElementAction.pick.rawValue, "AXPick")
    }

    func testAllActionsAreCaseIterable() {
        XCTAssertEqual(UIElementAction.allCases.count, 8)
    }

    // MARK: - UIElementInteractionResult

    func testInteractionResultSuccess() {
        let result = UIElementInteractionResult(
            action: .press,
            elementRole: "AXButton",
            elementTitle: "OK",
            success: true
        )

        XCTAssertEqual(result.action, .press)
        XCTAssertEqual(result.elementRole, "AXButton")
        XCTAssertEqual(result.elementTitle, "OK")
        XCTAssertTrue(result.success)
        XCTAssertNil(result.errorDescription)
    }

    func testInteractionResultFailure() {
        let result = UIElementInteractionResult(
            action: .press,
            elementRole: "AXButton",
            elementTitle: "Disabled",
            success: false,
            errorDescription: "AX error -25212"
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorDescription, "AX error -25212")
    }

    // MARK: - UIElementQueryError

    func testErrorDescriptions() {
        XCTAssertNotNil(UIElementQueryError.accessibilityPermissionDenied.errorDescription)
        XCTAssertNotNil(UIElementQueryError.applicationNotFound(bundleID: "com.example.app").errorDescription)
        XCTAssertNotNil(UIElementQueryError.elementNotFound.errorDescription)
        XCTAssertNotNil(UIElementQueryError.actionFailed(action: "AXPress", axError: -25212).errorDescription)
        XCTAssertNotNil(UIElementQueryError.invalidTarget.errorDescription)
    }

    func testErrorDescriptionContainsBundleID() {
        let error = UIElementQueryError.applicationNotFound(bundleID: "com.example.myapp")
        XCTAssertTrue(error.errorDescription?.contains("com.example.myapp") ?? false)
    }

    // MARK: - Tool Registration

    func testToolCanBeRegisteredInRegistry() async throws {
        let registry = OrderedToolRegistry()
        let queryTool = UIElementQueryTool()

        try await registry.register(queryTool)

        let state = await registry.state()
        XCTAssertEqual(state.toolCount, 1)
        XCTAssertEqual(state.categories, ["UIAutomation"])
    }

    func testToolLookupByName() async throws {
        let registry = OrderedToolRegistry()
        try await registry.register(UIElementQueryTool())

        let found = await registry.tool(named: "UIElementQuery")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.identifier, "ui-element-query")
    }

    func testToolLookupByID() async throws {
        let registry = OrderedToolRegistry()
        try await registry.register(UIElementQueryTool())

        let found = await registry.tool(id: "ui-element-query")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.category, "UIAutomation")
    }

    // MARK: - Accessibility Check

    func testIsAccessibilityEnabledReturnsBool() {
        // This just verifies the method runs without crashing in a test environment.
        // The actual return value depends on system permissions.
        let _ = tool.isAccessibilityEnabled()
    }

    // MARK: - Query Without Accessibility (permission denied path)

    func testQueryFrontmostAppThrowsWhenAccessibilityDenied() {
        // Only runs in CI/test environment where accessibility is not granted.
        guard !tool.isAccessibilityEnabled() else {
            // Skip: accessibility is granted in this environment.
            return
        }

        XCTAssertThrowsError(try tool.queryFrontmostApp()) { error in
            guard let queryError = error as? UIElementQueryError else {
                XCTFail("Expected UIElementQueryError, got \(error)")
                return
            }
            if case .accessibilityPermissionDenied = queryError {
                // Expected
            } else {
                XCTFail("Expected .accessibilityPermissionDenied, got \(queryError)")
            }
        }
    }

    func testQueryApplicationThrowsWhenAccessibilityDenied() {
        guard !tool.isAccessibilityEnabled() else { return }

        XCTAssertThrowsError(try tool.queryApplication(bundleID: "com.apple.finder")) { error in
            guard let queryError = error as? UIElementQueryError else {
                XCTFail("Expected UIElementQueryError")
                return
            }
            if case .accessibilityPermissionDenied = queryError { /* Expected */ }
        }
    }
}
