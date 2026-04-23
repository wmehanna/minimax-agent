import Foundation
import Collections

// MARK: - Tool Protocol

/// Protocol for tools that can be registered with OrderedToolRegistry.
///
/// Types conforming to Tool are stored in OrderedToolRegistry using
/// swift-collections' OrderedDictionary and OrderedSet for deterministic
/// iteration order and O(1) lookup performance.
public protocol Tool: Sendable {
    var toolIdentifier: String { get }
    var toolName: String { get }
    var toolCategory: String { get }
}

// MARK: - Tool Wrapper

/// Wrapper that type-erases a tool, exposing only identifier metadata.
/// The actual tool instance is retained for future retrieval.
public final class ToolWrapper: @unchecked Sendable {
    private let _identifier: String
    private let _name: String
    private let _category: String

    public var identifier: String { _identifier }
    public var name: String { _name }
    public var category: String { _category }

    public init(_ tool: some Tool) {
        self._identifier = tool.toolIdentifier
        self._name = tool.toolName
        self._category = tool.toolCategory
    }
}

// MARK: - OrderedToolRegistry

/// A registry of tools with deterministic iteration order.
///
/// OrderedToolRegistry uses `OrderedSet` and `OrderedDictionary` from swift-collections
/// to maintain tools in insertion order while enabling O(1) lookup by name or ID.
///
/// ## Example
/// ```swift
/// let registry = OrderedToolRegistry()
/// try await registry.register(MyTool())
/// registry.allTools() // Returns tools in registration order
/// registry.tool(named: "my-tool") // O(1) lookup
/// ```
public actor OrderedToolRegistry {

    // MARK: - Tool Descriptor

    /// Metadata descriptor for a registered tool
    public struct ToolDescriptor: Identifiable, Sendable, Hashable {
        public let id: String
        public let name: String
        public let category: String
        public let registeredAt: Date

        public init(id: String, name: String, category: String, registeredAt: Date = Date()) {
            self.id = id
            self.name = name
            self.category = category
            self.registeredAt = registeredAt
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        public static func == (lhs: ToolDescriptor, rhs: ToolDescriptor) -> Bool {
            lhs.id == rhs.id
        }
    }

    // MARK: - Errors

    public enum RegistryError: Error, LocalizedError, Sendable {
        case toolAlreadyRegistered(id: String)
        case toolNotFound(id: String)
        case toolNotFoundByName(name: String)
        case categoryNotFound(category: String)

        public var errorDescription: String? {
            switch self {
            case .toolAlreadyRegistered(let id):
                return "Tool with ID '\(id)' is already registered"
            case .toolNotFound(let id):
                return "Tool with ID '\(id)' not found in registry"
            case .toolNotFoundByName(let name):
                return "Tool with name '\(name)' not found"
            case .categoryNotFound(let category):
                return "No tools found in category '\(category)'"
            }
        }
    }

    // MARK: - State

    /// Snapshot of the registry state
    public struct State: Sendable {
        public let toolCount: Int
        public let categoryCount: Int
        public let categories: [String]
        public let toolsByCategory: [String: [String]]
    }

    // MARK: - Properties

    /// All registered tool descriptors in insertion order — uses OrderedSet
    private var toolDescriptors: OrderedSet<ToolDescriptor> = []

    /// Tool lookup by identifier — uses OrderedDictionary for consistent iteration order
    private var toolsById: OrderedDictionary<String, ToolWrapper> = [:]

    /// Tool lookup by name (unique per tool)
    private var toolIdsByName: [String: String] = [:]

    /// Tool IDs grouped by category — uses OrderedDictionary for deterministic category iteration
    private var toolIdsByCategory: OrderedDictionary<String, OrderedSet<String>> = [:]

    // MARK: - Initialization

    public init() {}

    // MARK: - Registration

    /// Register a tool
    /// - Parameter tool: The tool to register
    /// - Throws: RegistryError.toolAlreadyRegistered if the tool ID is already registered
    public func register(_ tool: some Tool) throws {
        let id = tool.toolIdentifier
        let name = tool.toolName
        let category = tool.toolCategory

        // Check for duplicate ID
        if toolsById[id] != nil {
            throw RegistryError.toolAlreadyRegistered(id: id)
        }

        let descriptor = ToolDescriptor(id: id, name: name, category: category)

        // Add to descriptors (OrderedSet maintains insertion order)
        toolDescriptors.append(descriptor)

        // Add to ID lookup (OrderedDictionary)
        toolsById[id] = ToolWrapper(tool)

        // Add name lookup
        toolIdsByName[name] = id

        // Add to category grouping
        if toolIdsByCategory[category] == nil {
            toolIdsByCategory[category] = OrderedSet<String>()
        }
        toolIdsByCategory[category]?.append(id)
    }

    // MARK: - Lookup

    /// Get a tool by its identifier
    /// - Parameter id: The tool identifier
    /// - Returns: The tool wrapper if found
    public func tool(id: String) -> ToolWrapper? {
        toolsById[id]
    }

    /// Get a tool by its name
    /// - Parameter name: The tool name
    /// - Returns: The tool wrapper if found
    public func tool(named name: String) -> ToolWrapper? {
        guard let id = toolIdsByName[name] else { return nil }
        return toolsById[id]
    }

    /// Get all registered tools in insertion order
    /// - Returns: Array of tool descriptors in registration order
    public func allTools() -> [ToolDescriptor] {
        Array(toolDescriptors)
    }

    /// Get tools in a specific category, in insertion order
    /// - Parameter category: The category name
    /// - Returns: Array of tool descriptors in that category
    /// - Throws: RegistryError.categoryNotFound if no tools exist in the category
    public func tools(inCategory category: String) throws -> [ToolDescriptor] {
        guard let orderedIds = toolIdsByCategory[category] else {
            throw RegistryError.categoryNotFound(category: category)
        }
        return orderedIds.compactMap { id in
            toolDescriptors.first { $0.id == id }
        }
    }

    /// Get all categories in insertion order (order of first tool registration)
    /// - Returns: Array of category names
    public func allCategories() -> [String] {
        Array(toolIdsByCategory.keys)
    }

    // MARK: - Unregistration

    /// Unregister a tool by ID
    /// - Parameter id: The tool identifier
    /// - Throws: RegistryError.toolNotFound if the tool is not registered
    public func unregister(id: String) throws {
        guard let descriptor = toolDescriptors.first(where: { $0.id == id }) else {
            throw RegistryError.toolNotFound(id: id)
        }

        // Remove from descriptors
        toolDescriptors.remove(descriptor)

        // Remove from ID lookup
        toolsById.removeValue(forKey: id)

        // Remove from name lookup
        toolIdsByName.removeValue(forKey: descriptor.name)

        // Remove from category grouping
        toolIdsByCategory[descriptor.category]?.remove(id)
        if toolIdsByCategory[descriptor.category]?.isEmpty == true {
            toolIdsByCategory.removeValue(forKey: descriptor.category)
        }
    }

    /// Unregister a tool by name
    /// - Parameter name: The tool name
    /// - Throws: RegistryError.toolNotFoundByName if no tool with that name exists
    public func unregister(name: String) throws {
        guard let id = toolIdsByName[name] else {
            throw RegistryError.toolNotFoundByName(name: name)
        }
        try unregister(id: id)
    }

    // MARK: - State

    /// Get a snapshot of the current registry state
    public func state() -> State {
        let categories = Array(toolIdsByCategory.keys)
        let toolsByCategory = categories.reduce(into: [String: [String]]()) { result, category in
            result[category] = Array(toolIdsByCategory[category] ?? [])
        }
        return State(
            toolCount: toolsById.count,
            categoryCount: toolIdsByCategory.count,
            categories: categories,
            toolsByCategory: toolsByCategory
        )
    }

    // MARK: - Batch Operations

    /// Register multiple tools at once
    /// - Parameter tools: The tools to register
    /// - Throws: First error encountered during registration
    public func registerAll(_ tools: some Sequence<some Tool>) throws {
        for tool in tools {
            try register(tool)
        }
    }

    /// Remove all registered tools
    public func removeAll() {
        toolDescriptors.removeAll()
        toolsById.removeAll()
        toolIdsByName.removeAll()
        toolIdsByCategory.removeAll()
    }
}

// MARK: - Tool Extensions for Built-in Tools

extension OrderedToolRegistry {
    /// Create a registry pre-populated with built-in tools
    public static func createBuiltIn() -> OrderedToolRegistry {
        let registry = OrderedToolRegistry()
        return registry
    }
}
