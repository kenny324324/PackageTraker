import SwiftUI

/// 主題顏色設定頁面
struct ThemeSettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 預覽區
                previewSection

                // 顏色選項列表
                colorOptionsSection
            }
            .padding()
        }
        .background(
            ZStack {
                Color.appBackground

                // 模擬首頁漸層
                LinearGradient(
                    colors: [
                        themeManager.currentColor.opacity(0.5),
                        themeManager.currentColor.opacity(0.28),
                        themeManager.currentColor.opacity(0.12),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 350)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
        )
        .navigationTitle(String(localized: "theme.title"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        Spacer()
            .frame(height: 80)
    }

    // MARK: - Color Options Section

    private var colorOptionsSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(ThemeColor.allCases.enumerated()), id: \.element.id) { index, theme in
                colorOptionRow(theme: theme)

                if index < ThemeColor.allCases.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.1))
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func colorOptionRow(theme: ThemeColor) -> some View {
        let isLocked = FeatureFlags.subscriptionEnabled && !subscriptionManager.hasAllThemes && theme != .coffeeBrown
        let isSelected = themeManager.selectedTheme == theme

        return Button {
            if isLocked {
                showPaywall = true
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    themeManager.selectedTheme = theme
                }
            }
        } label: {
            HStack(spacing: 16) {
                // 顏色圓圈
                Circle()
                    .fill(theme.color)
                    .frame(width: 40, height: 40)
                    .overlay {
                        if isLocked {
                            Circle()
                                .fill(.black.opacity(0.4))
                        }
                    }

                // 名稱
                Text(theme.displayName)
                    .font(.body)
                    .foregroundStyle(isLocked ? Color.secondary : Color.white)

                Spacer()

                if isLocked {
                    // 鎖頭 + 皇冠
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                        Image(systemName: "crown.fill")
                            .font(.caption)
                    }
                    .foregroundStyle(.yellow.opacity(0.7))
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ThemeSettingsView()
    }
}
