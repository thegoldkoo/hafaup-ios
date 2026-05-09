//
//  LiveActivityBridge.swift
//  HafaUp (main app target only)
//
//  v24: WebView ↔ Native bridge for Live Activities.
//  Called from PWA via:
//    window.webkit.messageHandlers["live-activity-start"].postMessage(JSON.stringify({...}))
//    window.webkit.messageHandlers["live-activity-end"].postMessage(JSON.stringify({...}))
//

import Foundation
import ActivityKit
import WebKit

/// Handle "live-activity-start" message from PWA.
/// Expected message body (string of JSON):
/// {
///   "packageId": "GP-...",
///   "gpCode": "...",
///   "customerName": "...",
///   "state": { ContentState fields ... }
/// }
@available(iOS 16.1, *)
func handleStartLiveActivity(message: WKScriptMessage) {
    let diagnostics = liveActivityDiagnostics()
    guard diagnostics.widgetExtensionInstalled else {
        sendBridgeResult(event: "live-activity-result", result: [
            "success": false,
            "error": "HafaUpWidget.appex is missing from this app build",
            "diagnostics": diagnostics.asDictionary
        ])
        return
    }

    guard let payload = parseLiveActivityMessage(message) else {
        sendBridgeResult(event: "live-activity-result",
                         result: ["success": false, "error": "invalid payload", "diagnostics": diagnostics.asDictionary])
        return
    }
    guard let packageId = payload["packageId"] as? String, !packageId.isEmpty else {
        sendBridgeResult(event: "live-activity-result",
                         result: ["success": false, "error": "packageId required", "diagnostics": diagnostics.asDictionary])
        return
    }
    let gpCode = (payload["gpCode"] as? String) ?? ""
    let customerName = (payload["customerName"] as? String) ?? ""
    let stateDict = (payload["state"] as? [String: Any]) ?? [:]
    let state = ShipmentAttributes.ContentState.fromDict(stateDict)

    let ok = ShipmentActivityManager.shared.start(
        packageId: packageId,
        initialState: state,
        gpCode: gpCode,
        customerName: customerName
    )

    sendBridgeResult(event: "live-activity-result", result: [
        "success": ok,
        "packageId": packageId,
        "action": "start",
        "diagnostics": diagnostics.asDictionary
    ])
}

/// Handle "live-activity-end" message from PWA.
/// Body:
/// { "packageId": "GP-...", "finalState": { ... } (optional) }
@available(iOS 16.1, *)
func handleEndLiveActivity(message: WKScriptMessage) {
    guard let payload = parseLiveActivityMessage(message) else {
        sendBridgeResult(event: "live-activity-result",
                         result: ["success": false, "error": "invalid payload"])
        return
    }
    guard let packageId = payload["packageId"] as? String, !packageId.isEmpty else {
        sendBridgeResult(event: "live-activity-result",
                         result: ["success": false, "error": "packageId required"])
        return
    }
    var finalState: ShipmentAttributes.ContentState? = nil
    if let stateDict = payload["finalState"] as? [String: Any] {
        finalState = ShipmentAttributes.ContentState.fromDict(stateDict)
    }

    ShipmentActivityManager.shared.end(packageId: packageId, finalState: finalState)
    sendBridgeResult(event: "live-activity-result", result: [
        "success": true,
        "packageId": packageId,
        "action": "end"
    ])
}

// MARK: - Helpers

private func parseLiveActivityMessage(_ message: WKScriptMessage) -> [String: Any]? {
    if let dict = message.body as? [String: Any] {
        return dict
    }
    if let str = message.body as? String,
       let data = str.data(using: .utf8),
       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        return dict
    }
    return nil
}

private func sendBridgeResult(event: String, result: [String: Any]) {
    guard let json = try? JSONSerialization.data(withJSONObject: result),
          let jsonStr = String(data: json, encoding: .utf8) else { return }
    DispatchQueue.main.async {
        let js = "this.dispatchEvent(new CustomEvent('\(event)', { detail: \(jsonStr) }))"
        HafaUp.webView?.evaluateJavaScript(js) { _, err in
            if let err = err { print("[LiveActivityBridge] JS dispatch err: \(err)") }
        }
    }
}

private struct LiveActivityDiagnostics {
    let widgetExtensionInstalled: Bool
    let plugIns: [String]
    let appVersion: String
    let appBuild: String
    let activitiesEnabled: Bool?

    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "widgetExtensionInstalled": widgetExtensionInstalled,
            "plugIns": plugIns,
            "appVersion": appVersion,
            "appBuild": appBuild
        ]
        if let activitiesEnabled = activitiesEnabled {
            dict["activitiesEnabled"] = activitiesEnabled
        }
        return dict
    }
}

private func liveActivityDiagnostics() -> LiveActivityDiagnostics {
    let plugInsURL = Bundle.main.builtInPlugInsURL
    let plugIns = (try? FileManager.default.contentsOfDirectory(
        at: plugInsURL ?? Bundle.main.bundleURL,
        includingPropertiesForKeys: nil
    ))?.map { $0.lastPathComponent }.sorted() ?? []

    let info = Bundle.main.infoDictionary ?? [:]
    let activitiesEnabled: Bool?
    if #available(iOS 16.1, *) {
        activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    } else {
        activitiesEnabled = nil
    }

    return LiveActivityDiagnostics(
        widgetExtensionInstalled: plugIns.contains("HafaUpWidget.appex"),
        plugIns: plugIns,
        appVersion: (info["CFBundleShortVersionString"] as? String) ?? "",
        appBuild: (info["CFBundleVersion"] as? String) ?? "",
        activitiesEnabled: activitiesEnabled
    )
}
