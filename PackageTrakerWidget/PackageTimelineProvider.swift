//
//  PackageTimelineProvider.swift
//  PackageTrakerWidget
//
//  Timeline provider for package widget data
//

import WidgetKit
import Foundation

// MARK: - Timeline Entry

struct PackageTimelineEntry: TimelineEntry {
    let date: Date
    let packages: [WidgetPackageItem]
    let isPro: Bool

    /// 預覽用範例資料
    static var preview: PackageTimelineEntry {
        PackageTimelineEntry(
            date: .now,
            packages: [
                WidgetPackageItem(
                    id: UUID().uuidString,
                    trackingNumber: "TW259426993523H",
                    carrierName: "蝦皮店到店",
                    carrierIcon: "shippingbox",
                    customName: "藍牙耳機",
                    statusName: "已到貨",
                    statusColor: .green,
                    latestDescription: "已到達 全家 台北信義店",
                    pickupLocation: "全家 台北信義店",
                    updatedAt: Date()
                ),
                WidgetPackageItem(
                    id: UUID().uuidString,
                    trackingNumber: "SF1234567890123",
                    carrierName: "順豐速運",
                    carrierIcon: "shippingbox",
                    customName: "手機殼",
                    statusName: "運送中",
                    statusColor: .blue,
                    latestDescription: "貨件已到達 台北轉運中心",
                    pickupLocation: nil,
                    updatedAt: Date().addingTimeInterval(-3600)
                ),
                WidgetPackageItem(
                    id: UUID().uuidString,
                    trackingNumber: "T123456789",
                    carrierName: "全家店到店",
                    carrierIcon: "shippingbox",
                    customName: nil,
                    statusName: "處理中",
                    statusColor: .orange,
                    latestDescription: "賣家已出貨",
                    pickupLocation: nil,
                    updatedAt: Date().addingTimeInterval(-7200)
                ),
            ],
            isPro: true
        )
    }
}

// MARK: - Widget Package Item

/// Widget 顯示用的包裹項目
struct WidgetPackageItem: Identifiable {
    let id: String
    let trackingNumber: String
    let carrierName: String
    let carrierIcon: String
    let customName: String?
    let statusName: String
    let statusColor: WidgetStatusColor
    let latestDescription: String?
    let pickupLocation: String?
    let updatedAt: Date

    /// 顯示名稱（優先使用自訂名稱）
    var displayName: String {
        customName ?? trackingNumber
    }

    /// Deep Link URL
    var deepLinkURL: URL {
        URL(string: "packagetraker://package/\(id)")!
    }
}

/// Widget 狀態顏色（避免依賴主 App 的 Color extensions）
enum WidgetStatusColor {
    case green, blue, orange, red, gray, purple

    /// 對應 TrackingStatus rawValue
    static func from(statusRawValue: String) -> WidgetStatusColor {
        switch statusRawValue {
        case "arrived": return .green
        case "transit": return .blue
        case "pending": return .orange
        case "exception": return .red
        case "collected": return .purple
        case "delivered": return .green
        default: return .gray
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

        let items = rawData.map { data in
            WidgetPackageItem(
                id: data.id,
                trackingNumber: data.trackingNumber,
                carrierName: data.carrierDisplayName,
                carrierIcon: "shippingbox",
                customName: data.customName,
                statusName: data.statusDisplayName,
                statusColor: WidgetStatusColor.from(statusRawValue: data.statusRawValue),
                latestDescription: data.latestDescription,
                pickupLocation: data.pickupLocation ?? data.storeName,
                updatedAt: data.updatedAt
            )
        }

        return PackageTimelineEntry(
            date: .now,
            packages: items,
            isPro: isPro
        )
    }
}
