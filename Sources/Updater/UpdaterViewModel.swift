import Foundation
import Sparkle

/// Wraps Sparkle's standard updater so SwiftUI can trigger "Check for Updates…".
///
/// The updater only starts if a real EdDSA public key is present in Info.plist (`SUPublicEDKey`).
/// Until you generate keys and publish a signed release (see README → Distribution), the updater
/// stays disabled and the UI hides its update controls — instead of showing Sparkle's
/// "updater failed to start" error.
@MainActor
final class UpdaterViewModel: ObservableObject {

    /// True once `SUPublicEDKey` has been filled in with a real key.
    let isConfigured: Bool

    private let controller: SPUStandardUpdaterController?

    @Published private(set) var canCheckForUpdates = false

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isConfigured = !key.isEmpty && key != "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"

        guard isConfigured else {
            controller = nil
            return
        }

        let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                      updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// User-initiated update check (from the popover menu).
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}
