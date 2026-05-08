//
//  ShipmentActivityManager.swift
//  HafaUp (main app target only — NOT widget extension)
//
//  v24/v25: Manages Live Activity lifecycle. Called from WebView bridge when
//  user taps "Track this package" in PWA, or when push notification triggers.
//
//  v25 fixes (post external review):
//   - P2.1: rehydrate `activities` map from `Activity<ShipmentAttributes>.activities`
//     on every operation. Otherwise an app-restart while an activity is still
//     showing leaves us with an empty in-memory map → start() creates a duplicate
//     and end() reports success but does nothing.
//

import Foundation
import ActivityKit
import UIKit

@available(iOS 16.1, *)
public final class ShipmentActivityManager {
    public static let shared = ShipmentActivityManager()
    private init() {}

    /// Lambda Function URL for guampick-api
    private let lambdaUrl = URL(string: "https://e4jtaecx44qedzzhlo3v4ayyvu0qlucp.lambda-url.ap-southeast-2.on.aws/")!

    /// Map of packageId → Activity reference (so we can update/end by package)
    private var activities: [String: Activity<ShipmentAttributes>] = [:]
    private let lock = NSLock()

    // MARK: - Rehydrate

    /// Repopulate `activities` from the system-wide list of running activities.
    /// Called at the top of every public operation so we always see activities
    /// that survived an app restart.
    private func rehydrate() {
        lock.lock(); defer { lock.unlock() }
        for activity in Activity<ShipmentAttributes>.activities {
            let pid = activity.attributes.packageId
            // Only track activities whose state is active or stale, not ended
            switch activity.activityState {
            case .active, .stale:
                if activities[pid] == nil {
                    activities[pid] = activity
                    print("[LiveActivity] rehydrated activity \(activity.id) for \(pid)")
                }
            case .ended, .dismissed:
                if activities[pid] != nil {
                    activities.removeValue(forKey: pid)
                }
            @unknown default:
                break
            }
        }
    }

    // MARK: - Public API

