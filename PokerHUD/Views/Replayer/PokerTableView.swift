import SwiftUI

/// Phase 4 PR2: top-down poker table render. Draws an oval felt with
/// seats positioned around its perimeter, the running pot in the centre,
/// and any revealed community cards above the pot.
///
/// Driven by a `ReplayerStep` snapshot — the table is fully stateless
/// and re-renders entirely whenever the parent's `currentIndex` advances.
/// `withAnimation` on the parent's index update produces the smooth
/// transitions between actions.
struct PokerTableView: View {
    let step: ReplayerStep
    let bundle: HandDetailBundle
    let theme: TableTheme

    /// Default size — picked so 9 seats stay readable. The view honours
    /// any frame the parent gives it, but seat sizing is computed off
    /// the actual GeometryReader so the table scales gracefully.
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Outer rail
                RoundedRectangle(cornerRadius: geo.size.height * 0.5)
                    .fill(theme.railColor)
                    .padding(8)

                // Inner felt
                RoundedRectangle(cornerRadius: geo.size.height * 0.45)
                    .fill(theme.feltColor)
                    .padding(28)
                    .overlay(
                        RoundedRectangle(cornerRadius: geo.size.height * 0.45)
                            .stroke(Color.black.opacity(0.25), lineWidth: 1)
                            .padding(28)
                    )

                // Centre: pot + community cards
                centrePanel(in: geo.size)

                // Seats positioned around the oval
                ForEach(Array(bundle.handPlayers.enumerated()), id: \.element.playerId) { index, hp in
                    seatView(handPlayer: hp, geo: geo)
                        .position(seatPosition(
                            index: index,
                            total: bundle.handPlayers.count,
                            in: geo.size
                        ))
                }
            }
        }
    }

    // MARK: - Centre panel

    private func centrePanel(in size: CGSize) -> some View {
        let cardWidth = min(size.width / 12, 52)
        return VStack(spacing: 10) {
            // Community cards row — always 5 slots so the layout doesn't
            // jitter when cards arrive.
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { i in
                    if i < step.revealedBoard.count {
                        PlayingCardView(
                            card: step.revealedBoard[i],
                            isFaceDown: false,
                            width: cardWidth,
                            theme: theme
                        )
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        // Empty slot placeholder
                        RoundedRectangle(cornerRadius: cardWidth * 0.12)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            .frame(width: cardWidth, height: cardWidth * 1.4)
                    }
                }
            }

            // Pot pill
            HStack(spacing: 6) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.caption2)
                    .foregroundColor(theme.accentColor)
                Text(String(format: "Pot %.2f", step.pot))
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(theme.labelColor)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.black.opacity(0.45))
            )
        }
        .position(x: size.width / 2, y: size.height / 2)
    }

    // MARK: - Seat

    private func seatView(handPlayer hp: HandPlayer, geo: GeometryProxy) -> some View {
        let isFolded = step.foldedPlayers.contains(hp.playerId)
        let isActive = step.activePlayerId == hp.playerId
        let stack = step.stacks[hp.playerId] ?? hp.startingStack
        let bet = step.bets[hp.playerId] ?? 0
        let player = bundle.playersById[hp.playerId]

        // Show villain hole cards face-down except at showdown / when
        // PokerStars actually exposed them in the hand history.
        let showCards: Bool = {
            if hp.isHero { return true }
            if !hp.cards.isEmpty {
                if case .showdown = step.kind { return true }
            }
            return false
        }()

        let parsedHole = Card.parseList(hp.holeCards ?? "")
        let cardWidth: CGFloat = 28

        return VStack(spacing: 4) {
            // Hole cards above the seat plate.
            HStack(spacing: 3) {
                if hp.holeCards == nil || hp.holeCards?.isEmpty == true {
                    PlayingCardView(card: nil, isFaceDown: true, width: cardWidth, theme: theme)
                    PlayingCardView(card: nil, isFaceDown: true, width: cardWidth, theme: theme)
                } else if showCards {
                    ForEach(parsedHole) { card in
                        PlayingCardView(card: card, isFaceDown: false, width: cardWidth, theme: theme)
                    }
                } else {
                    PlayingCardView(card: nil, isFaceDown: true, width: cardWidth, theme: theme)
                    PlayingCardView(card: nil, isFaceDown: true, width: cardWidth, theme: theme)
                }
            }
            .opacity(isFolded ? 0.35 : 1.0)

            // Name + stack plate
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    if let pos = hp.position, !pos.isEmpty {
                        Text(pos)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.85))
                            .foregroundColor(.black)
                            .cornerRadius(3)
                    }
                    Text(player?.username ?? "P\(hp.playerId)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.labelColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(String(format: "%.2f", max(0, stack)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.labelColor.opacity(0.85))
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 80)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hp.isHero ? Color.blue.opacity(0.55) : Color.black.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? theme.accentColor : Color.clear, lineWidth: 2)
            )
            .opacity(isFolded ? 0.45 : 1.0)

            // Bet chips below the seat (when something has been put in
            // for this street).
            if bet > 0 {
                Text(String(format: "%.2f", bet))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(theme.accentColor)
                    )
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Seat positioning

    /// Compute (x, y) for seat `index` of `total` evenly distributed
    /// around an oval inscribed in `size`. Seat 0 is at the bottom
    /// centre (hero's natural orientation) and indices proceed
    /// counter-clockwise so adjacent seats look adjacent on screen.
    private func seatPosition(index: Int, total: Int, in size: CGSize) -> CGPoint {
        guard total > 0 else { return CGPoint(x: size.width / 2, y: size.height / 2) }

        // Angle starts from the bottom (π / 2 in standard math, but we
        // flip the y-axis since SwiftUI's y grows downward) and walks
        // counter-clockwise.
        let startAngle = Double.pi / 2
        let angle = startAngle - (2 * Double.pi * Double(index) / Double(total))

        // Inset by ~38 px so seats sit just outside the felt edge.
        let radiusX = (size.width / 2) - 60
        let radiusY = (size.height / 2) - 50

        let x = size.width / 2 + CGFloat(cos(angle)) * radiusX
        let y = size.height / 2 - CGFloat(sin(angle)) * radiusY
        return CGPoint(x: x, y: y)
    }
}
