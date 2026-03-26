import XCTest
@testable import PokerHUD

final class PokerStarsParserTests: XCTestCase {
    var parser: PokerStarsParser!

    override func setUp() {
        super.setUp()
        parser = PokerStarsParser()
    }

    func testCanParse() {
        let validText = "PokerStars Hand #123456789: Hold'em No Limit ($0.50/$1.00 USD)"
        XCTAssertTrue(parser.canParse(validText))

        let invalidText = "888poker Hand History"
        XCTAssertFalse(parser.canParse(invalidText))
    }

    func testParseSimpleHand() throws {
        let handHistory = """
        PokerStars Hand #123456789: Hold'em No Limit ($0.50/$1.00 USD) - 2025/01/15 12:34:56 ET
        Table 'TestTable' 6-max Seat #1 is the button
        Seat 1: Player1 ($100.00 in chips)
        Seat 2: Player2 ($100.00 in chips)
        Seat 3: Hero ($100.00 in chips)
        Player2: posts small blind $0.50
        Hero: posts big blind $1.00
        *** HOLE CARDS ***
        Dealt to Hero [Ah Kd]
        Player1: folds
        Player2: raises $2.00 to $3.00
        Hero: calls $2.00
        *** FLOP *** [Ac 7s 2h]
        Player2: bets $4.00
        Hero: raises $8.00 to $12.00
        Player2: folds
        Hero collected $14.00 from pot
        *** SUMMARY ***
        Total pot $14.00 | Rake $0.50
        Board [Ac 7s 2h]
        """

        let parsedHands = try parser.parse(handHistory)

        XCTAssertEqual(parsedHands.count, 1)

        let hand = parsedHands[0]
        XCTAssertEqual(hand.hand.handId, "123456789")
        XCTAssertEqual(hand.hand.siteName, "PokerStars")
        XCTAssertEqual(hand.hand.gameType, "HOLDEM")
        XCTAssertEqual(hand.hand.limitType, "NL")
        XCTAssertEqual(hand.hand.smallBlind, 0.50)
        XCTAssertEqual(hand.hand.bigBlind, 1.00)
        XCTAssertEqual(hand.hand.tableSize, 6)

        XCTAssertEqual(hand.players.count, 3)

        // Find hero
        let hero = hand.players.first { $0.isHero }
        XCTAssertNotNil(hero)
        XCTAssertEqual(hero?.username, "Hero")
        XCTAssertEqual(hero?.holeCards, "Ah Kd")
        XCTAssertEqual(hero?.startingStack, 100.00)

        // Check actions
        XCTAssertFalse(hand.actions.isEmpty)
    }

    func testExtractHandId() {
        let line = "PokerStars Hand #987654321: Hold'em No Limit"
        // Use reflection to access private method for testing
        // In production, you'd make this testable or test through public API
    }

    func testParseGameInfo() {
        // Test various game formats
        let nlhe = "PokerStars Hand #123: Hold'em No Limit ($0.50/$1.00 USD)"
        let plo = "PokerStars Hand #123: Omaha Pot Limit ($1/$2 USD)"

        // These would test the private parseGameInfo method
        // In production code, consider making helpers testable
    }

    func testMultipleHands() throws {
        let multiHandHistory = """
        PokerStars Hand #111: Hold'em No Limit ($0.50/$1.00 USD) - 2025/01/15 12:00:00 ET
        Table 'Table1' 6-max Seat #1 is the button
        Seat 1: Player1 ($100.00 in chips)
        Seat 2: Player2 ($100.00 in chips)
        Player2: posts small blind $0.50
        Player1: posts big blind $1.00
        *** HOLE CARDS ***
        Dealt to Player1 [Ah Kd]
        Player2: folds
        Player1 collected $1.00 from pot
        *** SUMMARY ***
        Total pot $1.00 | Rake $0.00


        PokerStars Hand #222: Hold'em No Limit ($0.50/$1.00 USD) - 2025/01/15 12:05:00 ET
        Table 'Table1' 6-max Seat #2 is the button
        Seat 1: Player1 ($100.50 in chips)
        Seat 2: Player2 ($99.50 in chips)
        Player1: posts small blind $0.50
        Player2: posts big blind $1.00
        *** HOLE CARDS ***
        Dealt to Player1 [Qs Qh]
        Player1: raises $2.00 to $3.00
        Player2: folds
        Player1 collected $2.00 from pot
        *** SUMMARY ***
        Total pot $2.00 | Rake $0.00
        """

        let parsedHands = try parser.parse(multiHandHistory)
        XCTAssertEqual(parsedHands.count, 2)
        XCTAssertEqual(parsedHands[0].hand.handId, "111")
        XCTAssertEqual(parsedHands[1].hand.handId, "222")
    }
}
