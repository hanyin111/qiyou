import SwiftUI
import WidgetKit
import CoreText

struct QiyouEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot
  var preview = false
}

enum WidgetFonts {
  static func register(in bundle: Bundle) {
    for name in ["HarmonyOS_Sans_SC_Regular", "HarmonyOS_Sans_SC_Bold"] {
      if let url = bundle.url(forResource: name, withExtension: "ttf") {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
      }
    }
  }
}

private func harmony(_ size: CGFloat, bold: Bool = false) -> Font {
  .custom(bold ? "HarmonyOS_Sans_SC_Bold" : "HarmonyOS_Sans_SC", fixedSize: size)
}

struct QiyouWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: QiyouEntry
  var resources: Bundle = .main
  var contentPadding: CGFloat? = nil
  private var small: Bool { family == .systemSmall }
  private var large: Bool { family == .systemLarge }
  private var relaxed: Bool { small && entry.snapshot.games.count <= 4 }
  private var columns: Int { family == .systemMedium ? 3 : 2 }
  var body: some View {
    GeometryReader { geometry in
      let compact = small && geometry.size.height < 120
      let rows = max(1, Int(ceil(Double(entry.snapshot.games.count) / Double(columns))))
      let gap: CGFloat = compact ? 3 : 4
      let cellHeight = max(16, (geometry.size.height - (compact ? 24 : small ? 34 : 36) - CGFloat(rows - 1) * gap) / CGFloat(rows))
      VStack(alignment: .leading, spacing: compact ? 2 : 4) {
        HStack(spacing: 4) {
          Text("栖游").font(harmony(compact ? 9 : small ? 11 : 13, bold: true))
          Spacer(minLength: 0)
          Text(entry.preview ? "示例" : "体力 · 签到").font(harmony(small ? 8 : 10)).foregroundColor(.secondary)
        }.frame(height: compact ? 12 : 16)
        if entry.snapshot.games.isEmpty {
          Spacer(minLength: 0)
          Text(entry.snapshot.connected ? "在设置中选择游戏" : "打开栖游连接账号")
            .font(harmony(small ? 11 : 13)).foregroundColor(.secondary)
          Spacer(minLength: 0)
        } else {
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns),
            alignment: .leading, spacing: gap) {
            ForEach(entry.snapshot.games) { game in
              cell(game, compact: compact).frame(height: cellHeight)
            }
          }
        }
        Spacer(minLength: 0)
        HStack(spacing: 3) {
          Text("同步值").font(harmony(small ? 7 : 9))
          if let oldest = entry.snapshot.games.compactMap(\.syncedAt).min() {
            Text(Date(timeIntervalSince1970: Double(oldest) / 1000), style: .time)
              .font(harmony(small ? 7 : 9))
          }
          if entry.snapshot.games.contains(where: { !$0.isFresh(at: entry.date) }) {
            Text("· 待刷新").font(harmony(small ? 7 : 9))
          }
        }.foregroundColor(.secondary).frame(height: compact ? 8 : small ? 10 : 12)
      }
    }.padding(contentPadding ?? (small ? 9 : 12))
  }

  private func cell(_ game: WidgetGameState, compact: Bool) -> some View {
    let fresh = game.isFresh(at: entry.date)
    let sign = entry.snapshot.sign(for: game, at: entry.date)
    let icon: CGFloat = small ? relaxed ? 25 : compact ? 16 : 20 : large ? 34 : 26
    return HStack(spacing: compact ? 4 : small ? 5 : 7) {
      Image(game.game.rawValue, bundle: resources).resizable().scaledToFill()
        .frame(width: icon, height: icon)
        .clipShape(RoundedRectangle(cornerRadius: small ? 5 : 7))
        .overlay(
          Image(systemName: signSymbol(sign))
            .font(.system(size: small ? 7 : 9, weight: .bold))
            .foregroundColor(.primary).padding(1)
            .background(Circle().fill(Color(UIColor.systemBackground)))
            .offset(x: 2, y: 2)
        , alignment: .bottomTrailing)
      VStack(alignment: .leading, spacing: large ? 4 : 1) {
        if !small || relaxed {
          Text(game.game.title).font(harmony(large ? 13 : relaxed ? 9 : 10, bold: true)).lineLimit(1)
        }
        Text(fresh ? "\(game.energy ?? 0)/\(game.capacity ?? 0)" : "—")
          .font(harmony(small ? relaxed ? 12 : compact ? 9 : 10 : large ? 16 : 12, bold: true))
          .lineLimit(1).minimumScaleFactor(0.7)
        if small && game.roleCount > 1 {
          Text(sign == .unknown ? "待刷新" : "\(game.signedRoles)/\(game.roleCount) 已签").font(harmony(6)).foregroundColor(.secondary)
        }
        if large {
          Text(signLabel(sign, game: game)).font(harmony(10)).foregroundColor(.secondary)
          if fresh, let full = game.fullDate {
            if full <= entry.date {
              Text((game.energy ?? 0) >= (game.capacity ?? 1) ? "已回满" : "预计已满")
                .font(harmony(9)).foregroundColor(.secondary)
            } else {
              HStack(spacing: 2) {
                Text("回满").font(harmony(9))
                Text(full, style: .time).font(harmony(9))
              }.foregroundColor(.secondary)
            }
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(game.game.title)，\(fresh ? "体力 \(game.energy ?? 0)，上限 \(game.capacity ?? 0)" : "体力待刷新")，\(signLabel(sign, game: game))")
  }
  private func signSymbol(_ sign: WidgetSign) -> String {
    switch sign {
    case .signed: return "checkmark.circle.fill"
    case .attention: return "exclamationmark.circle"
    case .partial: return "circle.lefthalf.filled"
    case .pending: return "circle"
    case .unknown: return "questionmark.circle"
    }
  }
  private func signLabel(_ sign: WidgetSign, game: WidgetGameState) -> String {
    switch sign {
    case .signed: return "今日已签"
    case .pending: return "待签到"
    case .partial: return "\(game.signedRoles)/\(game.roleCount) 已签"
    case .attention: return "请打开栖游处理"
    case .unknown: return "签到待刷新"
    }
  }
}
