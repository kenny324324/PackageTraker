//
//  PackageWidgetIntent.swift
//  PackageTrakerWidget
//
//  WidgetConfigurationIntent for selecting which package to display
//

import AppIntents
import WidgetKit

struct PackageWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.config.selectPackage"
    static var description: IntentDescription = IntentDescription("widget.config.description")

    @Parameter(title: LocalizedStringResource("widget.config.package"))
    var selectedPackage: PackageAppEntity?
}
