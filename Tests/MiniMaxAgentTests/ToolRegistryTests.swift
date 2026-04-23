import XCTest
@testable import MiniMaxAgent

final class ToolRegistryTests: XCTestCase {

    // MARK: - Mock Tool

    private struct MockTool: OrderedToolRegistry.Tool, Equatable {
        let identifier: String
        let name: String
        let category: String

        var toolIdentifier: String { identifier }
        var toolName: String { name }
        var toolCategory: String { category }

        static func == (lhs: MockTool, rhs: MockTool) -> Bool {
            lhs.identifier == rhs.identifier
        }
    }

    // MARK: - Tests

    func testRegisterSingleTool() async throws {
        let registry = OrderedToolRegistry()
        let tool = MockTool(identifier: "tool-1", name: "First Tool", category: "test")

        try await registry.register(tool)

        let state = await registry.state()
        XCTAssertEqual(state.toolCount, 1)
        XCTAssertEqual(state.categoryCount, 1)
    }

    func testRegisterMultipleToolsPreservesOrder() async throws {
        let registry = OrderedToolRegistry()

        let tool1 = MockTool(identifier: "tool-1", name: "Alpha", category: "test")
        let tool2 = MockTool(identifier: "tool-2", name: "Beta", category: "test")
        let tool3 = MockTool(identifier: "tool-3", name: "Gamma", category: "test")

        try await registry.register(tool1)
        try await registry.register(tool2)
        try await registry.register(tool3)

        let tools = await registry.allTools()
        XCTAssertEqual(tools.map(\.name), ["Alpha", "Beta", "Gamma"])
    }

    func testDuplicateRegistrationThrows() async throws {
        let registry = OrderedToolRegistry()
        let tool = MockTool(identifier: "dup", name: "Duplicate", category: "test")

        try await registry.register(tool)

        do {
            try await registry.register(tool)
            XCTFail("Expected error for duplicate registration")
        } catch is OrderedToolRegistry.RegistryError {
            // Expected
        }
    }

    func testLookupById() async throws {
        let registry = OrderedToolRegistry()
        let tool = MockTool(identifier: "lookup-id", name: "Lookup Test", category: "test")

        try await registry.register(tool)

        let found = await registry.tool(id: "lookup-id")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Lookup Test")
    }

    func testLookupByName() async throws {
        let registry = OrderedToolRegistry()
        let tool = MockTool(identifier: "name-id", name: "Unique Name", category: "test")

        try await registry.register(tool)

        let found = await registry.tool(named: "Unique Name")
        XCTAssertNotNil(found)
    }

    func testToolsInCategoryPreservesOrder() async throws {
        let registry = OrderedToolRegistry()

        let toolA = MockTool(identifier: "cat-a", name: "Tool A", category: "order")
        let toolB = MockTool(identifier: "cat-b", name: "Tool B", category: "order")
        let toolC = MockTool(identifier: "cat-c", name: "Tool C", category: "other")

        try await registry.register(toolA)
        try await registry.register(toolC)
        try await registry.register(toolB)

        let orderTools = try await registry.tools(inCategory: "order")
        XCTAssertEqual(orderTools.map(\.name), ["Tool A", "Tool B"])
    }

    func testCategoriesInInsertionOrder() async throws {
        let registry = OrderedToolRegistry()

        let tool1 = MockTool(identifier: "t1", name: "First", category: "alpha")
        let tool2 = MockTool(identifier: "t2", name: "Second", category: "beta")
        let tool3 = MockTool(identifier: "t3", name: "Third", category: "gamma")

        try await registry.register(tool1)
        try await registry.register(tool2)
        try await registry.register(tool3)

        let categories = await registry.allCategories()
        XCTAssertEqual(categories, ["alpha", "beta", "gamma"])
    }

    func testUnregisterById() async throws {
        let registry = OrderedToolRegistry()
        let tool = MockTool(identifier: "remove-me", name: "To Remove", category: "test")

        try await registry.register(tool)
        try await registry.unregister(id: "remove-me")

        let state = await registry.state()
        XCTAssertEqual(state.toolCount, 0)
    }

    func testUnregisterByName() async throws {
        let registry = OrderedToolRegistry()
        let tool = MockTool(identifier: "by-name-id", name: "Remove By Name", category: "test")

        try await registry.register(tool)
        try await registry.unregister(name: "Remove By Name")

        let state = await registry.state()
        XCTAssertEqual(state.toolCount, 0)
    }

    func testRemoveAll() async throws {
        let registry = OrderedToolRegistry()

        try await registry.register(MockTool(identifier: "a", name: "A", category: "cat"))
        try await registry.register(MockTool(identifier: "b", name: "B", category: "cat"))
        try await registry.register(MockTool(identifier: "c", name: "C", category: "cat"))

        await registry.removeAll()

        let state = await registry.state()
        XCTAssertEqual(state.toolCount, 0)
        XCTAssertEqual(state.categoryCount, 0)
    }

    func testRegisterAll() async throws {
        let registry = OrderedToolRegistry()

        let tools = [
            MockTool(identifier: "all-1", name: "All 1", category: "batch"),
            MockTool(identifier: "all-2", name: "All 2", category: "batch"),
            MockTool(identifier: "all-3", name: "All 3", category: "batch"),
        ]

        try await registry.registerAll(tools)

        let state = await registry.state()
        XCTAssertEqual(state.toolCount, 3)
    }

    func testToolWrapperExposesMetadata() async throws {
        let registry = OrderedToolRegistry()
        let tool = MockTool(identifier: "wrap-1", name: "Wrapper Test", category: "meta")

        try await registry.register(tool)

        let wrapper = await registry.tool(id: "wrap-1")
        XCTAssertEqual(wrapper?.identifier, "wrap-1")
        XCTAssertEqual(wrapper?.name, "Wrapper Test")
        XCTAssertEqual(wrapper?.category, "meta")
    }
}
