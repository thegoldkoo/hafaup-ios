//
//  HafaUpWidgetBundle.swift
//  HafaUpWidget extension target only
//
//  v24: Entry point for the widget extension. Registers all widgets including
//  the Live Activity. iOS 16.1+ required for ActivityKit.
//

import WidgetKit
import SwiftUI

@main
struct HafaUpWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            ShipmentLiveActivityWidget()
        }
    }
}
