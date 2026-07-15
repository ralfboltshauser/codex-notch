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
    static let resourceBundleName = "CodexNotch_CodexNotchApp.bundle"

    static let releases: [ChangelogRelease] = {
        load(
            applicationResourcesURL: Bundle.main.resourceURL,
            fallbackBundle: {
                guard Bundle.main.bundleURL.pathExtension.lowercased() != "app" else {
                    return nil
                }
                return Bundle.module
            }
        )
    }()

    static func load(
        applicationResourcesURL: URL?,
        fallbackBundle: () -> Bundle?
    ) -> [ChangelogRelease] {
        let packagedURL = applicationResourcesURL?
            .appendingPathComponent(resourceBundleName, isDirectory: true)
            .appendingPathComponent("Changelog")
            .appendingPathExtension("json")
        let url: URL?
        if let packagedURL, FileManager.default.fileExists(atPath: packagedURL.path) {
            url = packagedURL
        } else {
            url = fallbackBundle()?.url(forResource: "Changelog", withExtension: "json")
        }
        guard let url,
              let data = try? Data(contentsOf: url),
              let releases = try? decode(data)
        else { return [] }
        return releases
    }

    static func decode(_ data: Data) throws -> [ChangelogRelease] {
        try JSONDecoder().decode(ChangelogDocument.self, from: data).releases
    }
}
