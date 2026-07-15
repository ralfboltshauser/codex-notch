import AppKit
import XCTest
@testable import CodexNotchApp

final class UninstallTests: CodexNotchTestCase {
    func testLocalUninstallerIncludesCurrentAndLegacyArtifacts() {
        let bundle = URL(fileURLWithPath: "/tmp/Codex Notch.app")
        let paths = Set(LocalApplicationUninstaller.cleanupArtifacts(bundleURL: bundle).map(\.path))
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].path

        XCTAssertTrue(paths.contains("\(library)/Application Support/Codex Notch"))
        XCTAssertTrue(paths.contains("\(library)/Caches/com.ralfbuilds.CodexNotch"))
        XCTAssertTrue(paths.contains("\(library)/Preferences/com.ralfbuilds.CodexNotch.plist"))
        XCTAssertTrue(paths.contains("\(library)/Application Support/Ntfy Codex Overlay"))
        XCTAssertTrue(paths.contains("\(library)/LaunchAgents/com.ralfbuilds.ntfy-codex-overlay.plist"))
    }
}
