import SwiftUI

/// App entry point. A menu-bar-only (`LSUIElement`) app: one `MenuBarExtra` popover plus a
/// standard `Settings` scene. State lives in a single shared `AppStore`.
@main
struct R2Git2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    @StateObject private var updater = UpdaterViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store, updater: updater)
        } label: {
            MenuBarLabel(reviewCount: store.reviewCount, hasFailure: store.hasRecentFailure)
        }
        .menuBarExtraStyle(.window)   // custom popover, not a system menu

        Settings {
            SettingsView(store: store, updater: updater)
        }
    }
}
