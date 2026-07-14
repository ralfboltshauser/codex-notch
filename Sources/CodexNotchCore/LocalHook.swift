import Foundation

public struct CodexStopHookInput: Decodable {
    public let sessionID: String
    public let turnID: String?
    public let hookEventName: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case turnID = "turn_id"
        case hookEventName = "hook_event_name"
    }
}

public enum LocalHookRunner {
    public static func run(input: FileHandle = .standardInput) -> Int32 {
        do {
            let payload = input.readDataToEndOfFile()
            let hook = try JSONDecoder().decode(CodexStopHookInput.self, from: payload)
            guard hook.hookEventName == nil || hook.hookEventName == "Stop",
                  let turnID = hook.turnID, !turnID.isEmpty,
                  let canonicalThreadID = UUID(uuidString: hook.sessionID)?.uuidString.lowercased()
            else { return 0 }

            let event = CompletionEvent(
                eventID: CompletionEvent.eventID(threadID: canonicalThreadID, turnID: turnID),
                threadID: canonicalThreadID,
                turnID: turnID,
                title: CompletionEvent.cleanTitle(lookupTitle(sessionID: canonicalThreadID)),
                sourceID: "local",
                sourceLabel: "This Mac",
                completedAt: Date()
            )
            guard event.isValid else { return 0 }
            try write(event)
        } catch {
            // Completion delivery must never fail the Codex turn.
        }
        return 0
    }

    public static func write(_ event: CompletionEvent, inbox: URL = AppPaths.inbox) throws {
        guard event.isValid else {
            throw NSError(
                domain: "CodexNotchCore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid completion event"]
            )
        }
        try AppPaths.prepareDirectory(inbox)
        let destination = inbox.appendingPathComponent(event.eventID).appendingPathExtension("json")
        let data = try JSONEncoder.codexNotch.encode(event)
        try data.write(to: destination, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
    }

    private static func lookupTitle(sessionID: String) -> String? {
        let index = AppPaths.codexHome.appendingPathComponent("session_index.jsonl")
        guard let handle = try? FileHandle(forReadingFrom: index) else { return nil }
        defer { try? handle.close() }
        let maximumBytes: UInt64 = 4 * 1024 * 1024
        let length = handle.seekToEndOfFile()
        handle.seek(toFileOffset: length > maximumBytes ? length - maximumBytes : 0)
        let data = handle.readDataToEndOfFile()
        for line in data.split(separator: 0x0A).reversed() {
            guard let value = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  (value["id"] as? String)?.lowercased() == sessionID else { continue }
            return value["thread_name"] as? String
        }
        return nil
    }
}

public extension JSONEncoder {
    static var codexNotch: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var codexNotch: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
