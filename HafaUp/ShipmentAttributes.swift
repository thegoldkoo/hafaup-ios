//
//  ShipmentAttributes.swift
//  HafaUp + HafaUpWidget (shared file — must be in BOTH targets)
//
//  v24: Live Activity attributes for GuamPick package tracking.
//  Mirrors Lambda's _buildLiveActivityState() shape exactly.
//

import Foundation
import ActivityKit

@available(iOS 16.1, *)
public struct ShipmentAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        public var status: String
        public var statusLabel: String
        public var statusLabelEn: String
        public var statusEmoji: String
        public var progress: Int

        public var packageId: String
        public var blNumber: String
        public var shopifyOrderName: String

        public var productName: String
        public var productNameEn: String
        public var weightKg: Double
        public var method: String

        public var eta: String
        public var lastUpdatedIso: String

        public init(status: String, statusLabel: String, statusLabelEn: String,
                    statusEmoji: String, progress: Int, packageId: String,
                    blNumber: String, shopifyOrderName: String, productName: String,
                    productNameEn: String, weightKg: Double, method: String,
                    eta: String, lastUpdatedIso: String) {
            self.status = status
            self.statusLabel = statusLabel
            self.statusLabelEn = statusLabelEn
            self.statusEmoji = statusEmoji
            self.progress = progress
            self.packageId = packageId
            self.blNumber = blNumber
            self.shopifyOrderName = shopifyOrderName
            self.productName = productName
            self.productNameEn = productNameEn
            self.weightKg = weightKg
            self.method = method
            self.eta = eta
            self.lastUpdatedIso = lastUpdatedIso
        }
    }

    public var packageId: String
    public var gpCode: String
    public var customerName: String
    public var startedAtIso: String

    public init(packageId: String, gpCode: String, customerName: String, startedAtIso: String) {
        self.packageId = packageId
        self.gpCode = gpCode
        self.customerName = customerName
        self.startedAtIso = startedAtIso
    }
}
