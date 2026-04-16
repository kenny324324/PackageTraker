//
//  PackageTrakerWidget.swift
//  PackageTrakerWidget
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Free Widget (Small only)

struct PackagePickupWidget: Widget {
    let kind: String = "PackagePickupWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: FreeWidgetIntent.self,
            provider: FreeWidgetTimelineProvider()
        ) { entry in
            FreeWidgetEntryView(entry: entry)
                .containerBackground(.ultraThinMaterial, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.pickup.displayName"))
        .description(String(localized: "widget.pickup.description"))
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct FreeWidgetEntryView: View {
    let entry: PackageTimelineEntry

    var body: some View {
        FreeWidgetView(
            entry: entry,
            topStat: entry.topStat,
            bottomStat: entry.bottomStat
        )
    }
}

// MARK: - Quick Add Widget (Small only, Free + Pro)

struct QuickAddWidget: Widget {
    let kind: String = "QuickAddWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PackageTimelineProvider()) { _ in
            QuickAddWidgetView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.quickAdd.displayName"))
        .description(String(localized: "widget.quickAdd.description"))
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - PRO Widget (All sizes)

struct PackageTrakerWidget: Widget {
    let kind: String = "PackageTrakerWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: PackageWidgetIntent.self,
            provider: ProPackageTimelineProvider()
        ) { entry in
            ProWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.title"))
        .description(String(localized: "widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Lock Screen Quick Add Widget (Circular, tap to add)

struct LockScreenQuickAddWidget: Widget {
    let kind: String = "LockScreenQuickAddWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PackageTimelineProvider()) { _ in
            LockScreenQuickAddView()
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.lockscreen.quickAdd.displayName"))
        .description(String(localized: "widget.lockscreen.quickAdd.description"))
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Lock Screen Circular Widget (Static)

struct LockScreenCircularWidget: Widget {
    let kind: String = "LockScreenCircularWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PackageTimelineProvider()) { entry in
            LockScreenCircularView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.lockscreen.circular.displayName"))
        .description(String(localized: "widget.lockscreen.circular.description"))
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Lock Screen Package Widget (Configurable)

struct LockScreenPackageWidget: Widget {
    let kind: String = "LockScreenPackageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: LockScreenPackageIntent.self,
            provider: LockScreenPackageTimelineProvider()
        ) { entry in
            LockScreenRectangularView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.lockscreen.package.displayName"))
        .description(String(localized: "widget.lockscreen.package.description"))
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Lock Screen Stats Widget (Configurable)

struct LockScreenStatsWidget: Widget {
    let kind: String = "LockScreenStatsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: LockScreenStatsIntent.self,
            provider: LockScreenStatsTimelineProvider()
        ) { entry in
            LockScreenStatsRectangularView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.lockscreen.stats.displayName"))
        .description(String(localized: "widget.lockscreen.stats.description"))
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - PRO Entry View Router

struct ProWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: PackageTimelineEntry

    var body: some View {
        if entry.isPro {
            switch widgetFamily {
            case .systemSmall:
                SmallWidgetView(entry: entry)
            case .systemMedium:
                MediumWidgetView(entry: entry)
            case .systemLarge:
                LargeWidgetView(entry: entry)
            default:
                SmallWidgetView(entry: entry)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(String(localized: "widget.proOnly"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Preview

#Preview("PRO - Small", as: .systemSmall) {
    PackageTrakerWidget()
} timeline: {
    PackageTimelineEntry.preview
}

#Preview("PRO - Medium", as: .systemMedium) {
    PackageTrakerWidget()
} timeline: {
    PackageTimelineEntry.preview
}

#Preview("PRO - Large", as: .systemLarge) {
    PackageTrakerWidget()
} timeline: {
    PackageTimelineEntry.preview
}

#Preview("Free - Small", as: .systemSmall) {
    PackagePickupWidget()
} timeline: {
    PackageTimelineEntry.freePreview
}

#Preview("Quick Add", as: .systemSmall) {
    QuickAddWidget()
} timeline: {
    PackageTimelineEntry.freePreview
}

#Preview("Lock Screen - Circular", as: .accessoryCircular) {
    LockScreenCircularWidget()
} timeline: {
    PackageTimelineEntry.freePreview
}

#Preview("Lock Screen - Package", as: .accessoryRectangular) {
    LockScreenPackageWidget()
} timeline: {
    PackageTimelineEntry.freePreview
}

#Preview("Lock Screen - Stats", as: .accessoryRectangular) {
    LockScreenStatsWidget()
} timeline: {
    PackageTimelineEntry.freePreview
}
