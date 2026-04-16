//
//  AddPackageControl.swift
//  PackageTrakerWidget
//
//  Control Center button: tap to open Add Package flow
//

import AppIntents
import SwiftUI
import WidgetKit

struct AddPackageControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "AddPackageControl") {
            ControlWidgetButton(action: AddPackageControlIntent()) {
                Label(
                    String(localized: "control.addPackage"),
                    systemImage: "shippingbox.fill"
                )
            }
        }
        .displayName(LocalizedStringResource("control.addPackage.displayName"))
        .description(LocalizedStringResource("control.addPackage.description"))
    }
}

struct AddPackageControlIntent: AppIntent {
    static let title: LocalizedStringResource = "control.addPackage"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "packagetraker://addPackage")!))
    }
}
