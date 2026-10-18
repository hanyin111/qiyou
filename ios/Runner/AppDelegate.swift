import Flutter
import UIKit
import Security
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let companion = IosCompanion()
  private let browserSession = BrowserCookieBridge(roots: {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }.map { $0 as UIView }
  })
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    UNUserNotificationCenter.current().delegate = self
    return launched
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
      willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if notification.request.identifier.hasPrefix(CompanionConstants.notificationPrefix) {
      if #available(iOS 14.0, *) { completionHandler([.banner, .sound]) }
      else { completionHandler([.alert, .sound]) }
    } else {
      super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "QiyouDevice")!
    let browserChannel = FlutterMethodChannel(name: "app.qiyou/browser-session", binaryMessenger: registrar.messenger())
    browserChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "readCookies" else { result(FlutterMethodNotImplemented); return }
      guard let arguments = call.arguments as? [String: Any],
            let nonce = arguments["nonce"] as? String,
            let urls = arguments["urls"] as? [String], let self = self else {
        result(FlutterError(code: "BROWSER_SESSION", message: "当前登录页面不可用", details: nil)); return
      }
      self.browserSession.read(nonce: nonce, urls: urls) { response in
        switch response {
        case .success(let cookies): result(cookies)
        case .failure: result(FlutterError(code: "BROWSER_SESSION", message: "无法读取当前官方登录会话，请等待页面加载完成后重试。", details: nil))
        }
      }
    }
    let companionChannel = FlutterMethodChannel(name: "app.qiyou/companion", binaryMessenger: registrar.messenger())
    companionChannel.setMethodCallHandler { [weak self] call, result in
      self?.companion.handle(call, result: result)
    }
    let channel = FlutterMethodChannel(name: "app.qiyou/device", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "app.qiyou.credentials",
        kSecAttrAccount as String: "accounts.v1"
      ]
      switch call.method {
      case "read":
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { result(nil) }
        else if status == errSecSuccess, let data = item as? Data,
                let value = String(data: data, encoding: .utf8) { result(value) }
        else { result(FlutterError(code: "SECURE_STORAGE", message: "本机安全存储不可用", details: nil)) }
      case "write":
        guard let value = call.arguments as? String,
              let data = value.data(using: .utf8), data.count <= 512000 else {
          result(FlutterError(code: "SECURE_STORAGE", message: "存储内容不可用", details: nil)); return
        }
        let updates: [String: Any] = [kSecValueData as String: data,
          kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
          query.merge(updates) { _, new in new }
          status = SecItemAdd(query as CFDictionary, nil)
        }
        if status == errSecSuccess { result(nil) }
        else { result(FlutterError(code: "SECURE_STORAGE", message: "本机安全存储不可用", details: nil)) }
      case "delete":
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { result(nil) }
        else { result(FlutterError(code: "SECURE_STORAGE", message: "无法移除本机账号", details: nil)) }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}
