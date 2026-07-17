import Foundation

public enum ActiveTaskState: String, Codable, CaseIterable, Sendable {
    case running
    case waitingForApproval = "waiting_for_approval"
    case waitingForInput = "waiting_for_input"
    case unavailable
}

public struct ActiveTaskEvent: Codable, Equatable, Sendable {
    public static let maximumProjectLabelLength = 80
    public static let maximumBranchLength = 160
    public static let maximumAgentLabelLength = 80

    public let threadID: String
    public let title: String
    public let state: ActiveTaskState
    public let updatedAt: Date
    public let parentThreadID: String?
    public let rootThreadID: String?
    public let rootTitle: String?
    public let projectLabel: String?
    public let branch: String?
    public let agentNickname: String?
    public let agentRole: String?

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case title, state
        case updatedAt = "updated_at"
        case parentThreadID = "parent_thread_id"
        case rootThreadID = "root_thread_id"
        case rootTitle = "root_title"
        case projectLabel = "project_label"
        case branch
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
    }

    public init(
        threadID: String,
        title: String,
        state: ActiveTaskState,
        updatedAt: Date,
        parentThreadID: String? = nil,
        rootThreadID: String? = nil,
        rootTitle: String? = nil,
        projectLabel: String? = nil,
        branch: String? = nil,
        agentNickname: String? = nil,
        agentRole: String? = nil
    ) {
        self.threadID = threadID
        self.title = title
        self.state = state
        self.updatedAt = updatedAt
        self.parentThreadID = parentThreadID
        self.rootThreadID = rootThreadID
        self.rootTitle = rootTitle
        self.projectLabel = projectLabel
        self.branch = branch
        self.agentNickname = agentNickname
        self.agentRole = agentRole
    }

    public var isValid: Bool {
        UUID(uuidString: threadID) != nil
            && !title.isEmpty
            && title.count <= CompletionEvent.maximumTitleLength
            && updatedAt.timeIntervalSince1970.isFinite
            && validOptionalThreadID(parentThreadID)
            && validOptionalThreadID(rootThreadID)
            && validOptionalText(rootTitle, maximum: CompletionEvent.maximumTitleLength)
            && validOptionalText(projectLabel, maximum: Self.maximumProjectLabelLength)
            && (projectLabel.map { !$0.contains("/") && !$0.contains("\\") } ?? true)
            && validOptionalText(branch, maximum: Self.maximumBranchLength)
            && validOptionalText(agentNickname, maximum: Self.maximumAgentLabelLength)
            && validOptionalText(agentRole, maximum: Self.maximumAgentLabelLength)
    }

    private func validOptionalThreadID(_ value: String?) -> Bool {
        value.map { UUID(uuidString: $0) != nil } ?? true
    }

    private func validOptionalText(_ value: String?, maximum: Int) -> Bool {
        value.map {
            !$0.isEmpty
                && $0.count <= maximum
                && $0.unicodeScalars.allSatisfy {
                    !CharacterSet.controlCharacters.contains($0)
                }
        } ?? true
    }
}

public struct ActiveTaskSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumTaskCount = 50

    public let schemaVersion: Int
    public let generation: String
    public let sequence: UInt64
    public let generatedAt: Date
    public let tasks: [ActiveTaskEvent]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generation, sequence
        case generatedAt = "generated_at"
        case tasks
    }

    public init(
        schemaVersion: Int = currentSchemaVersion,
        generation: String,
        sequence: UInt64,
        generatedAt: Date,
        tasks: [ActiveTaskEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.generation = generation
        self.sequence = sequence
        self.generatedAt = generatedAt
        self.tasks = tasks
    }

    public var isValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && UUID(uuidString: generation) != nil
            && tasks.count <= Self.maximumTaskCount
            && Set(tasks.map { $0.threadID.lowercased() }).count == tasks.count
            && tasks.allSatisfy(\.isValid)
    }
}
