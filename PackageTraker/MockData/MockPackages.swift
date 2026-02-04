import Foundation

/// Mock 資料（UI 原型測試用）
enum MockPackages {

    // MARK: - 待取件包裹（主頁顯示）

    static let samplePackages: [Package] = [
        // 媽媽驛站 - 3 個包裹
        Package(
            trackingNumber: "SF1234567890123",
            carrier: .sfExpress,
            customName: nil,
            pickupCode: "6-5-29-14",
            pickupLocation: "媽媽驛站",
            status: .arrivedAtStore,
            lastUpdated: Date().addingTimeInterval(-3600),
            latestDescription: "快件已到達 媽媽驛站-中和景安店"
        ),
        Package(
            trackingNumber: "TW268979373141Z",
            carrier: .sevenEleven,
            customName: nil,
            pickupCode: "2-4-2-17",
            pickupLocation: "媽媽驛站",
            status: .arrivedAtStore,
            lastUpdated: Date().addingTimeInterval(-7200),
            latestDescription: "包裹已到店，請於 7 天內取件"
        ),
        Package(
            trackingNumber: "HCT1234567890",
            carrier: .hct,
            customName: "PChome 滑鼠",
            pickupCode: "3-8-15-22",
            pickupLocation: "媽媽驛站",
            status: .arrivedAtStore,
            lastUpdated: Date().addingTimeInterval(-10800),
            latestDescription: "包裹已送達指定取貨點"
        ),

        // 其他驛站 - 2 個包裹
        Package(
            trackingNumber: "YT9876543210",
            carrier: .cainiao,
            customName: nil,
            pickupCode: "3-7-29-29",
            pickupLocation: "其他驛站",
            status: .arrivedAtStore,
            lastUpdated: Date().addingTimeInterval(-14400),
            latestDescription: "包裹已到達取貨點"
        ),
        Package(
            trackingNumber: "FM2024020101234",
            carrier: .familyMart,
            customName: "蝦皮手機殼",
            pickupCode: "35415",
            pickupLocation: "其他驛站",
            status: .arrivedAtStore,
            lastUpdated: Date().addingTimeInterval(-18000),
            latestDescription: "已到店 全家-景安門市"
        ),

        // 運輸中包裹
        Package(
            trackingNumber: "123456789012",
            carrier: .tcat,
            customName: "momo 藍牙耳機",
            pickupCode: nil,
            pickupLocation: "宅配到府",
            status: .inTransit,
            lastUpdated: Date().addingTimeInterval(-1800),
            latestDescription: "包裹已從台北轉運中心發出"
        ),
        Package(
            trackingNumber: "DHL1234567890",
            carrier: .dhl,
            customName: "Amazon 訂單",
            pickupCode: nil,
            pickupLocation: "宅配到府",
            status: .inTransit,
            lastUpdated: Date().addingTimeInterval(-86400),
            latestDescription: "Shipment in transit - Hong Kong"
        )
    ]

    // MARK: - 歷史記錄（已簽收）

    static let historyPackages: [Package] = [
        Package(
            trackingNumber: "TC2024010100001",
            carrier: .tcat,
            customName: "momo 冬季外套",
            status: .delivered,
            lastUpdated: Date().addingTimeInterval(-86400 * 3),
            isArchived: true,
            latestDescription: "已簽收"
        ),
        Package(
            trackingNumber: "SF9999888877776",
            carrier: .sfExpress,
            customName: "淘寶代購",
            status: .delivered,
            lastUpdated: Date().addingTimeInterval(-86400 * 5),
            isArchived: true,
            latestDescription: "快件已簽收"
        ),
        Package(
            trackingNumber: "TW123456789012A",
            carrier: .sevenEleven,
            customName: "蝦皮保護貼",
            status: .delivered,
            lastUpdated: Date().addingTimeInterval(-86400 * 7),
            isArchived: true,
            latestDescription: "已取件"
        ),
        Package(
            trackingNumber: "HCT2024010200001",
            carrier: .hct,
            customName: "PChome 書籍",
            status: .delivered,
            lastUpdated: Date().addingTimeInterval(-86400 * 14),
            isArchived: true,
            latestDescription: "已送達"
        ),
        Package(
            trackingNumber: "FDX123456789",
            carrier: .fedex,
            customName: "Apple Store 訂單",
            status: .delivered,
            lastUpdated: Date().addingTimeInterval(-86400 * 30),
            isArchived: true,
            latestDescription: "Delivered"
        )
    ]

    // MARK: - 詳情頁時間軸事件

    static let sampleEvents: [TrackingEvent] = [
        TrackingEvent(
            timestamp: Date().addingTimeInterval(-3600),
            status: .arrivedAtStore,
            description: "快件已到達 媽媽驛站-中和景安店，請憑取件碼取件",
            location: "新北市中和區"
        ),
        TrackingEvent(
            timestamp: Date().addingTimeInterval(-7200),
            status: .inTransit,
            description: "快件正在派送中",
            location: "新北市中和區"
        ),
        TrackingEvent(
            timestamp: Date().addingTimeInterval(-14400),
            status: .inTransit,
            description: "快件已到達 新北轉運中心",
            location: "新北市新莊區"
        ),
        TrackingEvent(
            timestamp: Date().addingTimeInterval(-28800),
            status: .inTransit,
            description: "快件已從 台北集散中心 發出",
            location: "台北市南港區"
        ),
        TrackingEvent(
            timestamp: Date().addingTimeInterval(-43200),
            status: .inTransit,
            description: "快件已到達 台北集散中心",
            location: "台北市南港區"
        ),
        TrackingEvent(
            timestamp: Date().addingTimeInterval(-86400),
            status: .shipped,
            description: "順豐已收取快件",
            location: "深圳市南山區"
        ),
        TrackingEvent(
            timestamp: Date().addingTimeInterval(-90000),
            status: .pending,
            description: "商家已發貨，等待攬收",
            location: nil
        )
    ]
}
