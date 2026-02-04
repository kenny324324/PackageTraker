import SwiftUI

/// 主題顏色設定頁面
struct ThemeSettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    
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
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                themeManager.selectedTheme = theme
            }
        } label: {
            HStack(spacing: 16) {
                // 顏色圓圈
                Circle()
                    .fill(theme.color)
                    .frame(width: 40, height: 40)
                
                // 名稱
                Text(theme.displayName)
                    .font(.body)
                    .foregroundStyle(.white)
                
                Spacer()
                
                // 選中標記
                if themeManager.selectedTheme == theme {
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
