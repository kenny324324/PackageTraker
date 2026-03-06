//
//  PackageEntityQuery.swift
//  PackageTrakerWidget
//
//  EntityQuery providing package list for widget configuration picker
//

import AppIntents

struct PackageEntityQuery: EntityQuery {

    /// 「最新加入」的虛擬 ID
    private static let latestAddedId = "__latest_added__"

    func entities(for identifiers: [String]) async throws -> [PackageAppEntity] {
        var results: [PackageAppEntity] = []

        if identifiers.contains(Self.latestAddedId) {
            results.append(Self.latestAddedEntity)
        }

        let allPackages = WidgetDataService.readWidgetData()
        results += allPackages
            .filter { identifiers.contains($0.id) }
            .map { toEntity($0) }

        return results
    }

    func suggestedEntities() async throws -> [PackageAppEntity] {
        let allPackages = WidgetDataService.readWidgetData()
        // 過濾掉已取貨的包裹
        let activePackages = allPackages.filter { $0.statusRawValue != "delivered" }
        var results: [PackageAppEntity] = [Self.latestAddedEntity]
        results += activePackages.map { toEntity($0) }
        return results
    }

    func defaultResult() async -> PackageAppEntity? {
        Self.latestAddedEntity
    }

    private static var latestAddedEntity: PackageAppEntity {
        PackageAppEntity(
            id: latestAddedId,
            displayName: String(localized: "widget.config.latestAdded"),
            carrierName: ""
        )
    }

    private func toEntity(_ data: WidgetPackageData) -> PackageAppEntity {
        PackageAppEntity(
            id: data.id,
            displayName: data.customName ?? data.trackingNumber,
            carrierName: data.carrierDisplayName
        )
    }
}
