import Foundation

enum CompanionConstants {
  static let group = "group.app.qiyou.qiyou"
  static let kind = "QiyouAllGames"
  static let file = "qiyou-widget-v1.json"
  static let notificationPrefix = "qiyou.energy."
}

enum WidgetGame: String, Codable, CaseIterable {
  case genshin, starRail, zenless, wutheringWaves, punishingGrayRaven
  case nevernessToEverness, towerOfFantasy
  var title: String {
    switch self {
    case .genshin: return "原神"
    case .starRail: return "星穹铁道"
    case .zenless: return "绝区零"
    case .wutheringWaves: return "鸣潮"
    case .punishingGrayRaven: return "战双"
    case .nevernessToEverness: return "异环"
    case .towerOfFantasy: return "幻塔"
    }
  }
}

enum WidgetSign: String, Codable { case signed, pending, partial, unknown, attention }

struct WidgetGameState: Codable, Equatable, Identifiable {
  let game: WidgetGame
  let roleCount: Int
  let signedRoles: Int
  let sign: WidgetSign
  let energy: Int?
  let capacity: Int?
  let syncedAt: Int64?
  let fullAt: Int64?
  var id: String { game.rawValue }
  func isFresh(at date: Date) -> Bool {
    guard let syncedAt = syncedAt, energy != nil, capacity != nil else { return false }
    let age = date.timeIntervalSince1970 - Double(syncedAt) / 1000
    return age >= -300 && age < 6 * 3600
  }
  var fullDate: Date? { fullAt.map { Date(timeIntervalSince1970: Double($0) / 1000) } }
}

struct WidgetSnapshot: Codable, Equatable {
  let version: Int
  let updatedAt: Int64
  let signDay: String
  let connected: Bool
  let games: [WidgetGameState]
  static let empty = WidgetSnapshot(version: 1, updatedAt: 0, signDay: "", connected: false, games: [])
  static func chinaDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
  func sign(for game: WidgetGameState, at date: Date) -> WidgetSign {
    signDay == Self.chinaDay(date) ? game.sign : .unknown
  }
  static func decode(_ data: Data) throws -> WidgetSnapshot {
    guard data.count <= 64000 else { throw SnapshotError.invalid }
    let value = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    guard value.version == 1, value.games.count <= WidgetGame.allCases.count,
      Set(value.games.map(\.game)).count == value.games.count,
      value.updatedAt >= 0, value.updatedAt < 4102444800000,
      !value.games.contains(where: { g in
        g.roleCount < 1 || g.roleCount > 10000 || g.signedRoles < 0 ||
        g.signedRoles > g.roleCount || (g.energy ?? 0) < 0 ||
        (g.capacity != nil && (g.capacity! <= 0 || g.capacity! > 10000000)) ||
        (g.energy ?? 0) > 10000000 ||
        (g.syncedAt != nil && (g.syncedAt! < 0 || g.syncedAt! >= 4102444800000)) ||
        (g.fullAt != nil && (g.fullAt! < 0 || g.fullAt! >= 4102444800000))
      }) else { throw SnapshotError.invalid }
    return value
  }
  func timelineDates(from now: Date) -> [Date] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    var dates = [now]
    if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
      dates.append(midnight)
    }
    for game in games {
      if let full = game.fullDate, full > now { dates.append(full) }
      if let synced = game.syncedAt {
        let stale = Date(timeIntervalSince1970: Double(synced) / 1000 + 6 * 3600)
        if stale > now { dates.append(stale) }
      }
    }
    return Array(Set(dates)).sorted()
  }
}

enum SnapshotError: Error { case invalid }

struct EnergyReminder: Codable, Equatable {
  let id: String
  let game: WidgetGame
  let fullAt: Int64
  var date: Date { Date(timeIntervalSince1970: Double(fullAt) / 1000) }
  func isValid(at now: Date) -> Bool {
    id.range(of: "^qiyou\\.energy\\.[a-f0-9]{24}$", options: .regularExpression) != nil &&
      date.timeIntervalSince(now) >= 1 && date.timeIntervalSince(now) <= 7 * 86400
  }
}

struct CompanionUpdate: Decodable {
  let snapshot: WidgetSnapshot
  let remindersEnabled: Bool
  let reminders: [EnergyReminder]
  static func decode(_ data: Data) throws -> CompanionUpdate {
    guard data.count <= 64000 else { throw SnapshotError.invalid }
    let value = try JSONDecoder().decode(CompanionUpdate.self, from: data)
    _ = try WidgetSnapshot.decode(JSONEncoder().encode(value.snapshot))
    guard value.reminders.count <= 60,
      Set(value.reminders.map(\.id)).count == value.reminders.count else { throw SnapshotError.invalid }
    return value
  }
}
