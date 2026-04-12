import SwiftUI

/// Phase 4 PR1 + PR3: top-level Hand Replayer tab. Replaces the
/// `ReplayerPlaceholderView` stub from earlier phases. Loads recent
/// hands and lets the user tap any row to open `HandDetailView` in a
/// sheet, with a PR3 filter pill across the top to switch between all
/// hands, bookmarked hands, and any-tagged hands.
struct HandReplayerView: View {
    @State private var hands: [Hand] = []
    @State private var heroResults: [Int64: Double] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedHand: HandSelection?
    @State private var handLimit = 200
    @State private var filter: HandReplayerFilter = .all

    private let handRepo = HandRepository()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
                .padding(.horizontal)
                .padding(.top)

            filterPills
                .padding(.horizontal)

            if isLoading {
                ProgressView("Loading hands…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorState(error)
            } else if hands.isEmpty {
                emptyState
            } else {
                handsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await load()
        }
        .onChange(of: filter) { _, _ in
            Task { await load() }
        }
        .sheet(item: $selectedHand) { selection in
            HandDetailView(handId: selection.handId)
                .frame(minWidth: 720, minHeight: 600)
        }
    }

    // MARK: - Filter pills (PR3)

    private var filterPills: some View {
        HStack(spacing: 8) {
            ForEach(HandReplayerFilter.allCases) { option in
                Button {
                    filter = option
                } label: {
                    HStack(spacing: 4) {
                        if let icon = option.icon {
                            Image(systemName: icon)
                                .font(.caption)
                        }
                        Text(option.label)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(filter == option ? Color.accentColor : Color.secondary.opacity(0.15))
                    )
                    .foregroundColor(filter == option ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text("Hand Replayer")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Browse and review every hand in your history")
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Hands list

    private var handsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(hands) { hand in
                    HandRow(hand: hand, heroNetResult: heroResults[hand.id ?? -1])
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let id = hand.id {
                                selectedHand = HandSelection(handId: id)
                            }
                        }
                }
                if hands.count >= handLimit {
                    Button("Load more") {
                        handLimit += 200
                        Task { await load() }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("No hands imported yet")
                .font(.headline)
            Text("Import hand histories from the Dashboard to start reviewing.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Couldn't load hands")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch filter {
            case .all:
                hands = try handRepo.fetchRecent(limit: handLimit)
            case .bookmarked:
                hands = try handRepo.fetchBookmarkedHands(limit: handLimit)
            case .tagged:
                hands = try handRepo.fetchTaggedHands(limit: handLimit)
            }
            // Batch-fetch hero P/L for every loaded hand so HandRow can
            // display it without an N+1 query per row.
            let handIds = hands.compactMap { $0.id }
            heroResults = try handRepo.fetchHeroResults(forHandIds: handIds)
        } catch {
            errorMessage = error.localizedDescription
            hands = []
            heroResults = [:]
        }
    }
}

// MARK: - Filter

/// Phase 4 PR3: filter pill options. Drives `HandRepository.fetchRecent`
/// (default), `fetchBookmarkedHands`, and `fetchTaggedHands` respectively.
enum HandReplayerFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case bookmarked
    case tagged

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:        return "All"
        case .bookmarked: return "Bookmarked"
        case .tagged:     return "Tagged"
        }
    }

    var icon: String? {
        switch self {
        case .all:        return "tray.full"
        case .bookmarked: return "star.fill"
        case .tagged:     return "tag.fill"
        }
    }
}

// MARK: - Row

private struct HandRow: View {
    let hand: Hand
    let heroNetResult: Double?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Date column
            VStack(alignment: .leading, spacing: 2) {
                Text(hand.playedAt, format: .dateTime.day().month(.abbreviated))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(hand.playedAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 90, alignment: .leading)

            // Table + game type
            VStack(alignment: .leading, spacing: 2) {
                Text(hand.tableName ?? "Unknown table")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(hand.gameType) \(hand.limitType) · \(hand.stakes)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Board summary
            if !hand.boardCards.isEmpty {
                Text(hand.boardCards.joined(separator: " "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 130, alignment: .trailing)
            }

            // Hero P/L
            VStack(alignment: .trailing, spacing: 2) {
                Text("P/L").font(.caption2).foregroundColor(.secondary)
                if let net = heroNetResult {
                    Text(String(format: "%+.2f", net))
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(net >= 0 ? .green : .red)
                } else {
                    Text("—")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 70)

            // Pot
            VStack(alignment: .trailing, spacing: 2) {
                Text("Pot").font(.caption2).foregroundColor(.secondary)
                Text(String(format: "%.2f", hand.potTotal))
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.semibold)
            }
            .frame(width: 80)

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Sheet identifier helper

/// Tiny wrapper that makes `Int64` `Identifiable` for use with
/// `.sheet(item:)`. Avoids a retroactive conformance on the global `Int64`
/// type. Shared by `HandReplayerView`, `DashboardView`, and
/// `SessionDetailView` to drive the same `HandDetailView` sheet.
struct HandSelection: Identifiable, Hashable {
    let handId: Int64
    var id: Int64 { handId }
}
