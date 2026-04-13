import SwiftUI

/// Phase 4 PR2: a single playing card render. Two visual variants:
///
///   • Face-up — shows rank + suit glyph in the suit's natural colour
///     (red for ♥♦, black for ♣♠).
///   • Face-down — shows the active `TableTheme`'s card-back colour.
///
/// Sized via the `width` parameter; the height follows a 1.4:1 aspect
/// ratio so the card looks like a real playing card at any size.
struct PlayingCardView: View {
    let card: Card?
    let isFaceDown: Bool
    let width: CGFloat
    let theme: TableTheme

    init(card: Card?, isFaceDown: Bool = false, width: CGFloat = 36, theme: TableTheme = .classicGreen) {
        self.card = card
        self.isFaceDown = isFaceDown
        self.width = width
        self.theme = theme
    }

    private var height: CGFloat { width * 1.4 }
    private var cornerRadius: CGFloat { width * 0.12 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isFaceDown ? theme.cardBackColor : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.black.opacity(0.4), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 1)

            if isFaceDown {
                cardBackPattern
            } else if let card = card {
                cardFace(card: card)
            } else {
                // Placeholder: empty slot (no card dealt yet).
                Image(systemName: "questionmark")
                    .font(.system(size: width * 0.45, weight: .light))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Face-up

    private func cardFace(card: Card) -> some View {
        VStack(spacing: -2) {
            Text(card.rank.symbol)
                .font(.system(size: width * 0.55, weight: .bold, design: .rounded))
                .foregroundColor(card.suit.isRed ? .red : .black)
            Text(card.suit.glyph)
                .font(.system(size: width * 0.5, weight: .semibold))
                .foregroundColor(card.suit.isRed ? .red : .black)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.vertical, 2)
    }

    // MARK: - Face-down pattern

    private var cardBackPattern: some View {
        GeometryReader { geo in
            let lineSpacing = geo.size.width / 5
            ZStack {
                // Diagonal hatch pattern for visual interest.
                ForEach(0..<8, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1.0, height: geo.size.height * 1.6)
                        .rotationEffect(.degrees(35))
                        .offset(x: CGFloat(i) * lineSpacing - geo.size.width / 2)
                }
                RoundedRectangle(cornerRadius: cornerRadius - 1)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    .padding(2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
