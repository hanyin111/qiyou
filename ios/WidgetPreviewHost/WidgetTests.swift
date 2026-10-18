import UIKit
import XCTest
import SwiftUI
import WidgetKit
import UserNotifications
@testable import WidgetPreviewHost

class WidgetTests: XCTestCase {

  func testCalendarNotificationKeepsAbsoluteDeadline() throws {
    let date = Date().addingTimeInterval(3600)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    parts.calendar = calendar
    parts.timeZone = calendar.timeZone
    let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    let next = try XCTUnwrap(trigger.nextTriggerDate())
    XCTAssertLessThan(abs(next.timeIntervalSince(date)), 2)
  }

  @MainActor
  func testAllSevenGamesInEverySizeAndAppearance() throws {
    let resources = Bundle.main
    WidgetFonts.register(in: resources)
    XCTAssertNotNil(UIFont(name: "HarmonyOS_Sans_SC", size: 12))
    XCTAssertNotNil(UIFont(name: "HarmonyOS_Sans_SC_Bold", size: 12))
    let now = Date()
    let games = WidgetGame.allCases.enumerated().map { i, game in
      WidgetGameState(game: game, roleCount: i == 0 ? 2 : 1,
        signedRoles: i == 0 ? 1 : i % 2, sign: i == 0 ? .partial : i % 2 == 0 ? .pending : .signed,
        energy: 110 + i * 17, capacity: i == 0 ? 400 : 300,
        syncedAt: Int64(now.timeIntervalSince1970 * 1000),
        fullAt: Int64(now.addingTimeInterval(3600).timeIntervalSince1970 * 1000))
    }
    for game in games {
      XCTAssertNotNil(UIImage(named: game.game.rawValue, in: resources, compatibleWith: nil))
    }
    let snapshot = WidgetSnapshot(version: 1, updatedAt: Int64(now.timeIntervalSince1970 * 1000),
      signDay: WidgetSnapshot.chinaDay(now), connected: true, games: games)
    let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("widget-previews")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let layouts: [(String, WidgetFamily, CGSize, Int)] = [
      ("small", .systemSmall, CGSize(width: 158, height: 158), 7),
      ("small-compact", .systemSmall, CGSize(width: 141, height: 141), 7),
      ("small-selected", .systemSmall, CGSize(width: 158, height: 158), 3),
      ("medium", .systemMedium, CGSize(width: 338, height: 158), 7),
      ("large", .systemLarge, CGSize(width: 338, height: 354), 7)]
    for (name, family, size, count) in layouts {
      for dark in [false, true] {
        let selected = WidgetSnapshot(version: snapshot.version, updatedAt: snapshot.updatedAt,
          signDay: snapshot.signDay, connected: true, games: Array(games.prefix(count)))
        let view = QiyouWidgetView(entry: QiyouEntry(date: now, snapshot: selected), resources: resources, contentPadding: 0, familyOverride: family)
          .environment(\.colorScheme, dark ? .dark : .light)
          .padding(16).background(dark ? Color.black : Color.white)
          .frame(width: size.width, height: size.height).ignoresSafeArea()
        let host = UIHostingController(rootView: view)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let image: UIImage = UIGraphicsImageRenderer(size: size).image { _ in
          host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        let path = folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
        let png: Data = try XCTUnwrap(image.pngData())
        try png.write(to: path)
        let attachment: XCTAttachment = XCTAttachment(image: image)
        attachment.name = path.lastPathComponent
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
      }
    }
  }
}
