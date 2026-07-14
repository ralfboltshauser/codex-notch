import Foundation
import Sparkle

final class UpdateCoordinator: NSObject, SPUUpdaterDelegate {
    private static let probeInterval: TimeInterval = 6 * 60 * 60
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var timer: Timer?

    var onAvailabilityChanged: ((String?) -> Void)?

    func start() {
        _ = controller
        DispatchQueue.main.async { [weak self] in
            self?.checkForUpdateInformation()
        }
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.probeInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkForUpdateInformation()
        }
    }

    func checkForUpdateInformation() {
        guard controller.updater.canCheckForUpdates else { return }
        controller.updater.checkForUpdateInformation()
    }

    func installAvailableUpdate() {
        checkForUpdates()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onAvailabilityChanged?(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        onAvailabilityChanged?(nil)
    }
}
