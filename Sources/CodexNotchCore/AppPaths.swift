import Foundation

public enum AppPaths {
    public static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Codex Notch", isDirectory: true)
    }

    public static var inbox: URL {
        applicationSupport.appendingPathComponent("inbox", isDirectory: true)
    }

    public static var tasksFile: URL {
        applicationSupport.appendingPathComponent("tasks.json")
    }

    public static var pairingsFile: URL {
        applicationSupport.appendingPathComponent("remote-hosts.json")
    }

    public static var codexHome: URL {
        ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    public static var hooksFile: URL {
        codexHome.appendingPathComponent("hooks.json")
    }

    public static func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }
}
