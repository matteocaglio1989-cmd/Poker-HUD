import SwiftUI

/// Phase 3 PR3 + Phase 4 PR3: opponent deep-dive sheet, presented from a
/// player row tap in `ReportsView`'s `PlayerStatsTable`. Reuses
/// `SituationalStatsView` from PR2 to render the opponent's situational
/// breakdown so a poker player can answer "how does this villain play in
/// 3-bet pots?" without switching tabs.
///
/// Four sections:
///   1. Header card — name, sample size, player type, BB/100
///   2. Headline preflop stats grid
///   3. Embedded SituationalStatsView with the opponent's flop / turn /
///      river splits (loaded lazily on appear)
///   4. Phase 4 PR3 **Notes** section — list of every `PlayerNote` for
///      this opponent with edit / delete / add affordances driven by
///      `PlayerNoteEditorSheet`.
struct OpponentDetailView: View {
    let opponent: PlayerStats
    let filters: StatFilters

    @Environment(\.dismiss) private var dismiss
    @State private var situational: SituationalStats?
    @State private var isLoading = false
    @State private var notes: [PlayerNote] = []
    @State private var resolvedPlayerId: Int64?
    @State private var noteSheetMode: PlayerNoteEditorSheet.Mode?

    private let playerRepo = PlayerRepository()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    preflopGrid

                    if isLoading {
                        ProgressView("Loading situational stats…")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        SituationalStatsView(
                            stats: situational,
                            heroName: opponent.playerName
                        )
                    }

                    notesSection
                }
                .padding(.vertical)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .task {
            await loadSituational()
            loadNotes()
        }
        .sheet(item: $noteSheetMode) { mode in
            PlayerNoteEditorSheet(
                mode: mode,
                onSave: { savedNote in
                    handleNoteSaved(savedNote, mode: mode)
                },
                onDelete: deleteHandler(for: mode)
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(opponent.playerName)
                        .font(.title2)
                        .fontWeight(.bold)
                    PlayerTypeBadge(type: opponent.playerType, fontSize: 11)
                }
                Text("\(opponent.handsPlayed) hands sample")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("BB/100")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%+.2f", opponent.bb100))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(opponent.bb100 >= 0 ? .green : .red)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Preflop stat grid

    private var preflopGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preflop")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: 12)],
                spacing: 12
            ) {
                statTile("VPIP",       value: opponent.vpip)
                statTile("PFR",        value: opponent.pfr)
                statTile("3-Bet",      value: opponent.threeBet)
                statTile("4-Bet",      value: opponent.fourBet)
                statTile("Fold to 3B", value: opponent.foldToThreeBet)
                statTile("Cold Call",  value: opponent.coldCall)
                statTile("Squeeze",    value: opponent.squeeze)
                statTile("AF",         value: opponent.aggressionFactor, isPercent: false, decimals: 1)
                statTile("WTSD",       value: opponent.wtsd)
                statTile("W$SD",       value: opponent.wsd)
            }
            .padding(.horizontal)
        }
    }

    private func statTile(
        _ label: String,
        value: Double,
        isPercent: Bool = true,
        decimals: Int = 1
    ) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(isPercent
                 ? String(format: "%.\(decimals)f%%", value)
                 : String(format: "%.\(decimals)f", value))
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    // MARK: - Notes section (PR3)

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes")
                    .font(.headline)
                Spacer()
                Button {
                    if let pid = resolvedPlayerId {
                        noteSheetMode = .add(playerId: pid)
                    }
                } label: {
                    Label("Add note", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(resolvedPlayerId == nil)
            }
            .padding(.horizontal)

            if resolvedPlayerId == nil {
                Text("No matching player record in the local database.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else if notes.isEmpty {
                Text("No notes yet — tap “Add note” to record observations on this player.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(notes) { note in
                        noteRow(note)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func noteRow(_ note: PlayerNote) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(NoteColor.from(rawValue: note.color).swatch)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(note.note ?? "")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note.updatedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                noteSheetMode = .edit(note)
            } label: {
                Image(systemName: "pencil")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit note")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Loading

    private func loadNotes() {
        // Look up the local player id by username (the only stable
        // identifier we have on `PlayerStats`). If the player isn't in
        // the local DB yet, the notes section shows a friendly empty
        // state instead of crashing.
        if resolvedPlayerId == nil {
            do {
                if let player = try playerRepo.fetchByUsername(opponent.playerName),
                   let id = player.id {
                    resolvedPlayerId = id
                }
            } catch {
                print("[OpponentDetailView] resolve player id failed: \(error)")
            }
        }
        guard let pid = resolvedPlayerId else {
            notes = []
            return
        }
        do {
            notes = try playerRepo.fetchNotes(forPlayerId: pid)
        } catch {
            print("[OpponentDetailView] fetch notes failed: \(error)")
            notes = []
        }
    }

    private func handleNoteSaved(_ note: PlayerNote, mode: PlayerNoteEditorSheet.Mode) {
        switch mode {
        case .add:
            notes.insert(note, at: 0)
        case .edit:
            if let idx = notes.firstIndex(where: { $0.id == note.id }) {
                notes[idx] = note
            }
        }
    }

    private func deleteHandler(for mode: PlayerNoteEditorSheet.Mode) -> (() -> Void)? {
        guard case .edit(let note) = mode, let id = note.id else { return nil }
        return {
            do {
                try playerRepo.deleteNote(id: id)
                notes.removeAll { $0.id == id }
            } catch {
                print("[OpponentDetailView] delete note failed: \(error)")
            }
        }
    }

    private func loadSituational() async {
        isLoading = true
        defer { isLoading = false }
        do {
            situational = try StatsRepository().fetchSituationalStats(
                playerName: opponent.playerName,
                filters: filters
            )
        } catch {
            print("[OpponentDetailView] failed to load situational stats: \(error)")
            situational = nil
        }
    }
}
