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
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
 
        // ✅ 알림 권한 요청
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            print("🔔 알림 권한 요청 결과: granted=\(granted), error=\(String(describing: error))")
            UserDefaults.standard.set(granted, forKey: "notification_permission_granted")
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
 
        return true
    }
 
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
        print("❌ APNs 등록 실패: \(error.localizedDescription)")
        UserDefaults.standard.set("failed: \(error.localizedDescription)", forKey: "apns_status")
    }
 
    // APNs 토큰 등록 성공 — 진단용 로그 + 상태 저장
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenStr = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("📱 APNs 디바이스 토큰 등록 성공: \(tokenStr.prefix(20))...")
        UserDefaults.standard.set("registered: \(Date())", forKey: "apns_status")
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
 
        // ✅ FCM 토큰 UserDefaults 에 저장 (진단용)
        UserDefaults.standard.set(fcmToken ?? "", forKey: "gjt_fcm_token")
        UserDefaults.standard.set(Date().description, forKey: "gjt_fcm_token_at")
 
        // ✅✅ 제일 먼저 토픽 구독 — 뒤에 뭐가 터져도 이건 반드시 실행
        Messaging.messaging().subscribe(toTopic: "all") { error in
            if let error = error {
                print("❌ Topic 'all' 구독 실패: \(error.localizedDescription)")
                UserDefaults.standard.set("failed: \(error.localizedDescription)", forKey: "topic_all_status")
            } else {
                print("✅ Topic 'all' 구독 완료")
                UserDefaults.standard.set("subscribed: \(Date())", forKey: "topic_all_status")
            }
        }
 
        // 기존 핸들러 호출 (혹시 터져도 위 subscribe는 이미 실행됨)
        let dataDict:[String: String] = ["token": fcmToken ?? ""]
        NotificationCenter.default.post(name: Notification.Name("FCMToken"), object: nil, userInfo: dataDict)
        handleFCMToken()
    }
}
