import Foundation
import Sparkle

@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #if DEBUG
        // The dev app shares nothing with the signed release, so it must not check for updates.
        automaticallyChecksForUpdates = false
        #else
        // Sparkle refuses to start (and alerts) without a public EdDSA key.
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        if !publicKey.isEmpty {
            controller.startUpdater()
        }
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = canCheck }
        }
        #endif
    }

    var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