    /// Start (or update) a Live Activity for a shipment.
    @discardableResult
    public func start(packageId: String,
                      initialState: ShipmentAttributes.ContentState,
                      gpCode: String = "",
                      customerName: String = "") -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivity] User has disabled Live Activities for this app")
            return false
        }

        rehydrate()

        // If we already have an active activity for this package (from in-memory
        // OR rehydrated from system), update it instead of creating a duplicate.
        if let existing = current(for: packageId) {
            Task { await existing.update(using: initialState) }
            print("[LiveActivity] reused existing activity for \(packageId)")
            return true
        }

        let attributes = ShipmentAttributes(
            packageId: packageId,
            gpCode: gpCode,
            customerName: customerName,
            startedAtIso: ISO8601DateFormatter().string(from: Date())
        )

        do {
            let activity = try Activity<ShipmentAttributes>.request(
                attributes: attributes,
                contentState: initialState,
                pushType: .token
            )
            lock.lock(); activities[packageId] = activity; lock.unlock()
            print("[LiveActivity] started: \(activity.id) for package \(packageId)")

            // Watch for push token & forward to Lambda
            Task {
                for await tokenData in activity.pushTokenUpdates {
                    let token = tokenData.map { String(format: "%02x", $0) }.joined()
                    print("[LiveActivity] got push token (\(token.count) hex chars) for activity \(activity.id)")
                    await self.registerToken(activityId: activity.id,
                                             packageId: packageId,
                                             pushToken: token,
                                             gpCode: gpCode)
                }
            }

            // Watch state changes to clean up local map
            Task {
                for await state in activity.activityStateUpdates {
                    print("[LiveActivity] activity \(activity.id) state: \(state)")
                    if state == .ended || state == .dismissed || state == .stale {
                        await MainActor.run {
                            self.lock.lock()
                            self.activities.removeValue(forKey: packageId)
                            self.lock.unlock()
                        }
                    }
                }
            }

            return true
        } catch {
            print("[LiveActivity] start FAILED: \(error)")
            return false
        }
    }

    /// End Live Activity for a package. Even if our in-memory map is empty
    /// (e.g. after app restart), rehydrate first so we can find the activity.
    public func end(packageId: String, finalState: ShipmentAttributes.ContentState? = nil) {
        rehydrate()
        guard let activity = current(for: packageId) else {
            print("[LiveActivity] no active activity for \(packageId)")
            return
        }
        Task {
            let dismissalDate = Date().addingTimeInterval(4 * 3600)
            if let s = finalState {
                await activity.end(using: s, dismissalPolicy: .after(dismissalDate))
            } else {
                await activity.end(dismissalPolicy: .after(dismissalDate))
            }
            await self.notifyLambdaEnded(activityId: activity.id)
            await MainActor.run {
                self.lock.lock()
                self.activities.removeValue(forKey: packageId)
                self.lock.unlock()
            }
            print("[LiveActivity] ended \(activity.id)")
        }
    }

    /// End ALL active activities (called on app uninstall path or settings reset)
    public func endAll() {
        rehydrate()
        for (_, a) in activities {
            Task { await a.end(dismissalPolicy: .immediate) }
        }
        lock.lock(); activities.removeAll(); lock.unlock()
    }

    // MARK: - Private

    private func current(for packageId: String) -> Activity<ShipmentAttributes>? {
        lock.lock(); defer { lock.unlock() }
        if let a = activities[packageId] { return a }
        // Last-chance lookup directly from system list
        return Activity<ShipmentAttributes>.activities
            .first(where: { $0.attributes.packageId == packageId &&
                            ($0.activityState == .active || $0.activityState == .stale) })
    }

    private func registerToken(activityId: String, packageId: String, pushToken: String, gpCode: String) async {
        let body: [String: Any] = [
            "action": "registerLiveActivityToken",
            "data": [
                "activityId": activityId,
                "packageId": packageId,
                "pushToken": pushToken,
                "gpCode": gpCode,
                "deviceId": (UIDevice.current.identifierForVendor?.uuidString ?? ""),
                "appVersion": (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
            ]
        ]
        await postToLambda(body: body)
    }

    private func notifyLambdaEnded(activityId: String) async {
        let body: [String: Any] = [
            "action": "endLiveActivity",
            "data": ["activityId": activityId, "reason": "client-ended"]
        ]
        await postToLambda(body: body)
    }

    private func postToLambda(body: [String: Any]) async {
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: lambdaUrl)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let s = String(data: data, encoding: .utf8) ?? "(non-utf8)"
                print("[LiveActivity] Lambda \(http.statusCode): \(s)")
            }
        } catch {
            print("[LiveActivity] Lambda POST failed: \(error)")
        }
    }
}

// MARK: - JSON helpers used by WebView bridge

@available(iOS 16.1, *)
public extension ShipmentAttributes.ContentState {
    /// Build a ContentState from a JSON dictionary received from PWA.
    /// Tolerant to missing fields — defaults to safe values.
    static func fromDict(_ dict: [String: Any]) -> ShipmentAttributes.ContentState {
        return ShipmentAttributes.ContentState(
            status: (dict["status"] as? String) ?? "운송장등록",
            statusLabel: (dict["statusLabel"] as? String) ?? "주문 접수",
            statusLabelEn: (dict["statusLabelEn"] as? String) ?? "Order Received",
            statusEmoji: (dict["statusEmoji"] as? String) ?? "📦",
            progress: (dict["progress"] as? Int) ?? 10,
            packageId: (dict["packageId"] as? String) ?? "",
            blNumber: (dict["blNumber"] as? String) ?? "",
            shopifyOrderName: (dict["shopifyOrderName"] as? String) ?? "",
            productName: (dict["productName"] as? String) ?? "",
            productNameEn: (dict["productNameEn"] as? String) ?? "",
            weightKg: (dict["weightKg"] as? Double) ?? ((dict["weightKg"] as? Int).map(Double.init) ?? 0),
            method: (dict["method"] as? String) ?? "air",
            eta: (dict["eta"] as? String) ?? "",
            lastUpdatedIso: (dict["lastUpdatedIso"] as? String) ?? ISO8601DateFormatter().string(from: Date())
        )
    }
}
