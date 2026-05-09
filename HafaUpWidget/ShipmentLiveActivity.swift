//
//  ShipmentLiveActivity.swift
//  HafaUpWidget extension target only
//
//  v24: Live Activity widget for package shipment tracking — Korean Air style.
//  Two layouts:
//    1. Lock screen / Notification Center (large card with progress + ETA)
//    2. Dynamic Island (compact alarm + expanded view)
//

import ActivityKit
import Foundation
import WidgetKit
import SwiftUI

@available(iOS 16.1, *)
struct ShipmentLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShipmentAttributes.self) { context in
            // Lock screen / Notification Center view
            LockScreenView(state: context.state, attributes: context.attributes)
                .activityBackgroundTint(Color(red: 0.043, green: 0.043, blue: 0.055))  // dark
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view (when user long-presses the alarm)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Text(context.state.statusEmoji).font(.title2)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("HafaUp").font(.caption2).foregroundColor(.secondary)
                            Text(context.state.shopifyOrderName.isEmpty ? context.state.packageId.prefix(12).description : context.state.shopifyOrderName)
                                .font(.caption).bold().lineLimit(1)
                        }
                    }.padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(context.state.statusLabel).font(.caption2).bold().foregroundColor(.orange)
                        Text("\(context.state.progress)%").font(.caption).bold()
                    }.padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 4) {
                        Text("ICN").font(.caption2).foregroundColor(.secondary)
                        ProgressTrack(progress: Double(context.state.progress) / 100.0)
                            .frame(height: 3)
                        Text("GUM").font(.caption2).foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(truncate(context.state.productName.isEmpty ? context.state.productNameEn : context.state.productName, 30))
                            .font(.caption2).foregroundColor(.white.opacity(0.8))
                        Spacer()
                        if context.state.weightKg > 0 {
                            Text(String(format: "%.1fkg", context.state.weightKg))
                                .font(.caption2).foregroundColor(.white.opacity(0.6))
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 4)
                }
            } compactLeading: {
                Text(context.state.statusEmoji)
            } compactTrailing: {
                Text("\(context.state.progress)%").font(.caption2).bold()
            } minimal: {
                Text(context.state.statusEmoji)
            }
            .keylineTint(Color.orange)
        }
    }

    private func truncate(_ s: String, _ n: Int) -> String {
        if s.count <= n { return s }
        let idx = s.index(s.startIndex, offsetBy: n)
        return String(s[..<idx]) + "…"
    }
}

// MARK: - Lock screen / Notification Center view

@available(iOS 16.1, *)
struct LockScreenView: View {
    let state: ShipmentAttributes.ContentState
    let attributes: ShipmentAttributes

    var body: some View {
        VStack(spacing: 12) {
            headerRow
            progressRow
            footerRow
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .foregroundColor(.white)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .foregroundColor(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 0) {
                Text("HafaUp").font(.caption).foregroundColor(.white.opacity(0.6)).bold()
                Text("국제 배송 추적").font(.caption2).foregroundColor(.white.opacity(0.4))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(state.statusLabel)
                    .font(.caption).bold()
                    .foregroundColor(state.progress >= 100 ? .green : .orange)
                if !state.shopifyOrderName.isEmpty {
                    Text(state.shopifyOrderName)
                        .font(.caption2).foregroundColor(.white.opacity(0.6))
                        .monospaced()
                }
            }
        }
    }

    private var progressRow: some View {
        VStack(spacing: 6) {
            HStack {
                stationLabel("ICN", "한국창고", isActive: state.progress >= 30)
                ProgressTrack(progress: Double(state.progress) / 100.0)
                    .frame(height: 4)
                stationLabel("GUM", "괌도착", isActive: state.progress >= 85, alignment: .trailing)
            }
            HStack {
                statusDot(active: state.progress >= 10, label: "주문")
                Spacer()
                statusDot(active: state.progress >= 30, label: "입고")
                Spacer()
                statusDot(active: state.progress >= 60, label: state.method == "sea" ? "해상" : "항공")
                Spacer()
                statusDot(active: state.progress >= 85, label: "도착")
                Spacer()
                statusDot(active: state.progress >= 100, label: "픽업")
            }.padding(.top, 2)
        }
    }

    private var footerRow: some View {
        HStack(spacing: 8) {
            Text(state.statusEmoji).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(productLine).font(.caption).bold().lineLimit(1)
                if !state.blNumber.isEmpty {
                    Text(state.blNumber).font(.caption2).foregroundColor(.white.opacity(0.5)).monospaced()
                }
            }
            Spacer()
            if state.weightKg > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.1f", state.weightKg)).font(.caption).bold()
                    Text("kg").font(.caption2).foregroundColor(.white.opacity(0.5))
                }
            }
        }.padding(.top, 4)
    }

    private var productLine: String {
        if !state.productName.isEmpty { return state.productName }
        if !state.productNameEn.isEmpty { return state.productNameEn }
        return state.packageId
    }

    private func stationLabel(_ code: String, _ name: String, isActive: Bool, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(code).font(.caption2).bold().foregroundColor(isActive ? .orange : .white.opacity(0.4)).monospaced()
            Text(name).font(.system(size: 8)).foregroundColor(.white.opacity(0.4))
        }
    }

    private func statusDot(active: Bool, label: String) -> some View {
        VStack(spacing: 2) {
            Circle()
                .fill(active ? Color.orange : Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
            Text(label).font(.system(size: 8)).foregroundColor(active ? .orange : .white.opacity(0.4))
        }
    }
}

// MARK: - Reusable progress bar with airplane icon

@available(iOS 16.1, *)
struct ProgressTrack: View {
    let progress: Double  // 0.0 — 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(geo.size.width, geo.size.width * progress)))
                if progress > 0 && progress < 1 {
                    Image(systemName: "airplane")
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                        .offset(x: max(0, geo.size.width * progress - 4))
                }
            }
        }
    }
}
