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
        StaticConfiguration(kind: kind, provider: PackageTimelineProvider()) { entry in
            FreeWidgetView(entry: entry)
                .containerBackground(.ultraThinMaterial, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.pickup.displayName"))
        .description(String(localized: "widget.pickup.description"))
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
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
