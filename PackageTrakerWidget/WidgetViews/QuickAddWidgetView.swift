//
//  QuickAddWidgetView.swift
//  PackageTrakerWidget
//
//  Quick-add widget (small only): tap to open add-package flow.
//

import SwiftUI
import WidgetKit

struct QuickAddWidgetView: View {
    var body: some View {
        Link(destination: URL(string: "packagetraker://addPackage")!) {
            ZStack {
                // Top-left: app icon
                VStack {
                    HStack {
                        Image("SplashIcon")
                            .resizable()
                            .widgetAccentedRenderingMode(.fullColor)
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                        Spacer()
                    }
                    Spacer()
                }

                // Center: + button
                VStack {
                    Spacer()
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 90, height: 90)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .padding(14)
        }
    }
}
