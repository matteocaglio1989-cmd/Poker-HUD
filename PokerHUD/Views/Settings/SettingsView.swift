import SwiftUI
import AppKit
import GRDB

struct SettingsView: View {
    @State private var sites: [Site] = []
    @State private var showingAddSite = false
    @State private var editingSite: Site? = nil
    @State private var totalHands = 0
    @State private var totalPlayers = 0

    var body: some View {
        Form {
            Section {
                Text("Poker HUD")
                    .font(.title)
                    .fontWeight(.bold)
                Text("macOS Poker Tracker & HUD")
                    .foregroundColor(.secondary)
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

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("2.0.0 (Phase 2)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Build")
                    Spacer()
                    Text("HUD Overlay Release")
                        .foregroundColor(.secondary)
                }

                Link("GitHub Repository", destination: URL(string: "https://github.com/matteocaglio1989-cmd/Poker-HUD")!)
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
            print("Error loading settings data: \(error)")
        }
    }

    private func clearAllData() {
        do {
            try HandRepository().deleteAll()
            Task { await loadData() }
        } catch {
            print("Error clearing data: \(error)")
        }
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
            print("Error updating site: \(error)")
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
                var site = Site(
                    id: nil,
                    name: siteName,
                    handHistoryPath: handHistoryPath.isEmpty ? nil : handHistoryPath,
                    autoImport: true
                )
                try site.insert(db)
            }
        } catch {
            print("Error saving site: \(error)")
        }
    }
}
