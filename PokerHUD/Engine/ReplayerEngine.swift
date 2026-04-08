import Foundation
import Combine

/// Phase 4 PR2: pure-Swift state machine that turns a `HandDetailBundle`
/// (hand row + seats + actions) into an indexable sequence of
/// `ReplayerStep` snapshots so SwiftUI can render the visual table at any
/// point in the hand's history.
///
/// The engine reconstructs pot and per-player stack on the fly because
/// `Action.potBefore` / `Action.potAfter` are nullable in the schema and
/// the PokerStars parser doesn't populate them. Reconstruction model:
///
///   • Initial pot = small blind + big blind + (ante × seated players)
///   • Each non-fold / non-check action adds `action.amount` to the pot
///     and subtracts the same value from the acting player's stack.
///
/// This is intentionally a "best-effort" accounting — for `raise` actions
/// the parser currently captures the raise-by amount rather than the
/// raise-to total, so the running totals will undercount slightly on raised
/// streets. The engine prioritises step-through clarity for hand review
/// over exact penny-perfect accounting; the final `Hand.potTotal` (already
/// stored on the hand row) is shown alongside the running estimate so the
/// user can sanity-check at the end.
final class ReplayerEngine: ObservableObject {
    @Published var currentIndex: Int = 0

    let bundle: HandDetailBundle
    let steps: [ReplayerStep]

    init(bundle: HandDetailBundle) {
        self.bundle = bundle
        self.steps = Self.buildSteps(bundle: bundle)
    }

    // MARK: - Navigation

    var totalSteps: Int { steps.count }
    var currentStep: ReplayerStep { steps[currentIndex] }
    var canStepForward: Bool { currentIndex < totalSteps - 1 }
    var canStepBack: Bool { currentIndex > 0 }

    func stepForward() {
        guard canStepForward else { return }
        currentIndex += 1
    }

    func stepBack() {
        guard canStepBack else { return }
        currentIndex -= 1
    }

    func jumpToStart() {
        currentIndex = 0
    }

    func jumpToEnd() {
        currentIndex = max(0, totalSteps - 1)
    }

    // MARK: - Step generation

    private static func buildSteps(bundle: HandDetailBundle) -> [ReplayerStep] {
        let hand = bundle.hand
        let handPlayers = bundle.handPlayers
        let actions = bundle.actions.sorted(by: { $0.actionOrder < $1.actionOrder })
        let board = Card.parseList(hand.board ?? "")

        // Initial stacks come straight from the hand-player rows.
        var stacks: [Int64: Double] = Dictionary(
            uniqueKeysWithValues: handPlayers.map { ($0.playerId, $0.startingStack) }
        )
        var bets: [Int64: Double] = [:]
        var folded: Set<Int64> = []
        var pot: Double = 0

        // Post antes (each seated player puts in the ante).
        if hand.ante > 0 {
            for hp in handPlayers {
                stacks[hp.playerId, default: 0] -= hand.ante
                pot += hand.ante
            }
        }

        // Post small + big blind from the players sitting in those seats.
        if let sb = handPlayers.first(where: { $0.position == "SB" }) {
            stacks[sb.playerId, default: 0] -= hand.smallBlind
            bets[sb.playerId] = hand.smallBlind
            pot += hand.smallBlind
        }
        if let bb = handPlayers.first(where: { $0.position == "BB" }) {
            stacks[bb.playerId, default: 0] -= hand.bigBlind
            bets[bb.playerId] = hand.bigBlind
            pot += hand.bigBlind
        }

        var steps: [ReplayerStep] = []
        var currentStreet: String = "PREFLOP"

        // Step 0 — table state immediately after blinds + antes posted.
        steps.append(ReplayerStep(
            index: 0,
            kind: .initial,
            pot: pot,
            stacks: stacks,
            bets: bets,
            revealedBoard: [],
            activePlayerId: nil,
            foldedPlayers: folded,
            descriptor: "Hand begins"
        ))

        for action in actions {
            // Street transitions: emit a "deal" step BEFORE the first
            // action of a new street. Reset per-street bets when we cross
            // a boundary because every player's commitment resets.
            if action.street != currentStreet {
                let revealed = revealedBoard(for: action.street, board: board)
                bets = [:]
                let dealKind: ReplayerStepKind
                switch action.street {
                case "FLOP":  dealKind = .dealFlop
                case "TURN":  dealKind = .dealTurn
                case "RIVER": dealKind = .dealRiver
                default:      dealKind = .initial
                }
                steps.append(ReplayerStep(
                    index: steps.count,
                    kind: dealKind,
                    pot: pot,
                    stacks: stacks,
                    bets: bets,
                    revealedBoard: revealed,
                    activePlayerId: nil,
                    foldedPlayers: folded,
                    descriptor: dealDescriptor(for: dealKind, cards: revealed)
                ))
                currentStreet = action.street
            }

            // Apply the action's chip movement. Default to `.check`
            // (a no-op) for any unknown action type so the engine never
            // crashes on unexpected schema values.
            let type = ActionType(rawValue: action.actionType) ?? .check
            let amount = action.amount
            let revealed = revealedBoard(for: currentStreet, board: board)

            switch type {
            case .fold:
                folded.insert(action.playerId)
            case .check:
                break
            case .call, .bet, .raise, .allIn:
                // `action.amount` is the actual chip delta the player
                // committed on this action (parser-side commitment
                // tracker resolves raise-to totals and street-entry
                // deltas before emitting — see PokerStarsParser).
                stacks[action.playerId, default: 0] -= amount
                bets[action.playerId, default: 0] += amount
                pot += amount
            case .uncalledRefund:
                // PokerStars returned `amount` of an overbet back to
                // the raiser after an all-in was only partially
                // called. Reverse the chip movement: refund the
                // stack, subtract from the raiser's street bet, and
                // drop the pot accordingly.
                stacks[action.playerId, default: 0] += amount
                bets[action.playerId, default: 0] -= amount
                pot -= amount
            }

            steps.append(ReplayerStep(
                index: steps.count,
                kind: .action(action),
                pot: pot,
                stacks: stacks,
                bets: bets,
                revealedBoard: revealed,
                activePlayerId: action.playerId,
                foldedPlayers: folded,
                descriptor: actionDescriptor(action)
            ))
        }

        // Catch up any "deal" steps for streets the hand reached (board
        // cards were dealt) but which had no voluntary actions to
        // trigger a street transition inside the main loop above. This
        // fires whenever the remaining players are already all-in on
        // an earlier street and the rest of the board runs out without
        // any action — the user still wants to see the turn and river
        // cards appear in the animation, not jump straight from the
        // flop to showdown with the full board appearing out of
        // nowhere.
        //
        // Walks FLOP → TURN → RIVER in order and emits a `dealX` step
        // for each one whose board-card threshold is met and which
        // the main loop didn't already emit. Advances `currentStreet`
        // as it goes so the next iteration sees the updated state.
        let streetOrder = ["PREFLOP", "FLOP", "TURN", "RIVER"]
        let progression: [(name: String, threshold: Int, kind: ReplayerStepKind)] = [
            ("FLOP",  3, .dealFlop),
            ("TURN",  4, .dealTurn),
            ("RIVER", 5, .dealRiver)
        ]
        var currentIdx = streetOrder.firstIndex(of: currentStreet) ?? 0
        for (name, threshold, kind) in progression {
            let targetIdx = streetOrder.firstIndex(of: name) ?? 0
            guard targetIdx > currentIdx else { continue }
            // Stop as soon as the board ran out — e.g. hand ended on
            // the turn (4 cards), skip the river step.
            guard board.count >= threshold else { break }

            bets = [:]
            let revealed = Array(board.prefix(threshold))
            steps.append(ReplayerStep(
                index: steps.count,
                kind: kind,
                pot: pot,
                stacks: stacks,
                bets: bets,
                revealedBoard: revealed,
                activePlayerId: nil,
                foldedPlayers: folded,
                descriptor: dealDescriptor(for: kind, cards: revealed)
            ))
            currentStreet = name
            currentIdx = targetIdx
        }

        // If the hand reached showdown (board complete) emit a final
        // showdown step so the user can see the full board + every
        // remaining player's hole cards in one resting view.
        if board.count >= 3 {
            steps.append(ReplayerStep(
                index: steps.count,
                kind: .showdown,
                pot: pot,
                stacks: stacks,
                bets: [:],
                revealedBoard: board,
                activePlayerId: nil,
                foldedPlayers: folded,
                descriptor: "Showdown"
            ))
        }

        return steps
    }

