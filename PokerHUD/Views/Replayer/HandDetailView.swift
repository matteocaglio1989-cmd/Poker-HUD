import SwiftUI

/// Phase 4 PR1: modal sheet that shows everything we know about a single
/// hand. Loads the hand bundle (hand row, seats, actions, players) lazily
/// on appear and renders five sections:
///
///   1. Header — table, stakes, time, hero outcome
///   2. Players strip — every seat with name, starting stack, hole cards,
///      hero highlighted
///   3. Board cards — flop / turn / river textual line
///   4. Action stream — street-by-street vertical list of every `Action`
///      in the hand. **This panel is the placeholder that PR2 replaces
///      with the visual top-down poker table.**
///   5. Footer metrics — pot total + hero net + hero preflop flags
///
/// The view is intentionally non-interactive (no tagging, no notes) so PR1
/// can ship as a pure read-only navigation skeleton. PR3 grafts the tag
/// chips and bookmark star into the toolbar.
struct HandDetailView: View {
    let handId: Int64

    @Environment(\.dismiss) private var dismiss
    @State private var bundle: HandDetailBundle?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let handRepo = HandRepository()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                ProgressView("Loading hand…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorState(error)
            } else if let bundle = bundle {
                content(for: bundle)
            } else {
                emptyState
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .task {
            await load()
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            bundle = try handRepo.fetchHandWithPlayersAndActions(handId: handId)
            if bundle == nil {
                errorMessage = "Hand not found in the local database."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Content

    private func content(for bundle: HandDetailBundle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(for: bundle)
                .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    playersStrip(for: bundle)
                    boardSection(for: bundle)
                    actionStream(for: bundle)
                    footerMetrics(for: bundle)
                }
                .padding()
            }
        }
    }

    // MARK: - Header

    private func header(for bundle: HandDetailBundle) -> some View {
        let hand = bundle.hand
        let hero = bundle.handPlayers.first(where: { $0.isHero })
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(hand.tableName ?? "Unknown table")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("\(hand.gameType) \(hand.limitType) · \(hand.stakes)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(hand.playedAt, format: .dateTime.weekday(.wide).day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let hero = hero {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Hero result")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%+.2f", hero.netResult))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(hero.netResult >= 0 ? .green : .red)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Players strip

    private func playersStrip(for bundle: HandDetailBundle) -> some View {
        let playersById = bundle.playersById
        return VStack(alignment: .leading, spacing: 8) {
            Text("Seats (\(bundle.handPlayers.count))")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 12)],
                spacing: 12
            ) {
                ForEach(bundle.handPlayers) { hp in
                    seatTile(handPlayer: hp, player: playersById[hp.playerId])
                }
            }
        }
    }

    private func seatTile(handPlayer hp: HandPlayer, player: Player?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Seat \(hp.seat)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let pos = hp.position, !pos.isEmpty {
                    Text(pos)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(3)
                }
                Spacer()
                if hp.isHero {
                    Text("HERO")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue)
                        .cornerRadius(3)
                }
            }
            Text(player?.username ?? "Player #\(hp.playerId)")
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(String(format: "Stack %.2f", hp.startingStack))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if !hp.cards.isEmpty {
                    Text(hp.cards.joined(separator: " "))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hp.isHero ? Color.blue.opacity(0.08) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(hp.isHero ? Color.blue.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Board

    private func boardSection(for bundle: HandDetailBundle) -> some View {
        let cards = bundle.hand.boardCards
        return VStack(alignment: .leading, spacing: 8) {
            Text("Board")
                .font(.headline)
            if cards.isEmpty {
                Text("Hand ended preflop — no board dealt.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 12) {
                    boardGroup(label: "Flop", cards: Array(cards.prefix(3)))
                    if cards.count >= 4 {
                        boardGroup(label: "Turn", cards: [cards[3]])
                    }
                    if cards.count >= 5 {
                        boardGroup(label: "River", cards: [cards[4]])
                    }
                    Spacer()
                }
            }
        }
    }

    private func boardGroup(label: String, cards: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                ForEach(cards, id: \.self) { card in
                    Text(card)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .foregroundColor(cardColor(for: card))
                }
            }
        }
    }

    private func cardColor(for card: String) -> Color {
        // Last char is the suit. h/d are red, s/c are black.
        guard let suit = card.last else { return .primary }
        switch suit {
        case "h", "d", "H", "D": return .red
        default: return .black
        }
    }

    // MARK: - Action stream

    private func actionStream(for bundle: HandDetailBundle) -> some View {
        let playersById = bundle.playersById
        let grouped = Dictionary(grouping: bundle.actions, by: { $0.street })
        return VStack(alignment: .leading, spacing: 12) {
            Text("Action stream")
                .font(.headline)
            if bundle.actions.isEmpty {
                Text("No actions recorded for this hand.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Street.allCases, id: \.self) { street in
                    if let streetActions = grouped[street.rawValue], !streetActions.isEmpty {
                        streetSection(
                            street: street,
                            actions: streetActions.sorted(by: { $0.actionOrder < $1.actionOrder }),
                            playersById: playersById
                        )
                    }
                }
            }
        }
    }

    private func streetSection(street: Street, actions: [Action], playersById: [Int64: Player]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(street.displayName.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(actions) { action in
                    HStack(spacing: 8) {
                        Text("#\(action.actionOrder)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 32, alignment: .leading)
                        Text(playersById[action.playerId]?.username ?? "Player #\(action.playerId)")
                            .font(.caption)
                            .frame(width: 140, alignment: .leading)
                            .lineLimit(1)
                        Text(actionVerb(for: action))
                            .font(.caption)
                            .foregroundColor(actionColor(for: action))
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.05))
            )
        }
    }

    private func actionVerb(for action: Action) -> String {
        let type = ActionType(rawValue: action.actionType) ?? .check
        switch type {
        case .fold:  return "folds"
        case .check: return "checks"
        case .call:  return String(format: "calls %.2f", action.amount)
        case .bet:   return String(format: "bets %.2f", action.amount)
        case .raise: return String(format: "raises to %.2f", action.amount)
        case .allIn: return String(format: "all-in %.2f", action.amount)
        }
    }

    private func actionColor(for action: Action) -> Color {
        let type = ActionType(rawValue: action.actionType) ?? .check
        if type.isAggressive { return .orange }
        if type == .fold { return .secondary }
        return .primary
    }

    // MARK: - Footer metrics

    private func footerMetrics(for bundle: HandDetailBundle) -> some View {
        let hero = bundle.handPlayers.first(where: { $0.isHero })
        return VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)
            HStack(spacing: 12) {
                metricTile(label: "Pot", value: String(format: "%.2f", bundle.hand.potTotal))
                metricTile(label: "Rake", value: String(format: "%.2f", bundle.hand.rake))
                if let hero = hero {
                    metricTile(label: "Hero net",
                               value: String(format: "%+.2f", hero.netResult),
                               valueColor: hero.netResult >= 0 ? .green : .red)
                    metricTile(label: "VPIP",  value: hero.vpip ? "Yes" : "No")
                    metricTile(label: "PFR",   value: hero.pfr ? "Yes" : "No")
                    metricTile(label: "3-Bet", value: hero.threeBet ? "Yes" : "No")
                }
            }
        }
    }

    private func metricTile(label: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(valueColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Empty / error states

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Hand not found")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Couldn't load hand")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
