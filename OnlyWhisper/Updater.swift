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
        canCheckForUpdates = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            guard let canCheck = change.newValue else { return }
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
