import Foundation

public enum CompletionOutcomeFormatter {
    public static let maximumLength = 200

    public static func format(_ value: String?) -> String? {
        guard let value else { return nil }

        var isInsideCodeFence = false
        var paragraph: [String] = []
        var headingFallback: String?

        for rawLine in value.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if isCodeFence(line) {
                isInsideCodeFence.toggle()
                if !paragraph.isEmpty { break }
                continue
            }
            if isInsideCodeFence { continue }
            if line.isEmpty {
                if !paragraph.isEmpty { break }
                continue
            }
            if isHeading(line) {
                if headingFallback == nil {
                    headingFallback = cleanMarkdownLine(line.drop { $0 == "#" })
                }
                continue
            }
            if !paragraph.isEmpty && isListItem(line) { break }
            guard let cleaned = cleanMarkdownLine(line) else { continue }
            paragraph.append(cleaned)
        }

        let outcome = paragraph.isEmpty ? headingFallback : paragraph.joined(separator: " ")
        guard let outcome else { return nil }
        return bounded(outcome)
    }

    private static func isCodeFence(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix("~~~")
    }

    private static func isHeading(_ line: String) -> Bool {
        guard line.first == "#" else { return false }
        let markerCount = line.prefix { $0 == "#" }.count
        guard markerCount <= 6, line.count > markerCount else { return false }
        let next = line.index(line.startIndex, offsetBy: markerCount)
        return line[next].isWhitespace
    }

    private static func isListItem(_ line: String) -> Bool {
        if ["- ", "* ", "+ "].contains(where: line.hasPrefix) { return true }
        guard let period = line.firstIndex(of: "."), period != line.startIndex else { return false }
        let prefix = line[..<period]
        let afterPeriod = line.index(after: period)
        return prefix.allSatisfy(\.isNumber)
            && afterPeriod < line.endIndex
            && line[afterPeriod].isWhitespace
    }

    private static func cleanMarkdownLine<S: StringProtocol>(_ source: S) -> String? {
        var line = String(source).trimmingCharacters(in: .whitespacesAndNewlines)
        while line.hasPrefix(">") {
            line.removeFirst()
            line = line.trimmingCharacters(in: .whitespaces)
        }
        if let marker = ["- ", "* ", "+ "].first(where: line.hasPrefix) {
            line.removeFirst(marker.count)
        } else if let period = line.firstIndex(of: "."), period != line.startIndex {
            let prefix = line[..<period]
            let afterPeriod = line.index(after: period)
            if prefix.allSatisfy(\.isNumber),
               afterPeriod < line.endIndex,
               line[afterPeriod].isWhitespace {
                line.removeSubrange(line.startIndex...afterPeriod)
            }
        }

        line = replacingMarkdownLinks(in: line)
        for marker in ["**", "__", "~~", "`"] {
            line = line.replacingOccurrences(of: marker, with: "")
        }
        let cleaned = line
            .components(separatedBy: .controlCharacters)
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func replacingMarkdownLinks(in value: String) -> String {
        let pattern = #"!?\[([^\]]+)\]\([^\)]+\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: "$1"
        )
    }

    private static func bounded(_ value: String) -> String {
        guard value.count > maximumLength else { return value }
        let prefix = String(value.prefix(maximumLength - 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "…"
    }
}
