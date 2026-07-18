import CodexNotchCore
import Foundation

enum AppServerThreadProjection {
    private struct ThreadNode {
        let id: String
        let title: String
        let parentID: String?
        let projectLabel: String?
        let branch: String?
        let agentNickname: String?
        let agentRole: String?
        let state: ActiveTaskState?
        let updatedAt: Date
    }

    static func activeEvents(
        from rows: [[String: Any]],
        observedAt: Date = Date()
    ) -> [ActiveTaskEvent] {
        let nodes = Dictionary(
            rows.compactMap { node(from: $0, observedAt: observedAt) }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return rows.compactMap { row -> ActiveTaskEvent? in
            guard let rawID = row["id"] as? String,
                  let id = canonicalThreadID(rawID),
                  let node = nodes[id],
                  let state = node.state else { return nil }
            let rootID = rootThreadID(for: node, in: nodes)
            let rootTitle = rootID == node.id ? nil : nodes[rootID]?.title
            return ActiveTaskEvent(
                threadID: node.id,
                title: node.title,
                state: state,
                updatedAt: node.updatedAt,
                parentThreadID: node.parentID,
                rootThreadID: rootID,
                rootTitle: rootTitle,
                projectLabel: node.projectLabel,
                branch: node.branch,
                agentNickname: node.agentNickname,
                agentRole: node.agentRole
            )
        }
    }

    /// Retains only the App Server fields needed to reconcile active tasks.
    /// In particular, thread previews, turns, rollout paths, and git remotes
    /// never survive beyond the response handler.
    static func reconciliationRow(from row: [String: Any]) -> [String: Any]? {
        guard let rawID = row["id"] as? String,
              let id = canonicalThreadID(rawID),
              let rawStatus = row["status"] as? [String: Any],
              let statusType = rawStatus["type"] as? String else { return nil }
        var result: [String: Any] = ["id": id]

        if let name = row["name"] as? String { result["name"] = name }
        if let rawParent = row["parentThreadId"], !(rawParent is NSNull) {
            guard let rawParentID = rawParent as? String,
                  let parentID = canonicalThreadID(rawParentID) else { return nil }
            result["parentThreadId"] = parentID
        }
        if let updatedAt = row["updatedAt"] as? NSNumber {
            result["updatedAt"] = updatedAt
        }
        if let label = projectLabel(from: row["cwd"] as? String) {
            result["projectLabel"] = label
        }
        if let gitInfo = row["gitInfo"] as? [String: Any],
           let branch = gitInfo["branch"] as? String {
            result["gitInfo"] = ["branch": branch]
        }
        if let nickname = row["agentNickname"] as? String {
            result["agentNickname"] = nickname
        }
        if let role = row["agentRole"] as? String {
            result["agentRole"] = role
        }
        var status: [String: Any] = ["type": statusType]
        if let rawFlags = rawStatus["activeFlags"], !(rawFlags is NSNull) {
            guard let flags = rawFlags as? [String] else { return nil }
            status["activeFlags"] = flags
        }
        result["status"] = status
        return result
    }

    private static func node(
        from row: [String: Any],
        observedAt: Date
    ) -> ThreadNode? {
        guard let rawID = row["id"] as? String,
              let id = canonicalThreadID(rawID) else { return nil }
        let status = row["status"] as? [String: Any]
        let state: ActiveTaskState?
        if status?["type"] as? String == "active" {
            let flags = status?["activeFlags"] as? [String] ?? []
            state = flags.contains("waitingOnApproval")
                ? .waitingForApproval
                : (flags.contains("waitingOnUserInput") ? .waitingForInput : .running)
        } else {
            state = nil
        }
        let seconds = (row["updatedAt"] as? NSNumber)?.doubleValue
        let gitInfo = row["gitInfo"] as? [String: Any]
        return ThreadNode(
            id: id,
            title: CompletionEvent.cleanTitle(row["name"] as? String ?? "Codex task running"),
            parentID: (row["parentThreadId"] as? String).flatMap(canonicalThreadID),
            projectLabel: cleanOptional(
                row["projectLabel"] as? String,
                maximum: ActiveTaskEvent.maximumProjectLabelLength
            ) ?? projectLabel(from: row["cwd"] as? String),
            branch: cleanOptional(
                gitInfo?["branch"] as? String,
                maximum: ActiveTaskEvent.maximumBranchLength
            ),
            agentNickname: cleanOptional(
                row["agentNickname"] as? String,
                maximum: ActiveTaskEvent.maximumAgentLabelLength
            ),
            agentRole: cleanOptional(
                row["agentRole"] as? String,
                maximum: ActiveTaskEvent.maximumAgentLabelLength
            ),
            state: state,
            updatedAt: seconds.map { Date(timeIntervalSince1970: $0) } ?? observedAt
        )
    }

    private static func rootThreadID(
        for node: ThreadNode,
        in nodes: [String: ThreadNode]
    ) -> String {
        var currentID = node.id
        var seen: Set<String> = [currentID]
        while let parentID = nodes[currentID]?.parentID {
            guard seen.insert(parentID).inserted else { return node.id }
            currentID = parentID
            if nodes[currentID] == nil { return currentID }
        }
        return currentID
    }

    private static func canonicalThreadID(_ value: String) -> String? {
        UUID(uuidString: value)?.uuidString.lowercased()
    }

    private static func projectLabel(from cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let label = URL(fileURLWithPath: cwd).standardizedFileURL.lastPathComponent
        return cleanOptional(label, maximum: ActiveTaskEvent.maximumProjectLabelLength)
    }

    private static func cleanOptional(_ value: String?, maximum: Int) -> String? {
        let cleaned = (value ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(maximum))
    }
}
