import CodexNotchCore
import Foundation

enum CompletionAcceptance {
    case accepted
    case duplicate
    case rejected
}

struct RemoteEnvelope: Decodable {
    let protocolVersion: Int
    let kind: String
    let token: String
    let event: CompletionEvent?
    let snapshot: ActiveTaskSnapshot?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case kind
        case token
        case event
        case snapshot
    }
}

struct RemoteAcknowledgement: Codable {
    let protocolVersion: Int
    let status: String
    let eventID: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case status
        case eventID = "event_id"
        case error
    }

    static func accepted(eventID: String, duplicate: Bool) -> Self {
        Self(
            protocolVersion: 1,
            status: duplicate ? "duplicate" : "accepted",
            eventID: eventID,
            error: nil
        )
    }

    static var pong: Self {
        Self(protocolVersion: 1, status: "pong", eventID: nil, error: nil)
    }

    static var snapshotAccepted: Self {
        Self(protocolVersion: 1, status: "accepted", eventID: nil, error: nil)
    }

    static func rejected(_ error: String, eventID: String? = nil) -> Self {
        Self(protocolVersion: 1, status: "rejected", eventID: eventID, error: error)
    }
}
