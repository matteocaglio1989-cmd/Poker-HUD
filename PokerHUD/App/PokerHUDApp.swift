import SwiftUI
import AppKit

/// Top-level router that swaps between the auth screen, the paywall, a
/// loading spinner while the entitlement resolves, and the main app UI.
struct RootRouterView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if !appState.authService.isAuthenticated {
                AuthContainerView()
            } else {
                switch appState.subscriptionManager.entitlement {
                case .unknown:
                    ProgressView("Checking your subscription…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .active, .trial:
                    // The trial banner (when on a free trial) is rendered
                    // by MainView itself at the bottom of the sidebar
                    // column via .safeAreaInset, so it never overlaps a
                    // nav item or the detail pane.
                    MainView()
                case .expired:
                    PaywallView()
                }
            }
        }
    }
}

/// Forces the process into a regular GUI activation policy and brings it to
/// the foreground at launch. Without this, a SwiftUI `@main` running from an
/// SPM `.executableTarget` (or any binary that lacks the right Info.plist
/// keys) starts as an "accessory" process: the window draws and can take
/// mouse focus, but it can never become the key window — text fields visibly
/// focus but reject keyboard input, and no main menu is installed. Calling
/// `setActivationPolicy(.regular)` on an already-regular process is a no-op,
/// so this is also safe in a "real" Xcode App project.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct PokerHUDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootRouterView()
                .environmentObject(appState)
                .frame(minWidth: 1200, minHeight: 800)
                .onAppear {
                    appState.setupMenuBar()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
