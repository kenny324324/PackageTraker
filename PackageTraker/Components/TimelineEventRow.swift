//
//  TimelineEventRow.swift
//  PackageTraker
//
//  時間軸事件行 — 可同時用於 TrackingEvent (@Model) 和 TrackingEventDTO
//

import SwiftUI

// MARK: - Protocol

/// 時間軸事件顯示所需的資料協議
protocol TimelineEventData {
    var eventDescription: String { get }
    var formattedTime: String { get }
    var location: String? { get }
    var status: TrackingStatus { get }
}

// MARK: - Conformances

extension TrackingEvent: TimelineEventData {
    // 已有 eventDescription, formattedTime, location, status — 自動符合
}

extension TrackingEventDTO: TimelineEventData {
    var eventDescription: String { description }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: timestamp)
    }
}

// MARK: - View

/// 時間軸事件行
struct TimelineEventRow: View {
    let event: any TimelineEventData
    let isFirst: Bool
    let isLast: Bool

    // 波紋動畫狀態（多層波紋）
    @State private var ripple1 = false
    @State private var ripple2 = false
    @State private var ripple3 = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 時間軸線 + 圓點
            VStack(spacing: 0) {
                // 上方連接線
                if !isFirst {
                    Rectangle()
                        .fill(Color.secondaryCardBackground)
                        .frame(width: 2, height: 4)
                }

                // 圓點（含波紋動畫）
                ZStack {
                    // 多層波紋效果（僅當前狀態）
                    if isFirst {
                        // 第一層波紋
                        Circle()
                            .fill(event.status.color.opacity(ripple1 ? 0 : 0.3))
                            .frame(width: 12, height: 12)
                            .scaleEffect(ripple1 ? 2.5 : 1)

                        // 第二層波紋（延遲）
                        Circle()
                            .fill(event.status.color.opacity(ripple2 ? 0 : 0.3))
                            .frame(width: 12, height: 12)
                            .scaleEffect(ripple2 ? 2.5 : 1)

                        // 第三層波紋（更多延遲）
                        Circle()
                            .fill(event.status.color.opacity(ripple3 ? 0 : 0.3))
                            .frame(width: 12, height: 12)
                            .scaleEffect(ripple3 ? 2.5 : 1)
                    }

                    // 主圓點
                    Circle()
                        .fill(isFirst ? event.status.color : Color.secondaryCardBackground)
                        .frame(width: 12, height: 12)
                }
                .frame(width: 24, height: 24)

                // 下方連接線
                if !isLast {
                    Rectangle()
                        .fill(Color.secondaryCardBackground)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 20)
            .padding(.top, 2) // 對齊文字中心

            // 事件內容
            VStack(alignment: .leading, spacing: 4) {
                Text(event.eventDescription)
                    .font(.subheadline)
                    .foregroundStyle(isFirst ? .primary : .secondary)

                HStack {
                    Text(event.formattedTime)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if let location = event.location {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : 16)

            Spacer()
        }
        .onAppear {
            // 啟動多層波紋動畫（交錯啟動）
            if isFirst {
                // 第一層波紋
                withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                    ripple1 = true
                }
                // 第二層波紋（延遲 0.6 秒）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                        ripple2 = true
                    }
                }
                // 第三層波紋（延遲 1.2 秒）
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                        ripple3 = true
                    }
                }
            }
        }
    }
}
