import SwiftUI
import AppKit

/// Top-level router that swaps between the database-error screen, the
/// auth screen, the paywall, a loading spinner while the entitlement
/// resolves, and the main app UI.
///
/// The database-error screen is the first gate: if
/// `DatabaseManager.shared.initializationError` is non-nil the local
/// SQLite store could not be opened (disk full, permissions, corrupt
/// file), every downstream view would crash on its first repository
/// call, so we short-circuit with a one-page message and invite the
/// user to quit cleanly. This replaces the previous
/// `fatalError("Failed to initialize database: ...")` which would have
/// been an automatic App Store rejection on first-launch.
struct RootRouterView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if let dbError = DatabaseManager.shared.initializationError {
                DatabaseErrorView(error: dbError)
            } else if !appState.authService.isAuthenticated {
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

/// One-page error view shown when `DatabaseManager` could not open the
/// local SQLite store. Displays the underlying error message plus a
/// "Quit" button. No recovery actions (reset / delete / migrate) —
/// keeping the scope narrow so the view itself can't introduce a
/// second failure mode.
struct DatabaseErrorView: View {
    let error: Error

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
            Text("Couldn't open the local database")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Poker HUD needs a local SQLite store in your Application Support folder. macOS refused to create or open it. Please quit and try again, or restart your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520)

            VStack(alignment: .leading, spacing: 4) {
                Text("Error details")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(error.localizedDescription)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.1))
                    )
            }

            Button("Quit Poker HUD") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
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

/// Root SwiftUI App. Public so the Xcode App-target wrapper
/// (`PokerHUDApp/PokerHUDApp/PokerHUDApp.xcodeproj`) can `import PokerHUD`
/// and call `PokerHUDApp.main()` from a thin `@main` entry-point file.
///
/// The `@main` attribute lives in the Xcode App target (not here) because
/// SwiftUI Previews + Xcode's runtime routing expect the top-level entry
/// point to be inside the App target where the Info.plist, entitlements,
/// and sandbox capabilities are applied. This file is still the single
/// source of truth for the app's scene graph — the Xcode-side entry
/// point is a one-line wrapper that calls `PokerHUDApp.main()`.
///
/// Note on opaque return types: the `public var body: some Scene`
/// signature hides every internal view type (`RootRouterView`,
/// `SettingsView`, etc.), so no other file in the module needs to be
/// made `public` to satisfy the consumer's visibility rules.
public struct PokerHUDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    public init() {}

    public var body: some Scene {
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
