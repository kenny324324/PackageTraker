import SwiftUI

/// 狀態標籤元件（綠點 + 狀態文字）
struct StatusBadgeView: View {
    let status: TrackingStatus
    var showText: Bool = true
    var showCheckbox: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            // 狀態指示點
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)

            // 狀態文字（白色）
            if showText {
                Text(status.displayName)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: true, vertical: false)
            }

            // 勾選框（用於取件確認）
            if showCheckbox {
                Image(systemName: "circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 帶圖示的狀態徽章
struct StatusIconBadge: View {
    let status: TrackingStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .font(.caption)
            Text(status.displayName)
                .font(.caption)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Previews

#Preview("Status Badges") {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(TrackingStatus.allCases) { status in
            HStack {
                StatusBadgeView(status: status)
                Spacer()
                StatusIconBadge(status: status)
            }
        }
    }
    .padding()
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}

#Preview("With Checkbox") {
    VStack(spacing: 12) {
        StatusBadgeView(status: .arrivedAtStore, showCheckbox: true)
        StatusBadgeView(status: .inTransit, showCheckbox: true)
    }
    .padding()
    .frame(width: 200)
    .background(Color.cardBackground)
    .preferredColorScheme(.dark)
}
