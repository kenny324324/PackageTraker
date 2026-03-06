//
//  PackageTrakerWidgetBundle.swift
//  PackageTrakerWidget
//

import WidgetKit
import SwiftUI

@main
struct PackageTrakerWidgetBundle: WidgetBundle {
    var body: some Widget {
        PackagePickupWidget()
        QuickAddWidget()
        PackageTrakerWidget()
    }
}
