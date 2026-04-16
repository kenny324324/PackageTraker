//
//  PackageWidgetIntent.swift
//  PackageTrakerWidget
//
//  WidgetConfigurationIntent with display mode + manual package selection
//

import AppIntents
import WidgetKit

// MARK: - Free Widget Stat Type

enum FreeWidgetStatType: String, AppEnum {
    case pendingPickup          // 待取件
    case deliveredLast30Days    // 近30天已取
    case thisMonthSpending      // 本月總花費（Pro）
    case pendingAmount          // 待取包裹金額（Pro）
    case last30DaysSpending     // 近30天總花費（Pro）
    case thisMonthDelivered     // 本月已取（Pro）
    case inTransit              // 運送中（Pro）
    case avgDeliveryDays        // 平均配送天數（Pro）
    case spendingDelta          // 相較上月花費（Pro）
    case codPendingAmount       // 貨到付款待付（Pro）

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("widget.config.statType")
    )

    static var caseDisplayRepresentations: [FreeWidgetStatType: DisplayRepresentation] = [
        .pendingPickup: DisplayRepresentation(
            title: LocalizedStringResource("widget.config.stat.pendingPickup")
        ),
        .deliveredLast30Days: DisplayRepresentation(
            title: LocalizedStringResource("widget.config.stat.deliveredLast30Days")
        ),
        .thisMonthSpending: DisplayRepresentation(
            title: LocalizedStringResource("widget.config.stat.thisMonthSpending")
        ),
        .pendingAmount: DisplayRepresentation(
            title: LocalizedStringResource("widget.config.stat.pendingAmount")
        ),
        .last30DaysSpending: DisplayRepresentation(
            title: LocalizedStringResource("widget.config.stat.last30DaysSpending")
        ),
        .thisMonthDelivered: DisplayRepresentation(
            title: LocalizedStringResource("widget.config.stat.thisMonthDelivered")
        ),
        .inTransit: DisplayRepresentation(
            title: LocalizedStringResource("widget.config.stat.inTransit")
        ),
        .avgDeliveryDays: DisplayRepresentation(
            title: LocalizedStringResource("widget.config.stat.avgDeliveryDays")
        ),
        .spendingDelta: DisplayRepresentation(
            title: LocalizedStringResource("widget.config.stat.spendingDelta")
        ),
        .codPendingAmount: DisplayRepresentation(
            title: LocalizedStringResource("widget.config.stat.codPendingAmount")
        )
    ]

    var isPro: Bool {
        switch self {
        case .pendingPickup, .deliveredLast30Days: return false
        default: return true
        }
    }

    var iconName: String {
        switch self {
        case .pendingPickup:        return "shippingbox.fill"
        case .deliveredLast30Days:  return "checkmark.rectangle.stack.fill"
        case .thisMonthSpending:    return "dollarsign.circle.fill"
        case .pendingAmount:        return "banknote.fill"
        case .last30DaysSpending:   return "yensign.circle.fill"
        case .thisMonthDelivered:   return "checkmark.seal.fill"
        case .inTransit:            return "truck.box.fill"
        case .avgDeliveryDays:      return "clock.badge.checkmark.fill"
        case .spendingDelta:        return "chart.line.uptrend.xyaxis"
        case .codPendingAmount:     return "creditcard.fill"
        }
    }
}

// MARK: - Free Widget Intent

struct FreeWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.config.freeTitle"
    static var description: IntentDescription = IntentDescription("widget.config.freeDescription")

    @Parameter(title: LocalizedStringResource("widget.config.topStat"), default: .pendingPickup)
    var topStat: FreeWidgetStatType

    @Parameter(title: LocalizedStringResource("widget.config.bottomStat"), default: .deliveredLast30Days)
    var bottomStat: FreeWidgetStatType

    static var parameterSummary: some ParameterSummary {
        Summary {
            \FreeWidgetIntent.$topStat
            \FreeWidgetIntent.$bottomStat
        }
    }
}

// MARK: - Lock Screen Package Intent

struct LockScreenPackageIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.lockscreen.config.packageTitle"
    static var description: IntentDescription = IntentDescription("widget.lockscreen.config.packageDescription")

    @Parameter(title: LocalizedStringResource("widget.lockscreen.config.package"))
    var package: PackageAppEntity?

    static var parameterSummary: some ParameterSummary {
        Summary {
            \LockScreenPackageIntent.$package
        }
    }
}

// MARK: - Lock Screen Stats Intent

struct LockScreenStatsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.lockscreen.config.statsTitle"
    static var description: IntentDescription = IntentDescription("widget.lockscreen.config.statsDescription")

    @Parameter(title: LocalizedStringResource("widget.lockscreen.config.stat"), default: .pendingPickup)
    var stat: FreeWidgetStatType

    static var parameterSummary: some ParameterSummary {
        Summary {
            \LockScreenStatsIntent.$stat
        }
    }
}

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
