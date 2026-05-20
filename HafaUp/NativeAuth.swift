import UIKit
import WebKit
import AuthenticationServices
import KakaoSDKCommon
import KakaoSDKAuth
import KakaoSDKUser
import GoogleSignIn

// 백엔드 API URL
fileprivate let HAFAUP_API_URL = "https://xct6si3lv4d5wq7c33e2ia5dle0vkvug.lambda-url.ap-southeast-2.on.aws/"

// JS bridge — WebView에 native-auth-result 이벤트 전달
func sendAuthResultToWebView(provider: String, success: Bool, token: String?, error: String?) {
    DispatchQueue.main.async {
        let payload: [String: Any] = [
            "provider": provider,
            "success": success,
            "token": token ?? "",
            "error": error ?? ""
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let escaped = json.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = "window.dispatchEvent(new CustomEvent('native-auth-result', { detail: \(json) }));"
        HafaUp.webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

// 백엔드에 third-party token 전달 → 자체 JWT 받기
func exchangeTokenForJWT(action: String, params: [String: Any], provider: String) {
    let body: [String: Any] = ["action": action, "data": params]
    guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
        sendAuthResultToWebView(provider: provider, success: false, token: nil, error: "json encode failed")
        return
    }
    guard let url = URL(string: HAFAUP_API_URL) else { return }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = httpBody
    URLSession.shared.dataTask(with: req) { data, resp, err in
        if let err = err {
            sendAuthResultToWebView(provider: provider, success: false, token: nil, error: err.localizedDescription)
            return
        }
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendAuthResultToWebView(provider: provider, success: false, token: nil, error: "invalid response")
            return
        }
        if let token = json["token"] as? String, !token.isEmpty {
            sendAuthResultToWebView(provider: provider, success: true, token: token, error: nil)
        } else {
            let errStr = (json["error"] as? String) ?? "unknown backend error"
            sendAuthResultToWebView(provider: provider, success: false, token: nil, error: errStr)
        }
    }.resume()
}

// MARK: - Kakao Login
func handleKakaoLogin() {
    let provider = "Kakao"
    let useTalk = UserApi.isKakaoTalkLoginAvailable()
    let oauthHandler: (OAuthToken?, Error?) -> Void = { token, error in
        if let error = error {
            sendAuthResultToWebView(provider: provider, success: false, token: nil, error: error.localizedDescription)
            return
        }
        guard let accessToken = token?.accessToken else {
            sendAuthResultToWebView(provider: provider, success: false, token: nil, error: "no access token")
            return
        }
        exchangeTokenForJWT(action: "auth.kakaoNative", params: ["accessToken": accessToken], provider: provider)
    }
    DispatchQueue.main.async {
        if useTalk {
            UserApi.shared.loginWithKakaoTalk(completion: oauthHandler)
        } else {
            UserApi.shared.loginWithKakaoAccount(completion: oauthHandler)
        }
    }
}

// MARK: - Google Login
func handleGoogleLogin() {
    let provider = "Google"
    DispatchQueue.main.async {
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {
            sendAuthResultToWebView(provider: provider, success: false, token: nil, error: "no root vc")
            return
        }
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error = error {
                sendAuthResultToWebView(provider: provider, success: false, token: nil, error: error.localizedDescription)
                return
            }
            guard let idToken = result?.user.idToken?.tokenString else {
                sendAuthResultToWebView(provider: provider, success: false, token: nil, error: "no id token")
                return
            }
            exchangeTokenForJWT(action: "auth.googleNative", params: ["idToken": idToken], provider: provider)
        }
    }
}

// MARK: - Apple Login
class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = AppleSignInDelegate()
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let provider = "Apple"
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            sendAuthResultToWebView(provider: provider, success: false, token: nil, error: "no identity token")
            return
        }
        var params: [String: Any] = ["identityToken": idToken, "userIdentifier": cred.user]
        if let fn = cred.fullName {
            var nameDict: [String: String] = [:]
            if let g = fn.givenName { nameDict["givenName"] = g }
            if let f = fn.familyName { nameDict["familyName"] = f }
            if !nameDict.isEmpty { params["fullName"] = nameDict }
        }
        exchangeTokenForJWT(action: "auth.appleNative", params: params, provider: provider)
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        sendAuthResultToWebView(provider: "Apple", success: false, token: nil, error: error.localizedDescription)
    }
}
func handleAppleLogin() {
    DispatchQueue.main.async {
        let req = ASAuthorizationAppleIDProvider().createRequest()
        req.requestedScopes = [.fullName, .email]
        let ctrl = ASAuthorizationController(authorizationRequests: [req])
        ctrl.delegate = AppleSignInDelegate.shared
        ctrl.presentationContextProvider = AppleSignInDelegate.shared
        ctrl.performRequests()
    }
}
