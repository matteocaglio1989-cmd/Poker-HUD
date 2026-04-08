import SwiftUI

/// Phase 4 PR2 + PR3: modal sheet that shows everything we know about a
/// single hand. Loads the hand bundle (hand row, seats, actions, players)
/// lazily on appear and renders four sections:
///
///   1. Header — table, stakes, time, hero outcome
///   2. **Tags strip** (PR3) — chips for every `HandTag` attached to the
///      hand, with an "+ Add tag" button that opens `AddTagPopover`.
///   3. **Visual replayer** (PR2) — top-down `PokerTableView` driven by a
///      `ReplayerEngine`, with `ReplayerControlsView` step-through bar
///      and a theme picker.
///   4. Footer metrics — pot total + hero net + hero preflop flags
///
/// The toolbar carries a bookmark star (PR3) that toggles a tag with the
/// `CommonHandTag.bookmark` rawValue, and the close button.
struct HandDetailView: View {
    let handId: Int64

    @Environment(\.dismiss) private var dismiss
    @State private var bundle: HandDetailBundle?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var tags: [HandTag] = []
    @State private var showAddTagPopover = false

    private let handRepo = HandRepository()

    private var isBookmarked: Bool {
        tags.contains(where: { $0.tag == CommonHandTag.bookmark.rawValue })
    }

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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggleBookmark()
                } label: {
                    Image(systemName: isBookmarked ? "star.fill" : "star")
                        .foregroundColor(isBookmarked ? .yellow : .secondary)
                }
                .help(isBookmarked ? "Remove bookmark" : "Bookmark this hand")
                .disabled(bundle == nil)
            }
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
            } else {
                tags = (try? handRepo.fetchTags(forHandId: handId)) ?? []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Tag actions (PR3)

    private func toggleBookmark() {
        guard bundle != nil else { return }
        if let existing = tags.first(where: { $0.tag == CommonHandTag.bookmark.rawValue }),
           let id = existing.id {
            do {
                try handRepo.removeTag(id: id)
                tags.removeAll { $0.id == id }
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            do {
                var tag = HandTag(
                    id: nil,
                    handId: handId,
                    tag: CommonHandTag.bookmark.rawValue,
                    note: nil,
                    createdAt: Date()
                )
                try handRepo.addTag(&tag)
                tags.insert(tag, at: 0)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addTag(_ tagString: String) {
        let trimmed = tagString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Avoid duplicates of the exact same tag string.
        if tags.contains(where: { $0.tag.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return
        }
        do {
            var tag = HandTag(
                id: nil,
                handId: handId,
                tag: trimmed,
                note: nil,
                createdAt: Date()
            )
            try handRepo.addTag(&tag)
            tags.insert(tag, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeTag(_ tag: HandTag) {
        guard let id = tag.id else { return }
        do {
            try handRepo.removeTag(id: id)
            tags.removeAll { $0.id == id }
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
                VStack(alignment: .leading, spacing: 20) {
                    tagsStrip
                    ReplayerPanel(bundle: bundle)
                    footerMetrics(for: bundle)
                }
                .padding()
            }
        }
    }

    // MARK: - Tags strip (PR3)

    private var tagsStrip: some View {
        // Bookmark is shown via the toolbar star, not as a chip in this
        // strip — keeps the chip area for review labels.
        let chipTags = tags.filter { $0.tag != CommonHandTag.bookmark.rawValue }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Tags")
                    .font(.headline)
                Spacer()
                Button {
                    showAddTagPopover = true
                } label: {
                    Label("Add tag", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showAddTagPopover) {
                    AddTagPopover { tag in
                        addTag(tag)
                    }
                }
            }
            if chipTags.isEmpty {
                Text("No tags yet — use the star above to bookmark, or tap “Add tag”.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), spacing: 6)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(chipTags) { tag in
                        tagChip(tag)
                    }
                }
            }
        }
    }

    private func tagChip(_ tag: HandTag) -> some View {
        Button {
            removeTag(tag)
        } label: {
            HStack(spacing: 4) {
                Text(tag.tag)
                    .font(.caption)
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.accentColor.opacity(0.18))
            )
            .overlay(
                Capsule().stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
            )
            .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
        .help("Remove tag")
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

// MARK: - Replayer panel

/// The visual replayer block: top-down `PokerTableView`, the
/// `ReplayerControlsView` step-through bar, and a theme picker. Lives in a
/// dedicated sub-view so the `@StateObject ReplayerEngine` can be created
/// once per hand-load (the parent only knows the bundle after an async
/// fetch, so it can't own the engine directly).
private struct ReplayerPanel: View {
    let bundle: HandDetailBundle

    @StateObject private var engine: ReplayerEngine
    @State private var theme: TableTheme

    init(bundle: HandDetailBundle) {
        self.bundle = bundle
        _engine = StateObject(wrappedValue: ReplayerEngine(bundle: bundle))
        _theme = State(initialValue: TableThemeStorage.load())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Replayer")
                    .font(.headline)
                Spacer()
                themePicker
            }

            PokerTableView(
                step: engine.currentStep,
                bundle: bundle,
                theme: theme
            )
            .frame(height: 380)

            ReplayerControlsView(engine: engine)
        }
    }

    private var themePicker: some View {
        Menu {
            ForEach(TableTheme.allCases) { option in
                Button {
                    theme = option
                    TableThemeStorage.save(option)
                } label: {
                    HStack {
                        Text(option.displayName)
                        if option == theme {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "paintpalette")
                Text(theme.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.secondary.opacity(0.15))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
