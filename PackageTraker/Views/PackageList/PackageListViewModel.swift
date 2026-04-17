import SwiftUI
import SwiftData
import WidgetKit

/// PackageListView 的業務邏輯層
/// @Query 留在 View，packages 透過方法參數傳入
@Observable
final class PackageListViewModel {

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let refreshService: PackageRefreshService

    init(modelContext: ModelContext, refreshService: PackageRefreshService) {
        self.modelContext = modelContext
        self.refreshService = refreshService
    }

    // MARK: - Filtering

    private var thirtyDaysAgo: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }

    func filteredPackages(_ packages: [Package], hideDelivered: Bool) -> [Package] {
        packages.filter { package in
            if hideDelivered && package.status == .delivered {
                return false
            }
            if let latestEventTime = package.latestEventTimestamp {
                return latestEventTime > thirtyDaysAgo
            }
            return package.lastUpdated > thirtyDaysAgo
        }
    }

    func allRecentPackages(_ packages: [Package]) -> [Package] {
        packages.filter { package in
            if let latestEventTime = package.latestEventTimestamp {
                return latestEventTime > thirtyDaysAgo
            }
            return package.lastUpdated > thirtyDaysAgo
        }
    }

    func pendingPackages(_ packages: [Package]) -> [Package] {
        allRecentPackages(packages).filter { $0.status.isPendingPickup }
    }

    func deliveredRecentPackages(_ packages: [Package]) -> [Package] {
        allRecentPackages(packages).filter { $0.status == .delivered }
    }

    func groupedByCarrier(_ packages: [Package]) -> [String: [Package]] {
        Dictionary(grouping: packages) { $0.carrier.displayName }
    }

    // MARK: - Stat Computation

    func computeStatValue(_ type: StatType, packages: [Package]) -> StatValue {
        let calendar = Calendar.current
        let now = Date()
        let allRecent = allRecentPackages(packages)

        switch type {
        case .pendingPickup:
            return .integer(pendingPackages(packages).count)

        case .deliveredLast30Days:
            return .integer(deliveredRecentPackages(packages).count)

        case .thisMonthSpending:
            let total = packages
                .filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month) }
                .compactMap(\.amount)
                .reduce(0, +)
            return .currency(total)

        case .pendingAmount:
            let total = packages
                .filter { $0.status.isPendingPickup }
                .compactMap(\.amount)
                .reduce(0, +)
            return .currency(total)

        case .last30DaysSpending:
            let total = allRecent
                .compactMap(\.amount)
                .reduce(0, +)
            return .currency(total)

        case .thisMonthDelivered:
            let count = packages.filter {
                $0.status == .delivered &&
                calendar.isDate($0.lastUpdated, equalTo: now, toGranularity: .month)
            }.count
            return .integer(count)

        case .inTransit:
            let count = packages.filter {
                $0.status == .shipped || $0.status == .inTransit
            }.count
            return .integer(count)

        case .avgDeliveryDays:
            let deliveredWithDates = deliveredRecentPackages(packages).compactMap { pkg -> Int? in
                guard let start = pkg.orderCreatedTimestamp,
                      let end = pkg.pickupEventTimestamp ?? pkg.latestEventTimestamp,
                      let days = calendar.dateComponents([.day], from: start, to: end).day,
                      days >= 0 else { return nil }
                return days
            }
            guard !deliveredWithDates.isEmpty else { return .days(-1) }
            let avg = Double(deliveredWithDates.reduce(0, +)) / Double(deliveredWithDates.count)
            return .days(avg)

        case .spendingDelta:
            let thisMonth = packages
                .filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month) }
                .compactMap(\.amount)
                .reduce(0, +)
            let lastMonth: Double = {
                guard let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now) else { return 0 }
                return packages
                    .filter { calendar.isDate($0.createdAt, equalTo: lastMonthDate, toGranularity: .month) }
                    .compactMap(\.amount)
                    .reduce(0, +)
            }()
            return .delta(current: thisMonth, previous: lastMonth)

        case .codPendingAmount:
            let total = packages
                .filter { $0.status.isPendingPickup && $0.paymentMethod == .cod }
                .compactMap(\.amount)
                .reduce(0, +)
            return .currency(total)
        }
    }

    func packagesForStat(_ type: StatType, packages: [Package]) -> [Package] {
        let calendar = Calendar.current
        let now = Date()

        switch type {
        case .pendingPickup:
            return pendingPackages(packages)

        case .deliveredLast30Days:
            return deliveredRecentPackages(packages)

        case .thisMonthSpending:
            return packages.filter {
                calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month) && $0.amount != nil
            }

        case .pendingAmount:
            return packages.filter { $0.status.isPendingPickup && $0.amount != nil }

        case .last30DaysSpending:
            return allRecentPackages(packages).filter { $0.amount != nil }

        case .thisMonthDelivered:
            return packages.filter {
                $0.status == .delivered &&
                calendar.isDate($0.lastUpdated, equalTo: now, toGranularity: .month)
            }

        case .inTransit:
            return packages.filter { $0.status == .shipped || $0.status == .inTransit }

        case .avgDeliveryDays:
            return allRecentPackages(packages).filter {
                $0.status == .delivered && $0.orderCreatedTimestamp != nil
            }

        case .spendingDelta:
            return packages.filter {
                calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month) && $0.amount != nil
            }

        case .codPendingAmount:
            return packages.filter { $0.status.isPendingPickup && $0.paymentMethod == .cod }
        }
    }

    // MARK: - CRUD Actions

    func deletePackage(_ package: Package, allPackages: [Package]) {
        let packageId = package.id
        let remainingPackages = allPackages.filter { $0.id != package.id }
        modelContext.delete(package)
        try? modelContext.save()
        FirebaseSyncService.shared.deletePackage(packageId)
        WidgetDataService.shared.updateWidgetData(packages: remainingPackages)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func markAsDelivered(_ package: Package, allPackages: [Package]) {
        let now = Date()
        let description = String(localized: "detail.markCompleteEvent")

        package.status = .delivered
        package.lastUpdated = now
        package.latestDescription = description

        let event = TrackingEvent(
            id: TrackingEvent.deterministicId(trackingNumber: package.trackingNumber, timestamp: now, description: description),
            timestamp: now,
            status: .delivered,
            description: description
        )
        event.package = package
        package.events.append(event)

        try? modelContext.save()
        FirebaseSyncService.shared.syncPackage(package, includeStatus: true)

        WidgetDataService.shared.updateWidgetData(packages: allPackages)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Refresh Actions

    func refreshAllPackages(_ filtered: [Package]) async {
        await refreshService.refreshAll(filtered, in: modelContext)
    }

    func refreshPendingPackages(_ packages: [Package]) async {
        let pending = packages.filter { $0.status == .pending && $0.events.isEmpty }
        guard !pending.isEmpty else { return }

        print("🔄 自動刷新 \(pending.count) 個新增包裹")
        for package in pending {
            _ = await refreshService.refreshPackage(package, in: modelContext)
        }
    }
}
