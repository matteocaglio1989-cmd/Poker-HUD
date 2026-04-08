# AppBundle/

Drop-in files for the Xcode App-target wrapper that ships Poker HUD to the
Mac App Store. This directory is **not** the final location of these files
inside the shipped `.app` bundle — they're staged here so you can wire them
into a new Xcode App target via drag-drop, and so every future PR can edit
them from one canonical location at the repo root.

## Why this exists

The Poker HUD codebase is a Swift Package Manager `.executableTarget`
(`PokerHUD/`), which is perfect for day-to-day development but **cannot
produce a proper `.app` bundle for App Store submission** — SPM executables
output a bare Mach-O binary, and Xcode only wraps them in a throwaway `.app`
for ⌘R debugging. Mac App Store Connect requires an archivable `.app` bundle
with an Info.plist, entitlements, and a privacy manifest.

The solution is a thin Xcode App-target wrapper that depends on the SPM
package as a local Swift library and adds just enough around it to produce
a proper `.app`. The files in this directory are the "just enough".

## What's here

| File | Purpose |
|---|---|
| `Info.plist` | Bundle metadata + the two macOS TCC usage description strings (`NSAccessibilityUsageDescription`, `NSScreenCaptureUsageDescription`) that Apple requires for this app's permission prompts. |
| `PokerHUD.entitlements` | App Sandbox + outbound network + user-selected read-only files + security-scoped bookmarks. Nothing exotic. |
| `PrivacyInfo.xcprivacy` | Mandatory Apple privacy manifest. Declares email + purchase history + hand content collected for app functionality only, and the UserDefaults + FileTimestamp API usage with Apple's pre-approved reason codes. |

## How to wire this into a new Xcode App target (one-time, ~10 minutes)

Prerequisite: you've already pulled PR #1 so `AppBundle/` exists in your
working copy.

1. **Fully quit Xcode** (⌘Q — not just close the window).
2. In the repo root, `mkdir PokerHUDApp && cd PokerHUDApp`.
3. Launch Xcode. **File → New → Project… → macOS → App**. Click Next.
4. Project options:
   - Product Name: `PokerHUD`
   - Team: pick your real Apple Developer Team
   - Organization Identifier: `com.pokerhud`
   - Bundle Identifier: Xcode will auto-populate to `com.pokerhud.PokerHUD`
     — **manually change it to `com.pokerhud.app`** to match `Info.plist`
     and the App Store Connect record.
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None**
   - Include Tests: unticked (the SPM package keeps its own test target).
5. Click Next, navigate to `<repo>/PokerHUDApp/`, Save. Xcode creates
   `PokerHUDApp/PokerHUD.xcodeproj/`.
6. In the project navigator, select the generated `PokerHUDApp.swift` file
   (Xcode's boilerplate `@main` struct) and **delete it from disk** —
   the real entry point is `PokerHUD/App/PokerHUDApp.swift` from the SPM
   package, which PR #2 will expose as a public library product.
7. **File → Add Package Dependencies… → Add Local… → select the repo
   root** (where `Package.swift` lives). Add the `PokerHUD` library
   product as a dependency of the new App target.
8. In Finder, open the repo-root `AppBundle/` folder and drag the three
   files (`Info.plist`, `PokerHUD.entitlements`, `PrivacyInfo.xcprivacy`)
   onto the Xcode project navigator's root group.
   - **Copy items if needed: NO** (so they stay in `AppBundle/` at repo
     root and can be edited from there).
   - **Add to targets: PokerHUD** (the new App target).
9. In the PokerHUD target → Build Settings, search for:
   - `INFOPLIST_FILE` → set to `../AppBundle/Info.plist`
   - `CODE_SIGN_ENTITLEMENTS` → set to `../AppBundle/PokerHUD.entitlements`
   - Verify `PrivacyInfo.xcprivacy` is listed under the target's
     "Copy Bundle Resources" build phase (drag-drop usually adds it
     automatically).
10. In the PokerHUD target → Signing & Capabilities:
    - Tick **Automatically manage signing**.
    - Team: pick your real Apple Developer team.
    - Verify the **App Sandbox** capability appears auto-populated from
      the entitlements file with these boxes ticked:
      - Network → Outgoing Connections (Client)
      - File Access → User Selected File: Read Only
11. Product → Scheme → Edit Scheme → Run → Info: verify the Executable is
    `PokerHUD.app` (the new App target), not the old SPM binary.
12. ⌘R. Expected: the app launches, sign-in works, Phase 4 Replayer works,
    and `Xcode → Debug → StoreKit → Manage Transactions` is now accessible
    (because the new App target correctly picks up the
    `MacOSPokerHud.storekit` config from the scheme's Options tab).

After step 12 succeeds, `git add PokerHUDApp/` and commit — that becomes
PR #2, which also updates `Package.swift` to expose `PokerHUD` as a
`.library(...)` product, drops the `@main` attribute from
`PokerHUDApp.swift`, and removes the now-obsolete `fix-storekit-membership.sh`
scripts.

## Editing these files in the future

All three files live here at repo root. Editing them in place (via Xcode's
editor or any text editor) keeps the source of truth in one location. The
Xcode App target references them via `INFOPLIST_FILE` / `CODE_SIGN_ENTITLEMENTS`
build settings plus the Copy Bundle Resources phase — no file duplication.

## Not in this directory (by design)

- **App icons** — live in the Xcode App target's asset catalog, not here.
  Add them before your first App Store submission.
- **Swift source files** — those are all under `PokerHUD/` in the SPM
  package. The Xcode App target pulls them in via the local package
  dependency; don't add Swift files to the App target directly.
