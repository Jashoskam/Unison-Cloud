import Foundation

/// Record of a single Gemini function call tool execution (read_file, run_command, etc.)
public struct ToolExecution: Codable, Hashable, Identifiable {
    public var id: String
    public var toolName: String      // "read_file", "list_directory", "write_file", "run_command", "search_files"
    public var arguments: String     // JSON string of arguments passed to the tool
    public var resultSummary: String // Human-readable summary: "28 lines read", "12 items listed", etc.
    public var durationMs: Int       // Execution time in milliseconds
    
    public init(id: String = UUID().uuidString, toolName: String, arguments: String, resultSummary: String, durationMs: Int) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.resultSummary = resultSummary
        self.durationMs = durationMs
    }
}

/// Singular chat message inside the Unison Neural OS stream
public struct ChatMessage: Identifiable, Codable, Hashable {
    public var id: String
    public var role: String // user, model, system
    public var content: String
    public var thoughts: String?
    public var createdAt: Date
    public var executionTimeSeconds: Int?
    public var commandExecuted: String?
    public var commandOutput: String?
    public var exploredTaskCount: Int?
    public var checkedTaskTitle: String?
    public var pendingApprovalCommand: String?
    public var isRelaySignal: Bool
    public var isApproved: Bool?
    public var toolExecutions: [ToolExecution]?
    
    public init(
        id: String = UUID().uuidString,
        role: String,
        content: String,
        thoughts: String? = nil,
        createdAt: Date = Date(),
        isRelaySignal: Bool = false,
        executionTimeSeconds: Int? = nil,
        commandExecuted: String? = nil,
        commandOutput: String? = nil,
        exploredTaskCount: Int? = nil,
        checkedTaskTitle: String? = nil,
        pendingApprovalCommand: String? = nil,
        isApproved: Bool? = nil,
        toolExecutions: [ToolExecution]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thoughts = thoughts
        self.createdAt = createdAt
        self.isRelaySignal = isRelaySignal
        self.executionTimeSeconds = executionTimeSeconds
        self.commandExecuted = commandExecuted
        self.commandOutput = commandOutput
        self.exploredTaskCount = exploredTaskCount
        self.checkedTaskTitle = checkedTaskTitle
        self.pendingApprovalCommand = pendingApprovalCommand
        self.isApproved = isApproved
        self.toolExecutions = toolExecutions
    }
}

/// Unified Conversation node grouping workspace files or chat threads
public struct Conversation: Identifiable, Codable, Hashable {
    public var id: String
    public var title: String
    public var type: String // main_convo, chat, project
    public var parentId: String?
    public var searchText: String?
    public var createdAt: Date
    public var childTabs: [String]?
    
    public init(id: String, title: String, type: String, parentId: String? = nil, searchText: String? = nil, createdAt: Date = Date(), childTabs: [String]? = nil) {
        self.id = id
        self.title = title
        self.type = type
        self.parentId = parentId
        self.searchText = searchText
        self.createdAt = createdAt
        self.childTabs = childTabs
    }
}

/// Dynamic file associated with a Unison Swarm project
public struct UnisonFile: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var category: String
    public var language: String
    public var size: String
    public var content: String
    
    public init(id: String, name: String, category: String, language: String, size: String, content: String) {
        self.id = id
        self.name = name
        self.category = category
        self.language = language
        self.size = size
        self.content = content
    }
}

/// Persistent Workspace Project directory representation
public struct WorkspaceProject: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var directoryPath: String
    public var createdAt: Date
    
    public init(id: String = UUID().uuidString, name: String, directoryPath: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.directoryPath = directoryPath
        self.createdAt = createdAt
    }
}
