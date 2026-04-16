import SwiftUI
import AppKit
import GRDB

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var sites: [Site] = []
    @State private var showingAddSite = false
    @State private var editingSite: Site? = nil
    @State private var totalHands = 0
    @State private var totalPlayers = 0
    @State private var screenRecordingGranted = PokerStarsWindowDetector.hasScreenRecordingPermission()
    @State private var tableLayoutMode: TableLayoutMode = TableLayoutMode.load()
    @State private var showDeleteAccountConfirm = false
    @State private var showDeleteAccountError = false
    @State private var deleteAccountInProgress = false

    var body: some View {
        Form {
            Section {
                Text("Poker HUD")
                    .font(.title)
                    .fontWeight(.bold)
                Text("macOS Poker Tracker & HUD")
                    .foregroundColor(.secondary)
            }

            Section("Account") {
                HStack {
                    Text("Signed in as")
                    Spacer()
                    Text(appState.authService.currentEmail ?? "—")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("Sign Out", role: .destructive) {
                    Task { await appState.authService.signOut() }
                }

                Button("Delete Account", role: .destructive) {
                    showDeleteAccountConfirm = true
                }
                .disabled(deleteAccountInProgress)
            }

            Section("Subscription") {
                HStack {
                    Text("Plan")
                    Spacer()
                    Text(planLabel)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(renewalRowLabel)
                    Spacer()
                    Text(renewalRowValue)
                        .foregroundColor(.secondary)
                }

                Button("Manage Subscription") {
                    appState.subscriptionManager.openManageSubscriptions()
                }

                Button("Restore Purchases") {
                    Task { await appState.subscriptionManager.restorePurchases() }
                }
            }

            Section("Poker Sites") {
                if sites.isEmpty {
                    Text("No sites configured")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(sites) { site in
                        SiteRow(site: site, onEdit: {
                            editingSite = site
                        })
                    }
                }

                Button(action: { showingAddSite = true }) {
                    Label("Add Site", systemImage: "plus.circle")
                }
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Screen Recording",
                    description: "Required. Lets PokerHUD read PokerStars window titles so HUD panels bind to the correct table. No screen content is recorded or transmitted.",
                    granted: screenRecordingGranted,
                    openAction: {
                        PokerStarsWindowDetector.requestScreenRecordingPermission()
                        // Re-check after the system dialog — the user may
                        // have granted inline. If they went to Settings we
                        // will pick it up on the next appearance of this view.
                        screenRecordingGranted = PokerStarsWindowDetector.hasScreenRecordingPermission()
                    }
                )

                Button("Re-check Permissions") {
                    screenRecordingGranted = PokerStarsWindowDetector.hasScreenRecordingPermission()
                }
            }

            Section("HUD") {
                Picker("Table Layout", selection: $tableLayoutMode) {
                    ForEach(TableLayoutMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: tableLayoutMode) { _, newValue in
                    TableLayoutMode.save(newValue)
                }
                Text(tableLayoutMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Database") {
                HStack {
                    Text("Total Hands")
                    Spacer()
                    Text("\(totalHands)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Total Players")
                    Spacer()
                    Text("\(totalPlayers)")
                        .foregroundColor(.secondary)
                }

                Button("Clear All Data", role: .destructive) {
                    clearAllData()
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 600)
        .task {
            await loadData()
        }
        .sheet(isPresented: $showingAddSite, onDismiss: {
            Task { await loadData() }
        }) {
            AddSiteView(isPresented: $showingAddSite)
        }
        .sheet(item: $editingSite, onDismiss: {
            Task { await loadData() }
        }) { site in
            EditSiteView(site: site, onDismiss: { editingSite = nil })
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task { await performDeleteAccount() }
            }
        } message: {
            Text("This permanently deletes your PokerEye account, your subscription record, and all usage data from our servers. Your local hand history files on this Mac are not affected. This cannot be undone.\n\nIf you have an active subscription, you must cancel it separately in the App Store — Apple does not allow apps to cancel subscriptions on your behalf.")
        }
        .alert("Could Not Delete Account", isPresented: $showDeleteAccountError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.authService.authError ?? "Something went wrong. Please try again.")
        }
    }

    /// Invoke the `delete-account` edge function. On success the user is
    /// signed out locally and the app returns to the sign-in screen.
    private func performDeleteAccount() async {
        deleteAccountInProgress = true
        defer { deleteAccountInProgress = false }
        let ok = await appState.authService.deleteAccount()
        if !ok {
            showDeleteAccountError = true
        }
    }

    // MARK: - Subscription row labels

    private var planLabel: String {
        switch appState.subscriptionManager.entitlement {
        case .unknown:  return "—"
        case .trial:    return "Free trial"
        case .expired:  return "Expired"
        case .active(let plan, _): return plan.displayName
        }
    }

    private var renewalRowLabel: String {
        switch appState.subscriptionManager.entitlement {
        case .trial:  return "Trial remaining"
        case .active: return "Renews on"
        default:      return "Status"
        }
    }

    private var renewalRowValue: String {
        switch appState.subscriptionManager.entitlement {
        case .unknown:
            return "—"
        case .trial(let remaining):
            return TrialBannerView.format(remainingHands: remaining)
        case .expired:
            return "Please subscribe to continue"
        case .active(_, let expiresAt):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: expiresAt)
        }
    }

    private func loadData() async {
        do {
            let loaded: [Site] = try await DatabaseManager.shared.reader.read { db in
                try Site.fetchAll(db)
            }
            sites = loaded

            let hands = try HandRepository().count()
            let players = try PlayerRepository().count()
            totalHands = hands
            totalPlayers = players
        } catch {
            Log.app.error("Error loading settings data: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearAllData() {
        do {
            try HandRepository().deleteAll()
            Task { await loadData() }
        } catch {
            Log.app.error("Error clearing data: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// A single row in the Settings "Permissions" section. Shows the current
/// grant state with a coloured icon and a button that routes the user to
/// the right place to toggle it (inline prompt for Screen Recording).
struct PermissionRow: View {
    let title: String
    let description: String
    let granted: Bool
    let openAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(granted ? .green : .orange)
                Text(title)
                    .fontWeight(.medium)
                Spacer()
                Text(granted ? "Granted" : "Not granted")
                    .foregroundColor(.secondary)
                    .font(.caption)
                if !granted {
                    Button("Open…", action: openAction)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct SiteRow: View {
    let site: Site
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(site.name)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    if let path = site.handHistoryPath, !path.isEmpty {
                        Text(path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("No path configured — click to set up")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Edit an existing site's settings
struct EditSiteView: View {
    let site: Site
    let onDismiss: () -> Void

    @State private var siteName: String = ""
    @State private var handHistoryPath: String = ""
    @State private var autoImport: Bool = true

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit \(site.name)")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                // Site Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Site Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Site name", text: $siteName)
                        .textFieldStyle(.roundedBorder)
                }

                // Hand History Path
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hand History Path")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text(handHistoryPath.isEmpty ? "No folder selected" : handHistoryPath)
                            .font(.system(size: 12))
                            .foregroundColor(handHistoryPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)

                        Button("Browse...") {
                            pickFolder()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Auto Import toggle
                Toggle("Auto-import new hands", isOn: $autoImport)
            }

            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save") {
                    saveSite()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(siteName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
        .fixSheetFocus()
        .onAppear {
            siteName = site.name
            handHistoryPath = site.handHistoryPath ?? ""
            autoImport = site.autoImport
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the hand history folder for \(siteName)"

        if panel.runModal() == .OK, let url = panel.url {
            handHistoryPath = url.path
        }
    }

    private func saveSite() {
        guard let siteId = site.id else { return }
        do {
            try DatabaseManager.shared.writer.write { db in
                let updatedSite = Site(
                    id: siteId,
                    name: siteName,
                    handHistoryPath: handHistoryPath.isEmpty ? nil : handHistoryPath,
                    autoImport: autoImport
                )
                try updatedSite.update(db)
            }
        } catch {
            Log.app.error("Error updating site: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct AddSiteView: View {
    @Binding var isPresented: Bool
    @State private var siteName = ""
    @State private var handHistoryPath = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Poker Site")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Site Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g. PokerStars", text: $siteName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Hand History Path")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text(handHistoryPath.isEmpty ? "No folder selected" : handHistoryPath)
                            .font(.system(size: 12))
                            .foregroundColor(handHistoryPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)

                        Button("Browse...") {
                            pickFolder()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Text("Select a supported poker site and configure the path to its hand history folder.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button("Add") {
                    saveSite()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(siteName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
        .fixSheetFocus()
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the hand history folder for \(siteName.isEmpty ? "this site" : siteName)"

        if panel.runModal() == .OK, let url = panel.url {
            handHistoryPath = url.path
        }
    }

    private func saveSite() {
        do {
            try DatabaseManager.shared.writer.write { db in
                // `let` because GRDB 7's `insert(_:)` is not a `mutating`
                // method on MutablePersistableRecord — capturing the new
                // rowID would require `insertAndFetch(_:)`, which we don't
                // need here. The compiler warning that prompted this fix
                // was correct: the local was never reassigned.
                let site = Site(
                    id: nil,
                    name: siteName,
                    handHistoryPath: handHistoryPath.isEmpty ? nil : handHistoryPath,
                    autoImport: true
                )
                try site.insert(db)
            }
        } catch {
            Log.app.error("Error saving site: \(error.localizedDescription, privacy: .public)")
        }
    }
}
