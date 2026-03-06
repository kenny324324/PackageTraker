//
//  PackageEntityQuery.swift
//  PackageTrakerWidget
//
//  EntityQuery providing package list for widget configuration picker
//

import AppIntents

struct PackageEntityQuery: EntityQuery {

    func entities(for identifiers: [String]) async throws -> [PackageAppEntity] {
        let allPackages = WidgetDataService.readWidgetData()
        return allPackages
            .filter { identifiers.contains($0.id) }
            .map { toEntity($0) }
    }

    func suggestedEntities() async throws -> [PackageAppEntity] {
        let allPackages = WidgetDataService.readWidgetData()
        let activePackages = allPackages.filter { $0.statusRawValue != "delivered" }
        return activePackages.map { toEntity($0) }
    }

    func defaultResult() async -> PackageAppEntity? {
        nil
    }

    private func toEntity(_ data: WidgetPackageData) -> PackageAppEntity {
        PackageAppEntity(
            id: data.id,
            displayName: data.customName ?? data.trackingNumber,
            carrierName: data.carrierDisplayName
        )
    }
}
