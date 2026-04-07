import SwiftUI

@main
struct PokerHUDApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.authService.isAuthenticated {
                    MainView()
                } else {
                    AuthContainerView()
                }
            }
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
