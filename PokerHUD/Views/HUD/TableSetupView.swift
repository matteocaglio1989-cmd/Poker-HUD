import SwiftUI

/// View for manually configuring active poker tables and seat assignments
struct TableSetupView: View {
    @EnvironmentObject var appState: AppState

    @State private var showAddTable = false
    @State private var newTableName = ""
    @State private var newTableSize = 6
    @State private var newStakes = "0.5/1.0"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("HUD Setup")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Configure tables and player positions for HUD overlay")
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    // Global HUD toggle
                    Toggle("HUD Enabled", isOn: $appState.hudEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: appState.hudEnabled) { _, enabled in
                            if !enabled {
                                appState.hideAllHUDs()
                            }
                        }

                    Button(action: { showAddTable = true }) {
                        Label("Add Table", systemImage: "plus.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

                // File Watcher status
                FileWatcherStatusView()
                    .environmentObject(appState)
                    .padding(.horizontal)

                // Table list
                if appState.managedTables.isEmpty {
                    EmptyTableView()
                } else {
                    ForEach($appState.managedTables) { $table in
                        TableCard(table: $table)
                            .environmentObject(appState)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddTable) {
            NavigationStack {
                AddTableSheet(
                    tableName: $newTableName,
                    tableSize: $newTableSize,
                    stakes: $newStakes,
                    onAdd: {
                        appState.addTable(name: newTableName, tableSize: newTableSize, stakes: newStakes)
                        newTableName = ""
                        showAddTable = false
                    },
                    onCancel: { showAddTable = false }
                )
            }
        }
    }
}

/// Card for a single table showing seats and controls
struct TableCard: View {
    @Binding var table: ActiveTable
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Table header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(table.tableName)
                        .font(.headline)
                    Text("\(table.site) - \(table.stakes) - \(table.tableSize)-max")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(table.isHUDVisible ? "Hide HUD" : "Show HUD") {
                    if table.isHUDVisible {
                        appState.hideHUD(for: table)
                        table.isHUDVisible = false
                    } else {
                        table.isHUDVisible = true
                        appState.showHUD(for: table)
                    }
                }
                .buttonStyle(.bordered)
                .tint(table.isHUDVisible ? .red : .green)

                Button(role: .destructive) {
                    appState.removeTable(id: table.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }

            // Seat grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 8) {
                ForEach($table.seatAssignments) { $seat in
                    SeatCell(seat: $seat)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

/// Cell for a single seat with editable player name
struct SeatCell: View {
    @Binding var seat: SeatAssignment

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: seat.playerName != nil ? "person.circle.fill" : "person.circle")
                .font(.title2)
                .foregroundColor(seat.playerName != nil ? .green : .secondary)

            Text("Seat \(seat.seatNumber)")
                .font(.caption2)
                .foregroundColor(.secondary)

            TextField("Player name", text: Binding(
                get: { seat.playerName ?? "" },
                set: { seat.playerName = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
        }
        .padding(6)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

/// Sheet for adding a new table
struct AddTableSheet: View {
    @Binding var tableName: String
    @Binding var tableSize: Int
    @Binding var stakes: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    @FocusState private var isTableNameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Table name (e.g. Vega III)", text: $tableName)
                    .focused($isTableNameFocused)

                Picker("Table Size", selection: $tableSize) {
                    Text("6-max").tag(6)
                    Text("9-max").tag(9)
                }
                .pickerStyle(.segmented)

                TextField("Stakes (e.g. 0.5/1.0)", text: $stakes)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Add Poker Table")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add Table", action: onAdd)
                    .disabled(tableName.isEmpty)
            }
        }
        .fixSheetFocus()
        .onAppear {
            isTableNameFocused = true
        }
        .frame(width: 400, height: 220)
    }
}

/// File watcher status indicator
struct FileWatcherStatusView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.isFileWatcherActive ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(appState.isFileWatcherActive ? "File Watcher Active" : "File Watcher Inactive")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if let path = appState.handHistoryPath {
                Text(path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Button("Configure") {
                // Navigate to settings or show path picker
                appState.pickHandHistoryDirectory()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

/// Empty state when no tables are configured
struct EmptyTableView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No tables configured")
                .font(.headline)
            Text("Add a poker table and assign player names to seats to start the HUD overlay")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}
