import AppKit
import XCTest
@testable import CodexNotchApp

final class OnboardingTests: CodexNotchTestCase {
    func testJourneyRequiresRealSetupAndTracksPractice() {
        var journey = OnboardingJourney(hookInstalled: false, hookTrusted: false)

        XCTAssertEqual(journey.step, .welcome)
        XCTAssertEqual(journey.progress, 0.25, accuracy: 0.001)
        XCTAssertEqual(journey.advance(), .connect)
        XCTAssertFalse(journey.canAdvance)
        XCTAssertEqual(journey.advance(), .connect)

        journey.updateHook(installed: true, trusted: false)
        XCTAssertFalse(journey.canAdvance)
        journey.updateHook(installed: true, trusted: true)
        XCTAssertTrue(journey.canAdvance)
        XCTAssertEqual(journey.advance(), .practice)
        XCTAssertFalse(journey.openedNotch)

        journey.markNotchOpened()
        XCTAssertTrue(journey.openedNotch)
        XCTAssertEqual(journey.advance(), .ready)
        XCTAssertEqual(journey.progress, 1, accuracy: 0.001)
        XCTAssertEqual(journey.goBack(), .practice)
    }

    func testInstallTrustPracticeAndFirstSuccessFlow() {
        _ = NSApplication.shared
        withRestoredCompletionDefault {
            UserDefaults.standard.set(false, forKey: OnboardingWindowController.completionKey)
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let pairings = PairingStore(
                fileURL: directory.appendingPathComponent("pairings.json")
            )
            let pairer = RemoteHostPairer(store: pairings) { _ in }
            var installed = false
            var trusted = false
            var reviewOpened = false
            var notchOpened = false
            let controller = OnboardingWindowController(
                pairings: pairings,
                pairer: pairer,
                isHookInstalled: { installed },
                isHookTrusted: { trusted },
                installHook: { installed = true },
                openHookReview: {
                    reviewOpened = true
                    trusted = true
                },
                startInOnboarding: true,
                shouldReduceMotion: { true }
            )
            controller.onTryNotch = { notchOpened = true }

            XCTAssertEqual(controller.onboardingStepForTesting, .welcome)
            XCTAssertFalse(controller.onboardingHasAmbiguityForTesting)
            controller.onboardingPrimaryButtonForTesting?.performClick(nil)
            XCTAssertEqual(controller.onboardingStepForTesting, .connect)

            XCTAssertEqual(
                controller.onboardingPrimaryButtonForTesting?.title,
                "Install Completion Hook"
            )
            controller.onboardingPrimaryButtonForTesting?.performClick(nil)
            XCTAssertTrue(installed)
            XCTAssertEqual(
                controller.onboardingPrimaryButtonForTesting?.title,
                "Review in Codex…"
            )
            controller.onboardingPrimaryButtonForTesting?.performClick(nil)
            XCTAssertTrue(reviewOpened)
            XCTAssertEqual(controller.onboardingPrimaryButtonForTesting?.title, "Continue")
            controller.onboardingPrimaryButtonForTesting?.performClick(nil)
            XCTAssertEqual(controller.onboardingStepForTesting, .practice)

            controller.onboardingPrimaryButtonForTesting?.performClick(nil)
            XCTAssertTrue(notchOpened)
            controller.notchVisibilityChanged(true)
            XCTAssertEqual(controller.onboardingPrimaryButtonForTesting?.title, "Continue")
            controller.onboardingPrimaryButtonForTesting?.performClick(nil)
            XCTAssertEqual(controller.onboardingStepForTesting, .ready)
            controller.onboardingPrimaryButtonForTesting?.performClick(nil)

            XCTAssertTrue(UserDefaults.standard.bool(
                forKey: OnboardingWindowController.completionKey
            ))
            XCTAssertNil(controller.onboardingStepForTesting)
            XCTAssertEqual(controller.selectedSettingsTabTitleForTesting, "Connections")
        }
    }

    func testConnectionsCanReplayWithoutResettingCompletion() throws {
        _ = NSApplication.shared
        try withRestoredCompletionDefault {
            UserDefaults.standard.set(true, forKey: OnboardingWindowController.completionKey)
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let pairings = PairingStore(
                fileURL: directory.appendingPathComponent("pairings.json")
            )
            let pairer = RemoteHostPairer(store: pairings) { _ in }
            let controller = OnboardingWindowController(
                pairings: pairings,
                pairer: pairer,
                isHookInstalled: { true },
                isHookTrusted: { true },
                shouldReduceMotion: { true }
            )

            let replay = try XCTUnwrap(controller.replayOnboardingButtonForTesting)
            XCTAssertEqual(replay.title, "Replay Onboarding…")
            replay.performClick(nil)

            XCTAssertEqual(controller.onboardingStepForTesting, .welcome)
            XCTAssertTrue(UserDefaults.standard.bool(
                forKey: OnboardingWindowController.completionKey
            ))
            XCTAssertFalse(controller.onboardingHasAmbiguityForTesting)
        }
    }

    private func withRestoredCompletionDefault<T>(
        _ operation: () throws -> T
    ) rethrows -> T {
        let previous = UserDefaults.standard.object(
            forKey: OnboardingWindowController.completionKey
        )
        defer {
            if let previous {
                UserDefaults.standard.set(
                    previous,
                    forKey: OnboardingWindowController.completionKey
                )
            } else {
                UserDefaults.standard.removeObject(
                    forKey: OnboardingWindowController.completionKey
                )
            }
        }
        return try operation()
    }
}
