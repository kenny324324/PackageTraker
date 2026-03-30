import SwiftUI

/// 購物平台消費分佈 Donut Chart
struct PlatformSpendingChartView: View {
    let data: [(platform: String, amount: Double, count: Int)]
    @Binding var selectedPlatform: String?

    @ObservedObject private var themeManager = ThemeManager.shared

    private var totalAmount: Double {
        data.map(\.amount).reduce(0, +)
    }

    private let segmentColors: [Color] = [
        .blue, .purple, .orange, .green, .pink, .cyan
    ]

    var body: some View {
        VStack(spacing: 16) {
            // Donut chart
            ZStack {
                ForEach(Array(segments.enumerated()), id: \.element.platform) { index, segment in
                    DonutSegment(
                        startAngle: segment.startAngle,
                        endAngle: segment.endAngle
                    )
                    .fill(segmentColors[index % segmentColors.count])
                    .onTapGesture {
                        if segment.platform != String(localized: "stats.spending.platform.other") {
                            selectedPlatform = segment.platform
                        }
                    }
                }

                // Center label
                VStack(spacing: 2) {
                    Text(formatCurrency(totalAmount))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 160, height: 160)

            // Legend
            VStack(spacing: 8) {
                ForEach(Array(data.enumerated()), id: \.element.platform) { index, item in
                    Button {
                        if item.platform != String(localized: "stats.spending.platform.other") {
                            selectedPlatform = item.platform
                        }
                    } label: {
                        legendRow(
                            color: segmentColors[index % segmentColors.count],
                            platform: item.platform,
                            amount: item.amount,
                            count: item.count
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .adaptiveCardStyle()
    }

    // MARK: - Segments

    private struct SegmentData: Identifiable {
        let id = UUID()
        let platform: String
        let startAngle: Angle
        let endAngle: Angle
    }

    private var segments: [SegmentData] {
        guard totalAmount > 0 else { return [] }
        var results: [SegmentData] = []
        var currentAngle: Double = -90 // Start from top

        for item in data {
            let sliceAngle = (item.amount / totalAmount) * 360
            results.append(SegmentData(
                platform: item.platform,
                startAngle: .degrees(currentAngle),
                endAngle: .degrees(currentAngle + sliceAngle)
            ))
            currentAngle += sliceAngle
        }
        return results
    }

    // MARK: - Legend Row

    private func legendRow(color: Color, platform: String, amount: Double, count: Int) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(platform)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Text(formatCurrency(amount))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Donut Segment Shape

private struct DonutSegment: Shape {
    let startAngle: Angle
    let endAngle: Angle
    private let lineWidth: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - lineWidth / 2

        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path.strokedPath(.init(lineWidth: lineWidth, lineCap: .butt))
    }
}
