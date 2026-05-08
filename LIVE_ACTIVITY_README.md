# Live Activity (v24) — Setup Guide

This branch (`feature/live-activity`) adds Live Activity support — Korean Air style
lock screen widget with real-time package tracking.

## Files added

### HafaUp app target
- `HafaUp/ShipmentAttributes.swift` — **shared** with widget extension. Defines
  `ShipmentAttributes` (static) and `ContentState` (mutable, pushed via APNs).
- `HafaUp/ShipmentActivityManager.swift` — manages activity lifecycle. Sends push
  token to Lambda when activity starts.
- `HafaUp/LiveActivityBridge.swift` — handles `live-activity-start` /
  `live-activity-end` messages from PWA WebView.

### HafaUpWidget extension target (NEW)
- `HafaUpWidget/HafaUpWidgetBundle.swift` — entry point.
- `HafaUpWidget/ShipmentLiveActivity.swift` — SwiftUI views for lock screen +
  Dynamic Island.
- `HafaUpWidget/Info.plist` — extension manifest with `NSSupportsLiveActivities`.

### Modified existing files
- `HafaUp/WebView.swift` — registers 2 new content controller handlers
  (`live-activity-start`, `live-activity-end`).
- `HafaUp/ViewController.swift` — dispatches new messages to bridge functions.
- `HafaUp/Info.plist` — adds `NSSupportsLiveActivities = true`.

## Manual Xcode setup (one-time, ~10 min)

### Step 1: Add Widget Extension target

1. Open `HafaUp.xcodeproj` in Xcode.
2. **File → New → Target…** → iOS tab → **Widget Extension** → Next.
3. Product Name: `HafaUpWidget` (exactly this name).
4. Bundle Identifier: `com.app.captainguam.HafaUpWidget` (auto-fills).
5. **Include Live Activity** ✅ (checkbox).
6. Language: Swift, no SwiftUI sample needed.
7. Click Finish. Xcode creates a new target with default files.

### Step 2: Replace generated files with our files

Xcode generates `HafaUpWidget.swift` etc. — **delete those** and add our files:

1. Select `HafaUpWidget` group in Xcode.
2. Right-click → **Add Files to "HafaUp"…**
3. Pick: `HafaUpWidget/HafaUpWidgetBundle.swift`,
   `HafaUpWidget/ShipmentLiveActivity.swift`.
4. **Important**: under "Targets" check **only HafaUpWidget**, NOT the main app.
5. Replace the generated `Info.plist` with ours, OR copy our keys into existing one.

### Step 3: Add ShipmentAttributes to BOTH targets

`ShipmentAttributes.swift` must be visible to both the app and the widget:

1. Click on `HafaUp/ShipmentAttributes.swift` in Project navigator.
2. Open File Inspector (right panel, first tab).
3. Under "Target Membership" check **both** `HafaUp` and `HafaUpWidget`.

### Step 4: Add other new HafaUp/ files to main target only

Repeat Add Files for `LiveActivityBridge.swift` and `ShipmentActivityManager.swift`.
Target Membership: **only** `HafaUp` (NOT widget).

### Step 5: Verify Info.plist

In `HafaUp/Info.plist`, confirm these keys (already added by this commit):
```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>NSSupportsLiveActivitiesFrequentUpdates</key>
<true/>
```

In `HafaUpWidget/Info.plist`, the same two keys should be present.

### Step 6: Test build

`Cmd+B` — should build for both schemes (HafaUp, HafaUpWidget). If you see
`Cannot find type 'ShipmentAttributes'` in widget files, re-check Step 3
(target membership).

### Step 7: Push & let Codemagic build

Once the project compiles locally, commit Xcode project changes (the
`.xcodeproj/project.pbxproj` file will have the new target) and push:

```bash
git add HafaUp.xcodeproj/project.pbxproj
git commit -m "Add Widget Extension target via Xcode UI"
git push origin feature/live-activity
```

Codemagic will build a new TestFlight build automatically.

## Backend Lambda — already deployed

- Lambda v24 (`guampick-api`) has APNs HTTP/2 client + `registerLiveActivityToken`,
  `endLiveActivity`, `triggerLiveActivityUpdate`, `listLiveActivities` actions.
- DynamoDB table `guampick-live-activities` stores tokens.
- `notifyCustomer()` automatically broadcasts Live Activity updates on status change.
- Env vars set: `APNS_TEAM_ID=GCFCJUMRPV`, `APNS_KEY_ID=CVG72QPMM8`,
  `APNS_BUNDLE_ID=com.app.captainguam`, `APNS_AUTH_KEY` (.p8 contents).

## End-to-end flow

```
1. User taps "이 패키지 추적 시작" in PWA
2. PWA: window.webkit.messageHandlers["live-activity-start"].postMessage(JSON)
3. Native: LiveActivityBridge → ShipmentActivityManager.start()
4. iOS: Activity.request() → returns push token
5. Native: POST /registerLiveActivityToken with token+packageId
6. Lambda: stores token in DynamoDB
7. ... time passes, package status changes ...
8. Lambda: notifyCustomer() detects status change → broadcastLiveActivityUpdate()
9. Lambda: POST to api.push.apple.com with apns-push-type:liveactivity
10. iOS: Live Activity widget updates on lock screen — no app launch needed
11. Status reaches "픽업완료" → Lambda sends event:end → widget dismisses
```

## What the user sees

**Lock screen:**
```
┌────────────────────────────────────────┐
│ 📦  HafaUp                  #1071     │
│     국제 배송 추적              항공중 │
│                                        │
│ ICN ━━━━━●━━━━━━━━━━━━━ GUM           │
│ 한국창고                       괌도착 │
│                                        │
│ ●─●─●─○─○                              │
│ 주문 입고 항공 도착 픽업                │
│                                        │
│ ✈️  1$ KOREA BREAD              1.2  │
│     GP-260508-0010                  kg │
└────────────────────────────────────────┘
```

**Dynamic Island (iPhone 14 Pro+):**
```
   [✈️] ━━━━━━━━━━━━━━━━━━━━━━━━ [60%]
```

## Troubleshooting

- **Activities not enabled** → Settings → HafaUp → Live Activities (toggle)
- **Token register failed** → check Network tab + Lambda logs
- **APNs 410 BadDeviceToken** → Lambda auto-marks ended; user dismissed activity
- **Wrong bundle topic** → APNs topic is `com.app.captainguam.push-type.liveactivity`
