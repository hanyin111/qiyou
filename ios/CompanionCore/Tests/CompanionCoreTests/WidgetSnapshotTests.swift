import XCTest
@testable import CompanionCore

final class WidgetSnapshotTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1792281600) // 2026-10-18 00:00 UTC
  func game(synced: Int64? = 1792281600000) -> WidgetGameState {
    WidgetGameState(game: .genshin, roleCount: 1, signedRoles: 1, sign: .signed,
      energy: 100, capacity: 200, syncedAt: synced, fullAt: 1792288800000)
  }
  func snapshot(_ games: [WidgetGameState]) -> WidgetSnapshot {
    WidgetSnapshot(version: 1, updatedAt: 1792281600000, signDay: "2026-10-18", connected: true, games: games)
  }
  func testRoundTripAndDuplicateRejection() throws {
    let original = snapshot([game()])
    XCTAssertEqual(try WidgetSnapshot.decode(JSONEncoder().encode(original)), original)
    XCTAssertThrowsError(try WidgetSnapshot.decode(JSONEncoder().encode(snapshot([game(), game()]))))
  }
  func testChinaMidnightDoesNotClaimYesterdaySigned() {
    let value = snapshot([game()])
    XCTAssertEqual(value.sign(for: game(), at: now), .signed)
    XCTAssertEqual(value.sign(for: game(), at: now.addingTimeInterval(16 * 3600)), .unknown)
  }
  func testStaleAndMissingValuesAreNotFresh() {
    XCTAssertTrue(game().isFresh(at: now))
    XCTAssertFalse(game().isFresh(at: now.addingTimeInterval(6 * 3600)))
    XCTAssertFalse(game(synced: nil).isFresh(at: now))
    XCTAssertFalse(game().isFresh(at: now.addingTimeInterval(-301)))
  }
  func testTimelineIncludesFullTimeStalenessAndChinaMidnight() {
    let dates = snapshot([game()]).timelineDates(from: now)
    XCTAssertEqual(dates, [now, now.addingTimeInterval(2 * 3600),
      now.addingTimeInterval(6 * 3600), now.addingTimeInterval(16 * 3600)])
  }
  func testNotificationCannotUseArbitraryIdentifiersOrPastDeadlines() {
    let id = "qiyou.energy.0123456789abcdef01234567"
    XCTAssertTrue(EnergyReminder(id: id, game: .genshin, fullAt: 1792288800000).isValid(at: now))
    XCTAssertFalse(EnergyReminder(id: "other.app", game: .genshin, fullAt: 1792288800000).isValid(at: now))
    XCTAssertFalse(EnergyReminder(id: id, game: .genshin, fullAt: 1792281600000).isValid(at: now))
    XCTAssertFalse(EnergyReminder(id: id, game: .genshin, fullAt: 1793281600000).isValid(at: now))
  }
  func testOversizedAndUnsupportedDataIsRejected() {
    XCTAssertThrowsError(try WidgetSnapshot.decode(Data(repeating: 65, count: 64001)))
    XCTAssertThrowsError(try WidgetSnapshot.decode(Data("{\"version\":9}".utf8)))
  }
}
