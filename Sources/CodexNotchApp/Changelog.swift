import Foundation

struct ChangelogRelease: Decodable, Equatable {
    let version: String
    let date: String
    let title: String
    let changes: [String]
}

private struct ChangelogDocument: Decodable {
    let releases: [ChangelogRelease]
}

enum ChangelogCatalog {
    static let releases: [ChangelogRelease] = {
        guard let url = Bundle.module.url(forResource: "Changelog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let releases = try? decode(data)
        else { return [] }
        return releases
    }()

    static func decode(_ data: Data) throws -> [ChangelogRelease] {
        try JSONDecoder().decode(ChangelogDocument.self, from: data).releases
    }
}
