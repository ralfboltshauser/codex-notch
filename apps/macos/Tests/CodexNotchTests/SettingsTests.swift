import AppKit
import CodexNotchCore
import XCTest
@testable import CodexNotchApp

final class SettingsTests: CodexNotchTestCase {
    func testSettingsWindowIsKeyCapableAndClosesWithCommandW() throws {
        _ = NSApplication.shared
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.isVisible)

        let commandW = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))
        XCTAssertTrue(window.performKeyEquivalent(with: commandW))
        XCTAssertFalse(window.isVisible)
    }

    func testSettingsUsesRegularActivationOnlyWhileVisible() {
        _ = NSApplication.shared
        let previousMainMenu = NSApp.mainMenu
        let previousWindowsMenu = NSApp.windowsMenu
        NSApp.setActivationPolicy(.accessory)
        let directory = temporaryDirectory()
        defer {
            NSApp.mainMenu = previousMainMenu
            NSApp.windowsMenu = previousWindowsMenu
            NSApp.setActivationPolicy(.accessory)
            try? FileManager.default.removeItem(at: directory)
        }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(pairings: pairings, pairer: pairer)

        controller.present()
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertTrue(controller.window?.canBecomeKey == true)
        XCTAssertEqual(NSApp.mainMenu?.items.first?.title, ApplicationMenu.applicationName)
        XCTAssertEqual(NSApp.mainMenu?.items.map(\.title), ["Codex Notch", "File", "Edit", "Window"])
        XCTAssertTrue(NSApp.windowsMenu === NSApp.mainMenu?.items.last?.submenu)

        controller.close()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        XCTAssertTrue(controller.window?.isVisible == false)
    }

    func testSettingsVersionDescriptionIncludesReleaseAndBuildNumbers() {
        XCTAssertEqual(
            OnboardingWindowController.versionDescription(info: [
                "CFBundleShortVersionString": "0.3.6",
                "CFBundleVersion": "9",
            ]),
            "Version 0.3.6 (9)"
        )
        XCTAssertEqual(
            OnboardingWindowController.versionDescription(info: [:]),
            "Version unavailable"
        )
    }

    func testSettingsCheckForUpdatesButtonInvokesHandler() throws {
        _ = NSApplication.shared
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            isHookInstalled: { true }
        )
        var checked = false
        controller.onCheckForUpdates = { checked = true }

        let button = try XCTUnwrap(controller.checkForUpdatesButtonForTesting)
        XCTAssertEqual(button.title, "Check for Updates")
        button.performClick(nil)

        XCTAssertTrue(checked)
    }

    func testSettingsRendersThemesSoundsAndPaddedNavigationTabs() throws {
        _ = NSApplication.shared
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            isHookInstalled: { true }
        )

        XCTAssertEqual(
            controller.settingsTabTitlesForTesting,
            ["Themes", "Tasks", "Sounds", "Connections", "Changelog"]
        )
        XCTAssertEqual(controller.selectedSettingsTabTitleForTesting, "Connections")
        XCTAssertFalse(controller.settingsTabsHaveAmbiguityForTesting)
        let tabFrames = controller.settingsTabFramesForTesting
        XCTAssertEqual(tabFrames.count, 5)
        XCTAssertTrue(tabFrames.allSatisfy {
            $0.width > 60 && controller.settingsBoundsForTesting.contains($0)
        })
        for index in tabFrames.indices.dropFirst() {
            XCTAssertFalse(tabFrames[index - 1].intersects(tabFrames[index]))
        }
        controller.showThemesForTesting()
        XCTAssertEqual(controller.renderedThemeChoiceCountForTesting, NotchTheme.all.count)
        XCTAssertGreaterThanOrEqual(SettingsNavigationButton.horizontalContentPadding, 12)

        controller.showSoundsForTesting()

        XCTAssertEqual(controller.renderedSoundChoiceCountForTesting, 7)
        XCTAssertEqual(NotificationSound.allCases.filter { $0 != .none }.count, 6)
        XCTAssertTrue(NotificationSound.allCases.filter { $0 != .none }.allSatisfy {
            $0.resourceURL != nil
        })
    }

    func testPresentConnectionsOverridesThePreviouslySelectedSettingsTab() {
        _ = NSApplication.shared
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            isHookInstalled: { true },
            shouldReduceMotion: { true }
        )

        controller.showThemesForTesting()
        XCTAssertEqual(controller.selectedSettingsTabTitleForTesting, "Themes")
        controller.presentConnections()

        XCTAssertEqual(controller.selectedSettingsTabTitleForTesting, "Connections")
        controller.close()
    }

    func testBundledChangelogMatchesReleaseAndRendersInSettings() throws {
        _ = NSApplication.shared
        XCTAssertEqual(ChangelogCatalog.releases.first?.version, "0.4.23")
        XCTAssertGreaterThanOrEqual(ChangelogCatalog.releases.count, 21)
        XCTAssertTrue(ChangelogCatalog.releases.allSatisfy {
            !$0.title.isEmpty && !$0.changes.isEmpty
        })

        let decoded = try ChangelogCatalog.decode(Data("""
        {"releases":[{"version":"1.2.3","date":"2026-07-15","title":"Clear notes","changes":["One useful change."]}]}
        """.utf8))
        XCTAssertEqual(decoded.first?.version, "1.2.3")

        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            isHookInstalled: { true }
        )

        controller.showChangelogForTesting()

        XCTAssertEqual(controller.selectedSettingsTabTitleForTesting, "Changelog")
        XCTAssertEqual(
            controller.renderedChangelogVersionsForTesting,
            ChangelogCatalog.releases.map(\.version)
        )
        XCTAssertTrue(controller.changelogUsesVerticalScrollingForTesting)
    }

    func testChangelogResolvesFromPackagedApplicationResourcesWithoutModuleFallback() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resources = directory.appendingPathComponent("Contents/Resources", isDirectory: true)
        let resourceBundle = resources.appendingPathComponent(
            ChangelogCatalog.resourceBundleName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: resourceBundle,
            withIntermediateDirectories: true
        )
        let expectedURL = resourceBundle.appendingPathComponent("Changelog.json")
        try Data("""
        {"releases":[{"version":"1.2.3","date":"2026-07-15","title":"Packaged notes","changes":["Loaded safely."]}]}
        """.utf8).write(to: expectedURL)
        var usedFallback = false

        let releases = ChangelogCatalog.load(
            applicationResourcesURL: resources,
            fallbackBundle: {
                usedFallback = true
                return nil
            }
        )

        XCTAssertEqual(releases.first?.version, "1.2.3")
        XCTAssertFalse(usedFallback, "Packaged changelog unexpectedly evaluated Bundle.module")
    }

    func testMissingPackagedChangelogFailsQuietlyWhenFallbackIsUnavailable() {
        let missingResources = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: missingResources) }
        var usedFallback = false

        let releases = ChangelogCatalog.load(
            applicationResourcesURL: missingResources,
            fallbackBundle: {
                usedFallback = true
                return nil
            }
        )

        XCTAssertTrue(releases.isEmpty)
        XCTAssertTrue(usedFallback)
    }

    func testSettingsThemeAndSoundChoicesReceiveVisibleFrames() throws {
        _ = NSApplication.shared
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            isHookInstalled: { true }
        )

        controller.showThemesForTesting()

        XCTAssertEqual(
            controller.renderedThemeChoiceFramesForTesting.count,
            NotchTheme.all.count
        )
        let themeFrames = controller.renderedThemeChoiceFramesForTesting
        for frame in themeFrames {
            XCTAssertGreaterThan(frame.width, 100)
            XCTAssertGreaterThan(frame.height, 60)
            XCTAssertTrue(controller.settingsBoundsForTesting.contains(frame))
        }
        XCTAssertEqual(Set(themeFrames.map { Int($0.midY.rounded()) }).count, 3)

        controller.showSoundsForTesting()

        XCTAssertEqual(controller.renderedSoundChoiceFramesForTesting.count, 7)
        for frame in controller.renderedSoundChoiceFramesForTesting {
            XCTAssertGreaterThan(frame.width, 100)
            XCTAssertGreaterThan(frame.height, 40)
            XCTAssertTrue(controller.settingsBoundsForTesting.intersects(frame))
        }
    }

    func testThemeTabKeepsRealNotchOpenAndReleasesItWhenLeaving() {
        _ = NSApplication.shared
        let previousMainMenu = NSApp.mainMenu
        let previousWindowsMenu = NSApp.windowsMenu
        NSApp.setActivationPolicy(.accessory)
        let directory = temporaryDirectory()
        defer {
            NSApp.mainMenu = previousMainMenu
            NSApp.windowsMenu = previousWindowsMenu
            NSApp.setActivationPolicy(.accessory)
            try? FileManager.default.removeItem(at: directory)
        }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let overlay = OverlayController(shouldReduceMotion: { true })
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            isHookInstalled: { true },
            shouldReduceMotion: { true }
        )
        controller.onThemePreviewVisibilityChanged = { visible, screen in
            overlay.setThemePreviewVisible(visible, on: screen)
        }

        controller.present()
        XCTAssertEqual(controller.selectedSettingsTabTitleForTesting, "Connections")
        XCTAssertFalse(overlay.isThemePreviewActiveForTesting)
        XCTAssertFalse(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.isVisibleForTesting)

        controller.selectSettingsTabForTesting(titled: "Themes")
        waitForMainQueue(seconds: 0.2)
        XCTAssertTrue(overlay.isThemePreviewActiveForTesting)
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertTrue(overlay.isVisibleForTesting)
        XCTAssertFalse(overlay.hasHideTimerForTesting)

        overlay.toggle()
        XCTAssertTrue(overlay.isThemePreviewActiveForTesting)
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertTrue(overlay.isVisibleForTesting)

        controller.selectSettingsTabForTesting(titled: "Tasks")
        waitForMainQueue(seconds: 0.2)
        XCTAssertFalse(overlay.isThemePreviewActiveForTesting)
        XCTAssertFalse(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.isVisibleForTesting)

        controller.selectSettingsTabForTesting(titled: "Themes")
        waitForMainQueue(seconds: 0.2)
        XCTAssertTrue(overlay.isThemePreviewActiveForTesting)
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertTrue(overlay.isVisibleForTesting)

        controller.close()
        XCTAssertFalse(overlay.isThemePreviewActiveForTesting)
        XCTAssertFalse(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.isVisibleForTesting)
    }

    func testSettingsTabTransitionsPreserveFixedWindowGeometry() throws {
        _ = NSApplication.shared
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            isHookInstalled: { true },
            shouldReduceMotion: { false }
        )
        let window = try XCTUnwrap(controller.window)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let expectedSize = OnboardingWindowController.settingsContentSize
        XCTAssertEqual(controller.settingsBoundsForTesting.width, expectedSize.width, accuracy: 0.5)
        XCTAssertEqual(controller.settingsBoundsForTesting.height, expectedSize.height, accuracy: 0.5)

        for title in ["Tasks", "Sounds", "Connections", "Changelog", "Themes"] {
            controller.selectSettingsTabForTesting(titled: title)
            let transitionFinished = expectation(description: "\(title) tab transition finished")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                transitionFinished.fulfill()
            }
            wait(for: [transitionFinished], timeout: 1)

            XCTAssertEqual(
                controller.settingsBoundsForTesting.width,
                expectedSize.width,
                accuracy: 0.5,
                "\(title) changed the settings width"
            )
            XCTAssertEqual(
                controller.settingsBoundsForTesting.height,
                expectedSize.height,
                accuracy: 0.5,
                "\(title) changed the settings height"
            )
        }
    }

    func testSettingsDoNotDisturbTogglePersistsWithoutMacOSFocus() throws {
        _ = NSApplication.shared
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "CodexNotchTests.SettingsDoNotDisturb.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DoNotDisturbPreferences(defaults: defaults)
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            doNotDisturbPreferences: preferences,
            isHookInstalled: { true }
        )

        controller.showTasksForTesting()
        let disabledButton = try XCTUnwrap(controller.doNotDisturbButtonForTesting)
        XCTAssertEqual(disabledButton.title, "Off")
        disabledButton.performClick(nil)

        XCTAssertTrue(preferences.isEnabled)
        XCTAssertEqual(controller.doNotDisturbButtonForTesting?.title, "On")
    }

    func testTaskSettingsControlsHaveStableNonOverlappingLayout() throws {
        _ = NSApplication.shared
        let previousTheme = ThemeStore.shared.selectedID
        ThemeStore.shared.select(.blackout)
        defer { ThemeStore.shared.select(previousTheme) }
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            isHookInstalled: { true }
        )

        controller.showTasksForTesting()
        let frames = controller.taskLayoutFramesForTesting
        let expected = [
            "Show active tasks.title",
            "Show active tasks.detail",
            "Show active tasks.toggle",
            "Do Not Disturb.title",
            "Do Not Disturb.detail",
            "Do Not Disturb.toggle",
            "Quick Toggle.title",
            "Quick Toggle.keys",
        ]

        XCTAssertEqual(Set(frames.keys), Set(expected))
        XCTAssertFalse(controller.taskLayoutHasAmbiguityForTesting)
        for name in expected {
            let frame = try XCTUnwrap(frames[name])
            XCTAssertGreaterThan(frame.width, 0, "\(name) has no width")
            XCTAssertGreaterThan(frame.height, 0, "\(name) has no height")
            XCTAssertTrue(
                controller.settingsBoundsForTesting.contains(frame),
                "\(name) escaped the settings window"
            )
        }

        for title in ["Show active tasks", "Do Not Disturb"] {
            let titleFrame = try XCTUnwrap(frames["\(title).title"])
            let detailFrame = try XCTUnwrap(frames["\(title).detail"])
            let toggleFrame = try XCTUnwrap(frames["\(title).toggle"])
            XCTAssertFalse(titleFrame.intersects(detailFrame), "\(title) title overlaps its detail")
            XCTAssertFalse(titleFrame.intersects(toggleFrame), "\(title) title overlaps its toggle")
            XCTAssertFalse(detailFrame.intersects(toggleFrame), "\(title) detail overlaps its toggle")
            XCTAssertEqual(titleFrame.midY, toggleFrame.midY, accuracy: 2)
        }

        let shortcutTitle = try XCTUnwrap(frames["Quick Toggle.title"])
        let shortcutKeys = try XCTUnwrap(frames["Quick Toggle.keys"])
        XCTAssertFalse(shortcutTitle.intersects(shortcutKeys))
        XCTAssertGreaterThanOrEqual(shortcutKeys.minX - shortcutTitle.maxX, 15)
    }

    func testThemePreviewIsTemporaryAndSelectionPersists() {
        let suiteName = "CodexNotchTests.Theme.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let themes = ThemeStore(defaults: defaults)

        XCTAssertEqual(themes.selectedID, .obsidian)
        themes.preview(.ember)
        XCTAssertEqual(themes.activeTheme.id, .ember)
        XCTAssertEqual(themes.selectedID, .obsidian)

        themes.endPreview(.ember)
        XCTAssertEqual(themes.activeTheme.id, .obsidian)
        themes.preview(.aurora)
        themes.select(.aurora)

        XCTAssertEqual(themes.activeTheme.id, .aurora)
        XCTAssertEqual(defaults.string(forKey: ThemeStore.defaultsKey), "aurora")
        XCTAssertEqual(ThemeStore(defaults: defaults).selectedID, .aurora)
    }

    func testThemeCatalogIncludesAuthoredTypographyAndTrueBlackTheme() throws {
        XCTAssertEqual(NotchTheme.all.count, 9)
        XCTAssertEqual(NotchTheme.ID.allCases.count, NotchTheme.all.count)
        XCTAssertEqual(Set(NotchTheme.all.map(\.id)).count, NotchTheme.all.count)
        XCTAssertEqual(
            Set(NotchTheme.all.map(\.typography)),
            Set(NotchTheme.Typography.allCases)
        )

        let blackout = NotchTheme.theme(for: .blackout)
        for color in [blackout.hudTop, blackout.hudBottom, blackout.windowTint] {
            let rgb = try XCTUnwrap(color.usingColorSpace(.deviceRGB))
            XCTAssertEqual(rgb.redComponent, 0, accuracy: 0.001)
            XCTAssertEqual(rgb.greenComponent, 0, accuracy: 0.001)
            XCTAssertEqual(rgb.blueComponent, 0, accuracy: 0.001)
        }

        let terminalFont = NotchTheme.theme(for: .terminal).font(
            ofSize: 14,
            weight: .medium
        )
        XCTAssertTrue(terminalFont.fontDescriptor.symbolicTraits.contains(.monoSpace))

        let systemFont = NotchTheme.theme(for: .obsidian).font(ofSize: 14, weight: .medium)
        let editorialFont = NotchTheme.theme(for: .letterpress).font(
            ofSize: 14,
            weight: .medium
        )
        XCTAssertNotEqual(editorialFont.fontName, systemFont.fontName)
    }

    func testNotificationSoundsResolveFromPackagedApplicationResourcesWithoutModuleFallback() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resources = directory.appendingPathComponent("Contents/Resources", isDirectory: true)
        let sounds = resources
            .appendingPathComponent(NotificationSound.resourceBundleName, isDirectory: true)
            .appendingPathComponent("Sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)

        for sound in NotificationSound.allCases where sound != .none {
            let expectedURL = sounds
                .appendingPathComponent(sound.rawValue)
                .appendingPathExtension("mp3")
            try Data([0x49, 0x44, 0x33]).write(to: expectedURL)
            var usedFallback = false

            let resolvedURL = sound.resourceURL(
                applicationResourcesURL: resources,
                fallbackBundle: {
                    usedFallback = true
                    return nil
                }
            )

            XCTAssertEqual(resolvedURL, expectedURL)
            XCTAssertFalse(usedFallback, "\(sound.name) unexpectedly evaluated Bundle.module")
        }
    }

    func testMissingPackagedSoundFailsQuietlyWhenFallbackIsUnavailable() {
        let missingResources = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: missingResources) }
        var usedFallback = false

        let resolvedURL = NotificationSound.glassDrop.resourceURL(
            applicationResourcesURL: missingResources,
            fallbackBundle: {
                usedFallback = true
                return nil
            }
        )

        XCTAssertNil(resolvedURL)
        XCTAssertTrue(usedFallback)
    }
}
