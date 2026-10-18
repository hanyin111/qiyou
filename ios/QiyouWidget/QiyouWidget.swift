import SwiftUI
import WidgetKit

struct QiyouProvider: TimelineProvider {
  init() { WidgetFonts.register(in: .main) }
  func placeholder(in context: Context) -> QiyouEntry {
    QiyouEntry(date: Date(), snapshot: .empty)
  }
  func getSnapshot(in context: Context, completion: @escaping (QiyouEntry) -> Void) {
    if context.isPreview {
      let now = Date()
      let games = WidgetGame.allCases.enumerated().map { index, game in
        WidgetGameState(game: game, roleCount: 1, signedRoles: index % 2,
          sign: index % 2 == 1 ? .signed : .pending,
          energy: 40 + index * 21, capacity: 240,
          syncedAt: Int64(now.timeIntervalSince1970 * 1000),
          fullAt: Int64(now.addingTimeInterval(3600).timeIntervalSince1970 * 1000))
      }
      completion(QiyouEntry(date: now, snapshot: WidgetSnapshot(version: 1,
        updatedAt: Int64(now.timeIntervalSince1970 * 1000), signDay: WidgetSnapshot.chinaDay(now),
        connected: true, games: games), preview: true))
    } else { completion(QiyouEntry(date: Date(), snapshot: load())) }
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<QiyouEntry>) -> Void) {
    let now = Date(), snapshot = load()
    let entries = snapshot.timelineDates(from: now).map { QiyouEntry(date: $0, snapshot: snapshot) }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
  }
  private func load() -> WidgetSnapshot {
    guard let directory = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: CompanionConstants.group),
      let data = try? Data(contentsOf: directory.appendingPathComponent(CompanionConstants.file)),
      let snapshot = try? WidgetSnapshot.decode(data) else { return .empty }
    return snapshot
  }
}

@main
struct QiyouWidget: Widget {
  var body: some WidgetConfiguration {
    if #available(iOSApplicationExtension 17.0, *) {
      configuration.contentMarginsDisabled()
    } else { configuration }
  }
  private var configuration: some WidgetConfiguration {
    StaticConfiguration(kind: CompanionConstants.kind, provider: QiyouProvider()) { entry in
      if #available(iOSApplicationExtension 17.0, *) {
        QiyouWidgetView(entry: entry)
          .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
      } else {
        QiyouWidgetView(entry: entry).background(Color(UIColor.systemBackground))
      }
    }
    .configurationDisplayName("所有游戏")
    .description("汇总体力与签到。在栖游设置中选择显示的游戏。")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
