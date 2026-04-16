//
//  PackageTimelineProvider.swift
//  PackageTrakerWidget
//
//  Timeline provider for package widget data
//

import WidgetKit
import AppIntents
import Foundation

// MARK: - Timeline Entry

struct PackageTimelineEntry: TimelineEntry {
    let date: Date
    let packages: [WidgetPackageItem]       // PRO：全部包裹
    let pendingPackages: [WidgetPackageItem] // Free：待取貨（arrivedAtStore）
    let recentDelivered: [WidgetPackageItem] // Free：30天內已取（delivered）
    let isPro: Bool

    // 預計算統計值（從主 App 寫入）
    let stats: WidgetStatValues?

    // Free Widget 配置
    let topStat: FreeWidgetStatType
    let bottomStat: FreeWidgetStatType

    // Lock Screen 配置
    let selectedPackage: WidgetPackageItem?  // 使用者選擇的包裹
    let selectedStat: FreeWidgetStatType     // 使用者選擇的統計

    /// 預覽用範例資料（PRO）
    static var preview: PackageTimelineEntry {
        PackageTimelineEntry(
            date: .now,
            packages: [
                WidgetPackageItem(
                    id: UUID().uuidString,
                    trackingNumber: "TW259426993523H",
                    carrierName: "蝦皮店到店",
                    carrierRawValue: "shopee",
                    customName: "藍牙耳機",
                    statusName: "已到貨",
                    statusColor: .green,
                    latestDescription: "已到達 全家 台北信義店",
                    pickupLocation: "全家 台北信義店",
                    pickupCode: "2847",
                    updatedAt: Date()
                ),
                WidgetPackageItem(
                    id: UUID().uuidString,
                    trackingNumber: "SF1234567890123",
                    carrierName: "順豐速運",
                    carrierRawValue: "sfExpress",
                    customName: "手機殼",
                    statusName: "運送中",
                    statusColor: .blue,
                    latestDescription: "貨件已到達 台北轉運中心",
                    pickupLocation: nil,
                    pickupCode: nil,
                    updatedAt: Date().addingTimeInterval(-3600)
                ),
                WidgetPackageItem(
                    id: UUID().uuidString,
                    trackingNumber: "T123456789",
                    carrierName: "全家店到店",
                    carrierRawValue: "familyMart",
                    customName: nil,
                    statusName: "處理中",
                    statusColor: .orange,
                    latestDescription: "賣家已出貨",
                    pickupLocation: nil,
                    pickupCode: nil,
                    updatedAt: Date().addingTimeInterval(-7200)
                ),
            ],
            pendingPackages: [],
            recentDelivered: [],
            isPro: true,
            stats: WidgetStatValues(
                pendingPickup: 2, deliveredLast30Days: 5,
                thisMonthSpending: 3500, pendingAmount: 1200,
                last30DaysSpending: 8000, thisMonthDelivered: 3,
                inTransit: 2, avgDeliveryDays: 2.5,
                spendingDeltaCurrent: 3500, spendingDeltaPrevious: 2800,
                codPendingAmount: 500
            ),
            topStat: .pendingPickup,
            bottomStat: .deliveredLast30Days,
            selectedPackage: nil,
            selectedStat: .pendingPickup
        )
    }

