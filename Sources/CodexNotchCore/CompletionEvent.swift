import CryptoKit
import Foundation

public struct CompletionEvent: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumTitleLength = 180

    public let schemaVersion: Int
    public let eventID: String
    public let threadID: String
    public let turnID: String
    public let title: String
    public let sourceID: String
    public let sourceLabel: String
    public let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventID = "event_id"
        case threadID = "thread_id"
        case turnID = "turn_id"
        case title
        case sourceID = "source_id"
        case sourceLabel = "source_label"
        case completedAt = "completed_at"
    }

    public init(
        schemaVersion: Int = currentSchemaVersion,
        eventID: String,
        threadID: String,
        turnID: String,
        title: String,
        sourceID: String,
        sourceLabel: String,
        completedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.threadID = threadID
        self.turnID = turnID
        self.title = title
        self.sourceID = sourceID
        self.sourceLabel = sourceLabel
        self.completedAt = completedAt
    }

    public var isValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && eventID.count == 64
            && eventID.allSatisfy { $0.isHexDigit && !$0.isUppercase }
            && UUID(uuidString: threadID) != nil
            && !turnID.isEmpty
            && turnID.utf8.count <= 256
            && eventID == Self.eventID(threadID: threadID, turnID: turnID)
            && !title.isEmpty
            && title.count <= Self.maximumTitleLength
            && !sourceID.isEmpty
            && sourceID.utf8.count <= 128
            && !sourceLabel.isEmpty
            && sourceLabel.count <= 80
    }

    public static func eventID(threadID: String, turnID: String) -> String {
        let input = Data("v1\0\(threadID.lowercased())\0\(turnID)".utf8)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    public static func cleanTitle(_ value: String?) -> String {
        let cleaned = (value ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String((cleaned.isEmpty ? "Codex task finished" : cleaned).prefix(maximumTitleLength))
    }
}
