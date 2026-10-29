import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var notificationChannel: FlutterMethodChannel?
  private var informationChannel: FlutterMethodChannel?
  private var pendingTask: String?

  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let notifications = FlutterMethodChannel(name: "vip.ichiki.javalee.clcrm/notifications", binaryMessenger: messenger)
    notificationChannel = notifications
    notifications.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "permissionState":
        center.getNotificationSettings { settings in
          let authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
          DispatchQueue.main.async { result(authorized ? "authorized" : "disabled") }
        }
      case "requestPermission":
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
          DispatchQueue.main.async { result(granted) }
        }
      case "takePendingTask":
        let id = self.pendingTask
        self.pendingTask = nil
        result(id)
      case "clearPendingTask":
        self.pendingTask = nil
        result(nil)
      case "replaceRequests":
        guard let rows = call.arguments as? [[String: Any]], rows.count <= 60 else {
          result(FlutterError(code: "invalid_requests", message: "通知数据无效", details: nil)); return
        }
        self.replaceRequests(rows, result: result)
      case "openSettings":
        guard let url = URL(string: UIApplication.openSettingsURLString) else { result(false); return }
        UIApplication.shared.open(url, options: [:]) { result($0) }
      default: result(FlutterMethodNotImplemented)
      }
    }
    let information = FlutterMethodChannel(name: "vip.ichiki.javalee.clcrm/app_info", binaryMessenger: messenger)
    informationChannel = information
    information.setMethodCallHandler { call, result in
      if call.method == "dial" {
        guard let phone = call.arguments as? String else { result(false); return }
        let allowed = CharacterSet(charactersIn: "+0123456789*#")
        let displayAllowed = CharacterSet(charactersIn: "+0123456789*#()-（） ").union(.whitespacesAndNewlines)
        guard phone.unicodeScalars.allSatisfy({ displayAllowed.contains($0) }) else { result(false); return }
        let normalized = phone.unicodeScalars.filter { allowed.contains($0) }.map { String($0) }.joined()
        guard !normalized.isEmpty else { result(false); return }
        var components = URLComponents()
        components.scheme = "tel"
        components.path = normalized
        guard let url = components.url else { result(false); return }
        UIApplication.shared.open(url, options: [:]) { result($0) }
        return
      }
      guard call.method == "getAppInfo" else { result(FlutterMethodNotImplemented); return }
      result(["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""])
    }
  }

  private func replaceRequests(_ rows: [[String: Any]], result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      center.getPendingNotificationRequests { previous in
        let own = previous.filter { $0.identifier.hasPrefix("clcrm.task.") }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: own)
        let wanted = Set(rows.compactMap { $0["id"] as? String })
        center.getDeliveredNotifications { delivered in
          let stale = delivered.map { $0.request.identifier }.filter {
            $0.hasPrefix("clcrm.task.") && !wanted.contains($0)
          }
          center.removeDeliveredNotifications(withIdentifiers: stale)
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
          DispatchQueue.main.async { result(["scheduled": 0, "failed": 0]) }; return
        }
        let group = DispatchGroup()
        let lock = NSLock()
        var scheduled = 0
        var failed = 0
        for row in rows {
          guard let id = row["id"] as? String, id.hasPrefix("clcrm.task."),
            let taskId = row["taskId"] as? String, let timestamp = row["timestamp"] as? Double,
            timestamp.isFinite, timestamp > Date().timeIntervalSince1970 else {
            lock.lock(); failed += 1; lock.unlock(); continue
          }
          let content = UNMutableNotificationContent()
          content.title = row["title"] as? String ?? "ClCrm"
          content.body = row["body"] as? String ?? ""
          content.sound = .default
          content.userInfo = ["taskId": taskId]
          let interval = max(1, timestamp - Date().timeIntervalSince1970)
          let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
          let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
          group.enter()
          center.add(request) { error in
            lock.lock()
            if error == nil { scheduled += 1 } else { failed += 1 }
            lock.unlock()
            group.leave()
          }
        }
        group.notify(queue: .main) { result(["scheduled": scheduled, "failed": failed]) }
      }
    }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    if let taskId = response.notification.request.content.userInfo["taskId"] as? String {
      DispatchQueue.main.async {
        self.pendingTask = taskId
        self.notificationChannel?.invokeMethod("openTask", arguments: taskId)
      }
      completionHandler()
    } else {
      super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .list, .sound])
  }
}
