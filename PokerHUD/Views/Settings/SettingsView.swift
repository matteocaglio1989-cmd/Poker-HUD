import SwiftUI

struct SettingsView: View {
    @State private var sites: [Site] = []
    @State private var selectedSite: Site?
    @State private var showingAddSite = false

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
                ForEach(sites) { site in
                    SiteRow(site: site)
                }

                Button(action: { showingAddSite = true }) {
                    Label("Add Site", systemImage: "plus.circle")
                }
            }

            Section("Database") {
                HStack {
                    Text("Total Hands")
                    Spacer()
                    Text("Loading...")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Total Players")
                    Spacer()
                    Text("Loading...")
                        .foregroundColor(.secondary)
                }

                Button("Export Database") {
                    // TODO: Export functionality
                }

                Button("Clear All Data", role: .destructive) {
                    // TODO: Confirmation dialog
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0 (Phase 1)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Build")
                    Spacer()
                    Text("Foundation Release")
                        .foregroundColor(.secondary)
                }

                Link("GitHub Repository", destination: URL(string: "https://github.com/matteocaglio1989-cmd/Poker-HUD")!)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 600)
        .task {
            await loadSites()
        }
        .sheet(isPresented: $showingAddSite) {
            AddSiteView(isPresented: $showingAddSite)
        }
    }

    private func loadSites() async {
        // TODO: Load sites from database
    }
}

struct SiteRow: View {
    let site: Site

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(site.name)
                .fontWeight(.medium)

            if let path = site.handHistoryPath {
                Text(path)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No path configured")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}

struct AddSiteView: View {
    @Binding var isPresented: Bool
    @State private var siteName = ""
    @State private var handHistoryPath = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Site Name", text: $siteName)
                TextField("Hand History Path", text: $handHistoryPath)

                Section {
                    Text("Select a supported poker site and configure the path to its hand history folder.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Poker Site")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        // TODO: Save site
                        isPresented = false
                    }
                    .disabled(siteName.isEmpty)
                }
            }
        }
        .frame(width: 500, height: 300)
    }
}
