import AppKit
import SwiftUI

/// Manages the menu bar status item for HUD-only mode
@MainActor
class MenuBarController {
    private var statusItem: NSStatusItem?
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "suit.spade.fill", accessibilityDescription: "Poker HUD")
            button.image?.size = NSSize(width: 16, height: 16)
        }

        updateMenu()
    }

    func updateMenu() {
        let menu = NSMenu()

        // HUD toggle
        let hudItem = NSMenuItem(
            title: (appState?.hudEnabled ?? false) ? "HUD Enabled" : "HUD Disabled",
            action: #selector(toggleHUD),
            keyEquivalent: "h"
        )
        hudItem.target = self
        hudItem.state = (appState?.hudEnabled ?? false) ? .on : .off
        menu.addItem(hudItem)

        // Manual recovery for multi-table swap caused by stale TCC
        // permissions or ambiguous exclusion-fallback binds. Clears the
        // cached table → window bindings; the next 500 ms reposition tick
        // re-binds every tracked table from scratch via name match (or
        // exclusion fallback if titles still unreadable).
        let resetItem = NSMenuItem(
            title: "Reset HUD Bindings",
            action: #selector(resetBindings),
            keyEquivalent: "r"
        )
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        // File watcher status
        let watcherStatus = (appState?.isFileWatcherActive ?? false) ? "Auto-Import: Active" : "Auto-Import: Inactive"
        let watcherItem = NSMenuItem(title: watcherStatus, action: nil, keyEquivalent: "")
        watcherItem.isEnabled = false
        menu.addItem(watcherItem)

        // Active tables
        if let tables = appState?.managedTables, !tables.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let tablesHeader = NSMenuItem(title: "Tables", action: nil, keyEquivalent: "")
            tablesHeader.isEnabled = false
            menu.addItem(tablesHeader)

            for table in tables {
                let tableItem = NSMenuItem(
                    title: "\(table.tableName) (\(table.stakes))",
                    action: nil,
                    keyEquivalent: ""
                )
                tableItem.state = table.isHUDVisible ? .on : .off
                menu.addItem(tableItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Show main window
        let showItem = NSMenuItem(title: "Open PokerHUD", action: #selector(showMainWindow), keyEquivalent: "o")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func toggleHUD() {
        appState?.hudEnabled.toggle()
        if !(appState?.hudEnabled ?? true) {
            appState?.hideAllHUDs()
        }
        updateMenu()
    }

    @objc private func resetBindings() {
        appState?.hudManager?.resetAllBindings()
    }

    @objc private func showMainWindow() {
        // Make sure the app is frontmost and not hidden. SwiftUI WindowGroup
        // apps that have been .hide'd (⌘H) or whose process has been
        // backgrounded need both `unhide` and `activate` to surface reliably.
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Find the main app window. On SwiftUI WindowGroup apps the main
        // window class is `SwiftUI.AppKitWindow` — we detect it by filtering
        // out the HUD NSPanels (which we own) and system panels, then
        // picking the first one that can become the main window.
        //
        // IMPORTANT: the previous implementation filtered windows whose
        // class name contained "AppKit" — which excluded the very window
        // we wanted to raise, silently doing nothing when the user clicked
        // the menu item. App Store review flagged the button as
        // unresponsive (guideline 2.1(a)), so the filter is now structural
        // (NSPanel + canBecomeMain) rather than string-based.
        let mainWindow = NSApp.windows.first { window in
            if window is NSPanel { return false }
            return window.canBecomeMain
        }

        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Fallback: no candidate window exists. This happens only when the
        // user has manually closed every window. Iterate the full NSApp
        // window list and raise whichever one we can find — SwiftUI keeps
        // its backing windows around even after a close button press, so
        // this is almost always enough to re-surface the UI.
        if let any = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            any.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quit() {
        appState?.hideAllHUDs()
        NSApp.terminate(nil)
    }
}
