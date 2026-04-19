import WebKit
struct Cookie {
    var name: String
    var value: String
}
let gcmMessageIDKey = "150996161475"
// URL for first launch
let rootUrl = URL(string: "https://hafaup.com/app.html")!
// allowed origin is for what we are sticking to pwa domain
// This should also appear in Info.plist
let allowedOrigins: [String] = ["hafaup.com"]
// auth origins will open in modal and show toolbar for back into the main origin.
// These should also appear in Info.plist
let authOrigins: [String] = [
    "ap-southeast-2m8nfu05hd.auth.ap-southeast-2.amazoncognito.com",
    "accounts.google.com",
    "kauth.kakao.com",
    "appleid.apple.com"
]
// allowedOrigins + authOrigins <= 10
let platformCookie = Cookie(name: "app-platform", value: "iOS App Store")
// UI options
let displayMode = "standalone"
let adaptiveUIStyle = true
let overrideStatusBar = false
let statusBarTheme = "dark"
let pullToRefresh = true
