extension AppDelegate : MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("Firebase registration token: \(String(describing: fcmToken))")
    let dataDict:[String: String] = ["token": fcmToken ?? ""]
    NotificationCenter.default.post(name: Notification.Name("FCMToken"), object: nil, userInfo: dataDict)
    handleFCMToken()
    
    // ✅ 추가: 브로드캐스트 수신을 위한 topic "all" 구독
    Messaging.messaging().subscribe(toTopic: "all") { error in
      if let error = error {
        print("❌ Topic 'all' 구독 실패: \(error.localizedDescription)")
      } else {
        print("✅ Topic 'all' 구독 완료 — 브로드캐스트 수신 가능")
      }
    }
  }
}
