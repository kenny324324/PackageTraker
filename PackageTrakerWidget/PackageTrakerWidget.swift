//
//  PackageTrakerWidget.swift
//  PackageTrakerWidget
//
//  Widget extension entry point
//

import WidgetKit
import SwiftUI

@main
struct PackageTrakerWidgetBundle: WidgetBundle {
    var body: some Widget {
        PackageTrakerWidget()
    }
}

struct PackageTrakerWidget: Widget {
    let kind: String = "PackageTrakerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PackageTimelineProvider()) { entry in
            PackageWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.displayName"))
        .description(String(localized: "widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry View Router

struct PackageWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: PackageTimelineEntry

    var body: some View {
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
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    PackageTrakerWidget()
} timeline: {
    PackageTimelineEntry.preview
}

#Preview(as: .systemMedium) {
    PackageTrakerWidget()
} timeline: {
    PackageTimelineEntry.preview
}

#Preview(as: .systemLarge) {
    PackageTrakerWidget()
} timeline: {
    PackageTimelineEntry.preview
}
