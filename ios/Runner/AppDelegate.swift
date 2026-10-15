import Flutter
import UIKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "QiyouDevice")!
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