    // MARK: - Helpers

    private static func revealedBoard(for street: String, board: [Card]) -> [Card] {
        switch street {
        case "PREFLOP": return []
        case "FLOP":    return Array(board.prefix(3))
        case "TURN":    return Array(board.prefix(4))
        case "RIVER":   return Array(board.prefix(5))
        default:        return []
        }
    }

    private static func dealDescriptor(for kind: ReplayerStepKind, cards: [Card]) -> String {
        let cardLabels = cards.map { "\($0.rank.symbol)\($0.suit.glyph)" }.joined(separator: " ")
        switch kind {
        case .dealFlop:  return "Flop dealt: \(cardLabels)"
        case .dealTurn:  return cards.last.map { "Turn: \($0.rank.symbol)\($0.suit.glyph)" } ?? "Turn dealt"
        case .dealRiver: return cards.last.map { "River: \($0.rank.symbol)\($0.suit.glyph)" } ?? "River dealt"
        default:         return ""
        }
    }

    private static func actionDescriptor(_ action: Action) -> String {
        let type = ActionType(rawValue: action.actionType) ?? .check
        switch type {
        case .fold:            return "folds"
        case .check:           return "checks"
        case .call:            return String(format: "calls %.2f", action.amount)
        case .bet:             return String(format: "bets %.2f", action.amount)
        case .raise:           return String(format: "raises %.2f", action.amount)
        case .allIn:           return String(format: "all-in %.2f", action.amount)
        case .uncalledRefund:  return String(format: "uncalled %.2f returned", action.amount)
        }
    }
}

// MARK: - Step model

/// One snapshot of the table at a single point in the replay timeline.
/// Each step is fully self-contained — the engine pre-computes every
/// snapshot in `init` so SwiftUI can render any step without re-walking
/// the action stream.
struct ReplayerStep {
    let index: Int
    let kind: ReplayerStepKind
    /// Reconstructed running pot total (see file header for the
    /// approximation model).
    let pot: Double
    /// Per-player remaining stack, keyed by `Player.id`.
    let stacks: [Int64: Double]
    /// Chips currently in front of each player on the active street
    /// (resets on every street boundary).
    let bets: [Int64: Double]
    /// Board cards visible at this step. Empty pre-flop, 3 on flop,
    /// 4 on turn, 5 on river / showdown.
    let revealedBoard: [Card]
    /// The player whose action this step represents (nil for initial /
    /// deal / showdown steps).
    let activePlayerId: Int64?
    /// Set of player ids that have folded by this point in the hand.
    let foldedPlayers: Set<Int64>
    /// Human-readable label used by the controls bar timeline.
    let descriptor: String
}

enum ReplayerStepKind {
    case initial
    case action(Action)
    case dealFlop
    case dealTurn
    case dealRiver
    case showdown

    var isAction: Bool {
        if case .action = self { return true }
        return false
    }
}
