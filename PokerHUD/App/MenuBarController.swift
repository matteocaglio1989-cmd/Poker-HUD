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
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isKeyWindow == false && $0.className.contains("AppKit") == false }) {
            window.makeKeyAndOrderFront(nil)
        }
        // Activate the app to bring windows forward
        for window in NSApp.windows {
            if !window.title.isEmpty {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }

    @objc private func quit() {
        appState?.hideAllHUDs()
        NSApp.terminate(nil)
    }
}
