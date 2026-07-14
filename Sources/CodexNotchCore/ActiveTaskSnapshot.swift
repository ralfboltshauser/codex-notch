import Foundation

public enum ActiveTaskState: String, Codable, CaseIterable, Sendable {
    case running
    case waitingForApproval = "waiting_for_approval"
    case waitingForInput = "waiting_for_input"
    case unavailable
}

public struct ActiveTaskEvent: Codable, Equatable, Sendable {
    public let threadID: String
    public let title: String
    public let state: ActiveTaskState
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case title, state
        case updatedAt = "updated_at"
    }

    public init(threadID: String, title: String, state: ActiveTaskState, updatedAt: Date) {
        self.threadID = threadID
        self.title = title
        self.state = state
        self.updatedAt = updatedAt
    }

    public var isValid: Bool {
        UUID(uuidString: threadID) != nil
            && !title.isEmpty
            && title.count <= CompletionEvent.maximumTitleLength
            && updatedAt.timeIntervalSince1970.isFinite
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
