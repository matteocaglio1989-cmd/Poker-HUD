import SwiftUI

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
                    MainView()
                        .overlay(alignment: .top) {
                            if case .trial(let remaining) = appState.subscriptionManager.entitlement {
                                TrialBannerView(remainingSeconds: remaining)
                            }
                        }
                case .expired:
                    PaywallView()
                }
            }
        }
    }
}

@main
struct PokerHUDApp: App {
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