    /// 預覽用範例資料（Free）
    static var freePreview: PackageTimelineEntry {
        PackageTimelineEntry(
            date: .now,
            packages: [],
            pendingPackages: [
                WidgetPackageItem(
                    id: UUID().uuidString,
                    trackingNumber: "TW259426993523H",
                    carrierName: "蝦皮店到店",
                    carrierRawValue: "shopee",
                    customName: nil,
                    statusName: "已到貨",
                    statusColor: .green,
                    latestDescription: nil,
                    pickupLocation: nil,
                    pickupCode: "2847",
                    updatedAt: Date()
                )
            ],
            recentDelivered: [
                WidgetPackageItem(
                    id: UUID().uuidString,
                    trackingNumber: "SF1234567890123",
                    carrierName: "順豐速運",
                    carrierRawValue: "sfExpress",
                    customName: nil,
                    statusName: "已取貨",
                    statusColor: .green,
                    latestDescription: nil,
                    pickupLocation: nil,
                    pickupCode: nil,
                    updatedAt: Date().addingTimeInterval(-3600)
                )
            ],
            isPro: false,
            stats: WidgetStatValues(
                pendingPickup: 1, deliveredLast30Days: 1,
                thisMonthSpending: 500, pendingAmount: 500,
                last30DaysSpending: 1200, thisMonthDelivered: 1,
                inTransit: 1, avgDeliveryDays: 2.0,
                spendingDeltaCurrent: 500, spendingDeltaPrevious: 800,
                codPendingAmount: 0
            ),
            topStat: .pendingPickup,
            bottomStat: .deliveredLast30Days,
            selectedPackage: nil,
            selectedStat: .pendingPickup
        )
    }
}

// MARK: - Widget Package Item

/// Widget 顯示用的包裹項目
struct WidgetPackageItem: Identifiable {
    let id: String
    let trackingNumber: String
    let carrierName: String
    let carrierRawValue: String
    let customName: String?
    let statusName: String
    let statusColor: WidgetStatusColor
    let latestDescription: String?
    let pickupLocation: String?
    let pickupCode: String?
    let updatedAt: Date

    /// 顯示名稱（優先使用自訂名稱）
    var displayName: String {
        customName ?? trackingNumber
    }

    /// Deep Link URL
    var deepLinkURL: URL {
        URL(string: "packagetraker://package/\(id)")!
    }

    /// 從 WidgetPackageData 轉換
    static func from(_ data: WidgetPackageData) -> WidgetPackageItem {
        WidgetPackageItem(
            id: data.id,
            trackingNumber: data.trackingNumber,
            carrierName: data.carrierDisplayName,
            carrierRawValue: data.carrierRawValue,
            customName: data.customName,
            statusName: data.statusDisplayName,
            statusColor: WidgetStatusColor.from(statusRawValue: data.statusRawValue),
            latestDescription: data.latestDescription,
            pickupLocation: data.pickupLocation ?? data.storeName,
            pickupCode: data.pickupCode,
            updatedAt: data.updatedAt
        )
    }

    /// 物流商 Logo 圖片名稱（對應 Assets 中的圖片）
    var carrierLogoName: String? {
        switch carrierRawValue {
        case "sevenEleven":   return "SevenEleven"
        case "familyMart":    return "FamilyMart"
        case "hiLife":        return "HiLife"
        case "okMart":        return "OKMart"
        case "shopee":        return "Shopee"
        case "tcat":          return "Tcat"
        case "hct":           return "HCT"
        case "ecan":          return "Ecan"
        case "postTW":        return "PostTW"
        case "pchome":        return "PChome"
        case "momo":          return "Momo"
        case "kerry":         return "Kerry"
        case "dhl":           return "DHL"
        case "fedex":         return "FedEx"
        case "ups":           return "UPS"
        case "sfExpress":     return "SFExpress"
        case "customs":       return "Customs"
        default:              return nil
        }
    }
}

/// Widget 狀態顏色（避免依賴主 App 的 Color extensions）
enum WidgetStatusColor {
    case green, blue, orange, red, gray, purple

    /// 對應 TrackingStatus rawValue
    static func from(statusRawValue: String) -> WidgetStatusColor {
        switch statusRawValue {
        case "pending":        return .gray
        case "shipped":        return .orange
        case "inTransit":      return .blue
        case "arrivedAtStore": return .green
        case "delivered":      return .green
        case "returned":       return .red
        default:               return .gray
        }
    }
}

// MARK: - Timeline Provider

