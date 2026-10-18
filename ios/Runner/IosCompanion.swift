import Flutter
import UIKit
import UserNotifications
import WidgetKit

final class IosCompanion {
  private let center = UNUserNotificationCenter.current()
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "permission": permission(result)
    case "requestPermission":
      center.getNotificationSettings { settings in
        if settings.authorizationStatus == .notDetermined {
          self.center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if error != nil { self.fail(result); return }
            self.permission(result)
          }
        } else { self.permission(result) }
      }
    case "openSettings":
      guard let url = URL(string: UIApplication.openSettingsURLString) else { result(nil); return }
      UIApplication.shared.open(url, options: [:]) { _ in result(nil) }
    case "publish":
      guard let json = call.arguments as? String, let data = json.data(using: .utf8),
        let update = try? CompanionUpdate.decode(data) else {
        result(FlutterError(code: "COMPANION_DATA", message: "小组件数据不可用", details: nil)); return
      }
      let shared = self.store(update.snapshot)
      self.schedule(update) { success in
        DispatchQueue.main.async {
          if success { result(shared) } else { self.fail(result) }
        }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func fail(_ result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      result(FlutterError(code: "COMPANION", message: "小组件或通知暂时不可用", details: nil))
    }
  }
  private func permission(_ result: @escaping FlutterResult) {
    center.getNotificationSettings { settings in
      let status: String
      switch settings.authorizationStatus {
      case .authorized: status = "authorized"
      case .provisional: status = "provisional"
      case .denied: status = "denied"
      case .notDetermined: status = "notDetermined"
      case .ephemeral: status = "ephemeral"
      @unknown default: status = "unknown"
      }
      DispatchQueue.main.async { result(status) }
    }
  }
  private func store(_ snapshot: WidgetSnapshot) -> Bool {
    guard let directory = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: CompanionConstants.group),
      let data = try? JSONEncoder().encode(snapshot) else { return false }
    do {
      try data.write(to: directory.appendingPathComponent(CompanionConstants.file),
        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadTimelines(ofKind: CompanionConstants.kind)
      }
      return true
    } catch { return false }
  }
  private func schedule(_ update: CompanionUpdate, completion: @escaping (Bool) -> Void) {
    center.getNotificationSettings { settings in
      let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
      let reminders = update.remindersEnabled && update.snapshot.connected && allowed
        ? update.reminders.filter { $0.isValid(at: Date()) }.sorted { $0.fullAt < $1.fullAt } : []
      let wanted = Set(reminders.map(\.id))
      self.center.getPendingNotificationRequests { requests in
        let obsolete = requests.map(\.identifier).filter {
          $0.hasPrefix(CompanionConstants.notificationPrefix) && !wanted.contains($0)
        }
        self.center.removePendingNotificationRequests(withIdentifiers: obsolete)
        let group = DispatchGroup()
        let lock = NSLock()
        var success = true
        for reminder in reminders {
          let content = UNMutableNotificationContent()
          content.title = "\(reminder.game.title)体力预计已回满"
          content.body = "按最近一次同步估算；若已在游戏中消耗，请打开栖游刷新。"
          content.sound = .default
          content.threadIdentifier = "qiyou.energy"
          var calendar = Calendar(identifier: .gregorian)
          calendar.timeZone = TimeZone(secondsFromGMT: 0)!
          var date = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
          date.timeZone = calendar.timeZone
          let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
          group.enter()
          self.center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)) { error in
            if error != nil { lock.lock(); success = false; lock.unlock() }
            group.leave()
          }
        }
        group.notify(queue: .main) { completion(success) }
      }
    }
  }
}
