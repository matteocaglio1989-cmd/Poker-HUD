import PokerHUD
import SwiftUI

/// Thin `@main` entry point for the Xcode App target wrapper.
///
/// The real SwiftUI app (scene graph, state, router, etc.) lives inside
/// the `PokerHUD` Swift package at `PokerHUD/App/PokerHUDApp.swift`. That
/// file used to carry the `@main` attribute, but it was moved here in
/// the Package.swift → library restructure so:
///
///   1. The `@main` symbol resolves inside the Xcode App target itself,
///      which is where SwiftUI Previews, Info.plist keys, entitlements,
///      and code signing are applied.
///   2. The SPM library (`PokerHUD`) can still be imported by tests,
///      future CLI helpers, or a secondary app target without fighting
///      over which module owns `@main`.
///   3. Changing the app's scene graph still only means editing one
///      file (`PokerHUD/App/PokerHUDApp.swift`); this file is stable
///      and should rarely need touching.
///
/// `PokerHUDApp.main()` is the static method provided by the `App`
/// protocol's default implementation — it kicks off the SwiftUI
/// runtime, installs the `NSApplicationDelegateAdaptor`, and blocks
/// the process for the lifetime of the app.
@main
enum PokerHUDAppMain {
    static func main() {
        PokerHUDApp.main()
    }
}