struct PackageTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> PackageTimelineEntry {
        PackageTimelineEntry.preview
    }

    func getSnapshot(in context: Context, completion: @escaping (PackageTimelineEntry) -> Void) {
        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PackageTimelineEntry>) -> Void) {
        let entry = createEntry()

        // 每 15 分鐘更新一次
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    // MARK: - Private

    private func createEntry() -> PackageTimelineEntry {
        let rawData = WidgetDataService.readWidgetData()
        let isPro = WidgetDataService.readSubscriptionTier() == .pro

        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        let recentData = rawData.filter { data in
            if let eventTime = data.latestEventTimestamp {
                return eventTime > thirtyDaysAgo
            }
            return data.updatedAt > thirtyDaysAgo
        }
        let pending = recentData
            .filter { $0.statusRawValue == "arrivedAtStore" }
            .map { WidgetPackageItem.from($0) }
        let delivered = recentData
            .filter { $0.statusRawValue == "delivered" }
            .map { WidgetPackageItem.from($0) }

        let proItems = isPro ? Array(rawData.prefix(5).map { WidgetPackageItem.from($0) }) : []
        let stats = WidgetDataService.readWidgetStats()

        return PackageTimelineEntry(
            date: .now,
            packages: proItems,
            pendingPackages: pending,
            recentDelivered: delivered,
            isPro: isPro,
            stats: stats,
            topStat: .pendingPickup,
            bottomStat: .deliveredLast30Days,
            selectedPackage: nil,
            selectedStat: .pendingPickup
        )
    }
}

// MARK: - Free Widget Timeline Provider (AppIntent, configurable stats)

struct FreeWidgetTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = PackageTimelineEntry
    typealias Intent = FreeWidgetIntent

    func placeholder(in context: Context) -> PackageTimelineEntry {
        PackageTimelineEntry.freePreview
    }

    func snapshot(for configuration: FreeWidgetIntent, in context: Context) async -> PackageTimelineEntry {
        createEntry(for: configuration)
    }

    func timeline(for configuration: FreeWidgetIntent, in context: Context) async -> Timeline<PackageTimelineEntry> {
        let entry = createEntry(for: configuration)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func createEntry(for configuration: FreeWidgetIntent) -> PackageTimelineEntry {
        let rawData = WidgetDataService.readWidgetData()
        let isPro = WidgetDataService.readSubscriptionTier() == .pro
        let stats = WidgetDataService.readWidgetStats()

        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        let recentData = rawData.filter { data in
            if let eventTime = data.latestEventTimestamp {
                return eventTime > thirtyDaysAgo
            }
            return data.updatedAt > thirtyDaysAgo
        }
        let pending = recentData
            .filter { $0.statusRawValue == "arrivedAtStore" }
            .map { WidgetPackageItem.from($0) }
        let delivered = recentData
            .filter { $0.statusRawValue == "delivered" }
            .map { WidgetPackageItem.from($0) }

        return PackageTimelineEntry(
            date: .now,
            packages: [],
            pendingPackages: pending,
            recentDelivered: delivered,
            isPro: isPro,
            stats: stats,
            topStat: configuration.topStat,
            bottomStat: configuration.bottomStat,
            selectedPackage: nil,
            selectedStat: .pendingPickup
        )
    }
}

// MARK: - PRO Timeline Provider (AppIntent)

