import SwiftUI
import SwiftData

/// 主 TabView
struct MainTabView: View {
    @Binding var selectedTab: Int
    @Binding var pendingPackageId: UUID?
    @Binding var showAddPackage: Bool
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            // 包裹清單（主頁）
            PackageListView(pendingPackageId: $pendingPackageId, showAddPackage: $showAddPackage)
                .tabItem {
                    Label(String(localized: "tab.packages"), systemImage: "shippingbox.fill")
                }
                .tag(0)

            // 個人統計
            NavigationStack {
                PersonalStatsView()
            }
                .tabItem {
                    Label(String(localized: "tab.stats"), systemImage: "chart.bar.fill")
                }
                .tag(1)

            // 歷史記錄
            HistoryView()
                .tabItem {
                    Label(String(localized: "tab.history"), systemImage: "archivebox")
                }
                .tag(2)

            // 設定
            SettingsView()
                .tabItem {
                    Label(String(localized: "tab.settings"), systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(themeManager.currentColor)
        .preferredColorScheme(.dark)
        .onChange(of: selectedTab) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Previews

#Preview {
    MainTabView(selectedTab: .constant(0), pendingPackageId: .constant(nil), showAddPackage: .constant(false))
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
