import Flutter
import UIKit
import XCTest
import SwiftUI
import WidgetKit
import UserNotifications
@testable import Runner

class RunnerTests: XCTestCase {

  func testCalendarNotificationKeepsAbsoluteDeadline() throws {
    let date = Date().addingTimeInterval(3600)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    parts.timeZone = calendar.timeZone
    let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    let next = try XCTUnwrap(trigger.nextTriggerDate())
    XCTAssertLessThan(abs(next.timeIntervalSince(date)), 2)
  }

  @MainActor
  func testAllSevenGamesInEverySizeAndAppearance() throws {
    let resources = try XCTUnwrap(Bundle(url: Bundle.main.bundleURL
      .appendingPathComponent("PlugIns/QiyouWidget.appex")))
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
    let layouts: [(String, WidgetFamily, CGSize)] = [
      ("small", .systemSmall, CGSize(width: 158, height: 158)),
      ("medium", .systemMedium, CGSize(width: 338, height: 158)),
      ("large", .systemLarge, CGSize(width: 338, height: 354))]
    for (name, family, size) in layouts {
      for dark in [false, true] {
        let view = QiyouWidgetView(entry: QiyouEntry(date: now, snapshot: snapshot), resources: resources, contentPadding: 0)
          .environment(\.widgetFamily, family).environment(\.colorScheme, dark ? .dark : .light)
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
        let image = UIGraphicsImageRenderer(size: size).image { _ in
          host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        let path = folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
        try XCTUnwrap(image.pngData()).write(to: path)
        let attachment = XCTAttachment(image: image)
        attachment.name = path.lastPathComponent
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
      }
    }
  }
}
