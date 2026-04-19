import UIKit
import FirebaseCore
import FirebaseMessaging

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window : UIWindow?

    func application(_ application: UIApplication,
                       didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Firebase Push Notifications
        FirebaseApp.configure()
        // [START set_messaging_delegate]
        Messaging.messaging().delegate = self
        // [END set_messaging_delegate]
        UNUserNotificationCenter.current().delegate = self

        // ✅ 알림 권한 요청 — 이게 있어야 iOS가 "알림 허용?" 팝업을 띄움
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            print("🔔 알림 권한 요청 결과: granted=\(granted), error=\(String(describing: error))")
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            } else {
                print("⚠️ 사용자가 알림을 거부했습니다. 설정에서 수동으로 켜야 합니다.")
            }
        }

        return true
    }

    // [START receive_message]
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID 1: \(messageID)")
        }
        print("push userInfo 1:", userInfo)
        sendPushToWebView(userInfo: userInfo)
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID 2: \(messageID)")
        }
        print("push userInfo 2:", userInfo)
        sendPushToWebView(userInfo: userInfo)
        completionHandler(UIBackgroundFetchResult.newData)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Unable to register for remote notifications: \(error.localizedDescription)")
    }

    // APNs 토큰 등록 성공 로그 (디버깅용)
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenStr = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("📱 APNs 디바이스 토큰 등록 성공: \(tokenStr.prefix(20))...")
    }
}

extension AppDelegate : UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: 3 \(messageID)")
        }
        print("push userInfo 3:", userInfo)
        sendPushToWebView(userInfo: userInfo)
        completionHandler([[.banner, .list, .sound]])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID 4: \(messageID)")
        }
        print("push userInfo 4:", userInfo)
        sendPushClickToWebView(userInfo: userInfo)
        completionHandler()
    }
}

extension AppDelegate : MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("🔥 Firebase registration token: \(String(describing: fcmToken))")
        let dataDict:[String: String] = ["token": fcmToken ?? ""]
        NotificationCenter.default.post(name: Notification.Name("FCMToken"), object: nil, userInfo: dataDict)
        handleFCMToken()

        // ✅ 브로드캐스트 수신을 위한 topic "all" 구독
        Messaging.messaging().subscribe(toTopic: "all") { error in
            if let error = error {
                print("❌ Topic 'all' 구독 실패: \(error.localizedDescription)")
            } else {
                print("✅ Topic 'all' 구독 완료 — 브로드캐스트 수신 가능")
            }
        }
    }
}
