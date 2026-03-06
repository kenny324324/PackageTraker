//
//  PackageAppEntity.swift
//  PackageTrakerWidget
//
//  AppEntity for widget package selection
//

import AppIntents

struct PackageAppEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("widget.config.package")
    )
    static var defaultQuery = PackageEntityQuery()

    var id: String
    var displayName: String
    var carrierName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: "\(carrierName)"
        )
    }
}