struct ProPackageTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = PackageTimelineEntry
    typealias Intent = PackageWidgetIntent

    func placeholder(in context: Context) -> PackageTimelineEntry {
        PackageTimelineEntry.preview
    }

    func snapshot(for configuration: PackageWidgetIntent, in context: Context) async -> PackageTimelineEntry {
        createEntry(for: configuration)
    }

    func timeline(for configuration: PackageWidgetIntent, in context: Context) async -> Timeline<PackageTimelineEntry> {
        let entry = createEntry(for: configuration)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    // MARK: - Private

    private func createEntry(for configuration: PackageWidgetIntent) -> PackageTimelineEntry {
        let rawData = WidgetDataService.readWidgetData()
        let isPro = WidgetDataService.readSubscriptionTier() == .pro

        let proItems: [WidgetPackageItem]
        if isPro {
            if configuration.displayMode == .manual {
                // 手動選擇：依序取 package1/2/3，跳過重複
                var seenIds = Set<String>()
                let selectedIds = [configuration.package1, configuration.package2, configuration.package3]
                    .compactMap { $0?.id }
                proItems = selectedIds.compactMap { id -> WidgetPackageItem? in
                    guard seenIds.insert(id).inserted else { return nil }
                    return rawData.first(where: { $0.id == id })
                        .map { WidgetPackageItem.from($0) }
                }
            } else {
                // 依照新增順序：取最新的未取貨包裹
                let active = rawData.filter { $0.statusRawValue != "delivered" }
                proItems = active.prefix(3).map { WidgetPackageItem.from($0) }
            }
        } else {
            proItems = []
        }

        return PackageTimelineEntry(
            date: .now,
            packages: proItems,
            pendingPackages: [],
            recentDelivered: [],
            isPro: isPro,
            stats: nil,
            topStat: .pendingPickup,
            bottomStat: .deliveredLast30Days,
            selectedPackage: nil,
            selectedStat: .pendingPickup
        )
    }
}

// MARK: - Lock Screen Package Timeline Provider

struct LockScreenPackageTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = PackageTimelineEntry
    typealias Intent = LockScreenPackageIntent

    func placeholder(in context: Context) -> PackageTimelineEntry {
        PackageTimelineEntry.freePreview
    }

    func snapshot(for configuration: LockScreenPackageIntent, in context: Context) async -> PackageTimelineEntry {
        createEntry(for: configuration)
    }

    func timeline(for configuration: LockScreenPackageIntent, in context: Context) async -> Timeline<PackageTimelineEntry> {
        let entry = createEntry(for: configuration)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func createEntry(for configuration: LockScreenPackageIntent) -> PackageTimelineEntry {
        let rawData = WidgetDataService.readWidgetData()
        let isPro = WidgetDataService.readSubscriptionTier() == .pro

        // 使用者選擇的包裹，fallback 到待取件第一筆或最新包裹
        let selected: WidgetPackageItem?
        if let chosenId = configuration.package?.id,
           let match = rawData.first(where: { $0.id == chosenId }) {
            selected = WidgetPackageItem.from(match)
        } else {
            let pending = rawData.first(where: { $0.statusRawValue == "arrivedAtStore" })
            let fallback = pending ?? rawData.first
            selected = fallback.map { WidgetPackageItem.from($0) }
        }

        return PackageTimelineEntry(
            date: .now,
            packages: [],
            pendingPackages: [],
            recentDelivered: [],
            isPro: isPro,
            stats: nil,
            topStat: .pendingPickup,
            bottomStat: .deliveredLast30Days,
            selectedPackage: selected,
            selectedStat: .pendingPickup
        )
    }
}

// MARK: - Lock Screen Stats Timeline Provider

struct LockScreenStatsTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = PackageTimelineEntry
    typealias Intent = LockScreenStatsIntent

    func placeholder(in context: Context) -> PackageTimelineEntry {
        PackageTimelineEntry.freePreview
    }

    func snapshot(for configuration: LockScreenStatsIntent, in context: Context) async -> PackageTimelineEntry {
        createEntry(for: configuration)
    }

    func timeline(for configuration: LockScreenStatsIntent, in context: Context) async -> Timeline<PackageTimelineEntry> {
        let entry = createEntry(for: configuration)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func createEntry(for configuration: LockScreenStatsIntent) -> PackageTimelineEntry {
        let isPro = WidgetDataService.readSubscriptionTier() == .pro
        let stats = WidgetDataService.readWidgetStats()

        return PackageTimelineEntry(
            date: .now,
            packages: [],
            pendingPackages: [],
            recentDelivered: [],
            isPro: isPro,
            stats: stats,
            topStat: .pendingPickup,
            bottomStat: .deliveredLast30Days,
            selectedPackage: nil,
            selectedStat: configuration.stat
        )
    }
}
