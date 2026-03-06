//
//  PackageWidgetIntent.swift
//  PackageTrakerWidget
//
//  WidgetConfigurationIntent with display mode + manual package selection
//

import AppIntents
import WidgetKit

// MARK: - Display Mode

enum WidgetDisplayMode: String, AppEnum {
    case automatic
    case manual

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("widget.config.displayMode")
    )

    static var caseDisplayRepresentations: [WidgetDisplayMode: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(
            title: LocalizedStringResource("widget.config.mode.automatic")
        ),
        .manual: DisplayRepresentation(
            title: LocalizedStringResource("widget.config.mode.manual")
        )
    ]
}

// MARK: - Intent

struct PackageWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.config.selectPackage"
    static var description: IntentDescription = IntentDescription("widget.config.description")

    @Parameter(title: LocalizedStringResource("widget.config.displayMode"), default: .automatic)
    var displayMode: WidgetDisplayMode

    @Parameter(title: LocalizedStringResource("widget.config.package1"))
    var package1: PackageAppEntity?

    @Parameter(title: LocalizedStringResource("widget.config.package2"))
    var package2: PackageAppEntity?

    @Parameter(title: LocalizedStringResource("widget.config.package3"))
    var package3: PackageAppEntity?

    static var parameterSummary: some ParameterSummary {
        When(\PackageWidgetIntent.$displayMode, .equalTo, .manual) {
            Summary {
                \PackageWidgetIntent.$displayMode
                \PackageWidgetIntent.$package1
                \PackageWidgetIntent.$package2
                \PackageWidgetIntent.$package3
            }
        } otherwise: {
            Summary {
                \PackageWidgetIntent.$displayMode
            }
        }
    }
}
