import SwiftUI
import SwiftData

/// 主 TabView
struct MainTabView: View {
    @Binding var selectedTab: Int
    @Binding var pendingPackageId: UUID?
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            // 包裹清單（主頁）
            PackageListView(pendingPackageId: $pendingPackageId)
                .tabItem {
                    Label(String(localized: "tab.packages"), systemImage: "shippingbox.fill")
                }
                .tag(0)

            // 歷史記錄
            HistoryView()
                .tabItem {
                    Label(String(localized: "tab.history"), systemImage: "archivebox")
                }
                .tag(1)

            // 設定
            SettingsView()
                .tabItem {
                    Label(String(localized: "tab.settings"), systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(themeManager.currentColor)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Previews

#Preview {
    MainTabView(selectedTab: .constant(0), pendingPackageId: .constant(nil))
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
