import SwiftUI
import SwiftData
import StoreKit
import FirebaseAuth
import FirebaseFirestore

/// 更新頻率選項
enum RefreshInterval: String, CaseIterable {
    case fifteenMinutes = "15min"
    case thirtyMinutes = "30min"
    case oneHour = "1hour"
    case twoHours = "2hours"
    case fourHours = "4hours"
    case manual = "manual"
    
    var displayName: String {
        switch self {
        case .fifteenMinutes: return String(localized: "interval.15min")
        case .thirtyMinutes: return String(localized: "interval.30min")
        case .oneHour: return String(localized: "interval.1hour")
        case .twoHours: return String(localized: "interval.2hours")
        case .fourHours: return String(localized: "interval.4hours")
        case .manual: return String(localized: "interval.manual")
        }
    }
    
    var seconds: TimeInterval {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .fourHours: return 4 * 60 * 60
        case .manual: return 0
        }
    }
}

/// 設定頁面
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview

    @Query private var existingPackages: [Package]

    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var authService = FirebaseAuthService.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var appStatsService = AppStatsService.shared

    // 通知設定（持久化到 UserDefaults，並同步到 Firestore）
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("arrivalNotificationEnabled") private var arrivalNotificationEnabled = true
    @AppStorage("shippedNotificationEnabled") private var shippedNotificationEnabled = true
    @AppStorage("pickupReminderEnabled") private var pickupReminderEnabled = true

    @State private var showClearDataConfirmation = false
    @State private var showClearDataSuccess = false
    @State private var showNotificationDeniedAlert = false
    @State private var showFeedbackError = false
    @State private var showPaywall = false
    @State private var showAccountDetail = false
    @State private var safariURL: IdentifiableURL?
    @AppStorage("cachedDisplayName") private var cachedDisplayName: String = ""
    @AppStorage("cachedPhotoURL") private var cachedPhotoURL: String = ""
    @AppStorage("refreshInterval") private var refreshInterval: RefreshInterval = .thirtyMinutes
    @AppStorage("hideDeliveredPackages") private var hideDeliveredPackages = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 帳號設定
                    accountSection

                    // 包裹額度（免費用戶才顯示）
                    if FeatureFlags.subscriptionEnabled && !subscriptionManager.isPro {
                        packageQuotaSection
                    }

                    // 一般設定
                    generalSection

                    // 通知設定
                    notificationSection

                    // 小工具
                    if FeatureFlags.widgetEnabled {
                        widgetSection
                    }

                    // 社群統計
                    if appStatsService.isLoaded {
                        appStatsSection
                    }

                    // 邀請好友
                    if FeatureFlags.referralEnabled {
                        InviteFriendsSection()
                    }

                    // 評分卡片
                    rateAppSection

                    // 支援區塊
                    supportSection

                    // 關於區塊
                    aboutSection

                    // 我們的其他作品
                    otherAppsSection

                    #if DEBUG
                    // 開發者選項（僅 DEBUG 模式）
                    developerSection
                    #endif

                    // 頁面底部 footer
                    VStack(spacing: 4) {
                        Text("Made By Kenny Studio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("© 2025 Kenny Yu")
                            .font(.caption2)
                            .foregroundStyle(Color(.systemGray3))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .adaptiveBackground()
            .navigationTitle(String(localized: "settings.title"))
            .toolbarTitleDisplayMode(.inlineLarge)
            .sheet(item: $safariURL) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
            .confirmationDialog(
                String(localized: "settings.clearDataConfirm"),
                isPresented: $showClearDataConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "common.clear"), role: .destructive) {
                    clearAllData()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings.clearDataMessage"))
            }
            .alert(String(localized: "settings.clearDataSuccess"), isPresented: $showClearDataSuccess) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            }
            .alert(String(localized: "settings.notificationPermissionDenied"), isPresented: $showNotificationDeniedAlert) {
                Button(String(localized: "common.ok"), role: .cancel) {}
                Button(String(localized: "common.settings")) {
                    openAppSettings()
                }
            } message: {
                Text(String(localized: "settings.notificationPermissionDeniedMessage"))
            }
            .alert(String(localized: "email.cannotOpenTitle"), isPresented: $showFeedbackError) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "email.cannotOpenMessage") + " \(AppConfiguration.feedbackEmail)")
            }
            .fullScreenCover(isPresented: $showPaywall) {
                PaywallView(trigger: .packages)
            }
            .sheet(isPresented: $showAccountDetail) {
                AccountDetailView()
            }
            .onAppear {
                checkNotificationPermission()
                loadDisplayName()
            }
            .task {
                await appStatsService.fetchStats()
            }
            .onChange(of: notificationsEnabled) { oldValue, newValue in
                if newValue && !oldValue {
                    // 用戶打開通知，請求權限
                    Task {
                        let granted = await NotificationService.shared.requestAuthorization()
                        if !granted {
                            notificationsEnabled = false
                            showNotificationDeniedAlert = true
                            return
                        }
                        FirebasePushService.shared.syncDeviceNotificationSettingsInBackground()
                    }
                } else if !newValue && oldValue {
                    // 用戶關閉通知，取消所有通知
                    NotificationService.shared.cancelAllNotifications()
                    FirebasePushService.shared.syncDeviceNotificationSettingsInBackground()
                }
            }
            .onChange(of: hideDeliveredPackages) { _, newValue in
                FirebaseSyncService.shared.syncUserPreferences(hideDeliveredPackages: newValue)
            }
            .onChange(of: refreshInterval) { _, newValue in
                FirebaseSyncService.shared.syncUserPreferences(refreshInterval: newValue.rawValue)
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(spacing: 0) {
            // 上半部：頭像 + 名稱 + 箭頭（可點擊）
            Button {
                showAccountDetail = true
            } label: {
                HStack(spacing: 14) {
                    // 頭像
                    AvatarView(urlString: cachedPhotoURL, size: 48)

                    // 名稱
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 分隔線
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16)

            // 下半部：訂閱方案資訊（灰底）
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(subscriptionManager.subscriptionName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Text(subscriptionManager.isPro
                         ? String(localized: "settings.subscription.proDesc")
                         : String(localized: "settings.subscription.freeDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if subscriptionManager.isPro {
                    Text("PRO")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(12)
            .background(Color(.systemGray6).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.secondaryCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: subscriptionManager.isPro ? 2 : 0
                )
        )
        .shadow(
            color: subscriptionManager.isPro ? .yellow.opacity(0.2) : .clear,
            radius: 8, x: 0, y: 2
        )
        .shadow(
            color: subscriptionManager.isPro ? .orange.opacity(0.3) : .clear,
            radius: 12, x: 0, y: 0
        )
    }

    /// 顯示名稱（優先順序：快取 > email username > 未知）
    private var displayName: String {
        if !cachedDisplayName.isEmpty {
            return cachedDisplayName
        }
        if let email = authService.currentUser?.email {
            let username = email.components(separatedBy: "@").first ?? email
            return username
        }
        return String(localized: "account.unknown")
    }

    // MARK: - Package Quota Section

    private var packageQuotaSection: some View {
        let remainingCount = subscriptionManager.maxPackageCount - activePackageCount
        let isFull = activePackageCount >= subscriptionManager.maxPackageCount
        let progressColor: Color = isFull ? .red : .green
        let borderColor: Color = isFull ? .red.opacity(0.3) : .green.opacity(0.3)

        return Button {
            showPaywall = true
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(progressColor)

                    Text(String(localized: "settings.quota.title"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)

                    Spacer()

                    Text(String(localized: "settings.quota.remaining") + " \(max(0, remainingCount)) " + String(localized: "settings.quota.packages"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(progressColor)
                }

                // 進度條
                VStack(spacing: 6) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // 背景
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(height: 6)

                            // 進度
                            RoundedRectangle(cornerRadius: 8)
                                .fill(progressColor)
                                .frame(width: min(CGFloat(activePackageCount) / CGFloat(subscriptionManager.maxPackageCount) * geometry.size.width, geometry.size.width), height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text(String(localized: "settings.quota.used") + " \(activePackageCount)/\(subscriptionManager.maxPackageCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()

                        HStack(spacing: 3) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 9))
                            Text(String(localized: "settings.quota.upgrade"))
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(isFull ? Color.secondary : Color.yellow)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(borderColor, lineWidth: 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.secondaryCardBackground)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// 計算活躍包裹數量（只計算未取貨的包裹）
    private var activePackageCount: Int {
        existingPackages.filter { !$0.isArchived && $0.status != .delivered }.count
    }

    // MARK: - Rate App Section

    // MARK: - App Stats Section

    private var appStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "settings.community"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Spacer()

                Text(String(localized: "settings.stats.updateInterval"))
                    .font(.caption2)
                    .foregroundStyle(Color(.systemGray3))
            }

            HStack(spacing: 0) {
                // 使用者數
                statsColumn(
                    value: appStatsService.totalUsers,
                    diff: appStatsService.diffUsers,
                    label: String(localized: "settings.stats.users.label")
                )

                // 豎線分隔
                Color.white.opacity(0.1)
                    .frame(width: 1)
                    .padding(.vertical, 16)

                // 追蹤包裹數
                statsColumn(
                    value: appStatsService.totalPackages,
                    diff: appStatsService.diffPackages,
                    label: String(localized: "settings.stats.packages.label")
                )

                // 豎線分隔
                Color.white.opacity(0.1)
                    .frame(width: 1)
                    .padding(.vertical, 16)

                // 送達數
                statsColumn(
                    value: appStatsService.totalDelivered,
                    diff: appStatsService.diffDelivered,
                    label: String(localized: "settings.stats.delivered.label")
                )
            }
            .padding(.vertical, 20)
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private func statsColumn(value: Int, diff: Int, label: String) -> some View {
        VStack(spacing: 8) {
            AnimatedNumberView(
                value: value,
                font: .system(size: 28, weight: .bold, design: .rounded),
                fontWeight: .bold,
                textColor: .white
            )
            .frame(height: 32)
            .overlay(alignment: .topTrailing) {
                if diff > 0 {
                    Text("+\(diff)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.green)
                        .offset(x: 20, y: -2)
                }
            }

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var rateAppSection: some View {
        Button {
            if let url = URL(string: "https://apps.apple.com/app/id6758759908?action=write-review") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "settings.rateApp.title"))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text(String(localized: "settings.rateApp.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // 星星
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.yellow)
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer()

                // App Store 3D icon
                Image("AppStoreIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
            }
            .padding(16)
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Support Section

    private var supportSection: some View {
        VStack(spacing: 0) {
            // 回報問題
            Button {
                openFeedbackEmail()
            } label: {
                settingsRowButton(
                    icon: "envelope.fill",
                    iconBg: .green,
                    title: String(localized: "settings.reportIssue")
                )
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // 隱私政策
            Button {
                openPrivacyPolicy()
            } label: {
                settingsRowButton(
                    icon: "hand.raised.fill",
                    iconBg: .teal,
                    title: String(localized: "settings.privacyPolicy")
                )
            }
        }
        .background(Color.secondaryCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.about"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                // App 資訊頭部
                HStack(spacing: 16) {
                    // App Icon
                    Image("SplashIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppConfiguration.appName)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("\(String(localized: "app.versionPrefix")) \(AppConfiguration.fullVersionString)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(16)

                Divider()
                    .overlay(Color.white.opacity(0.1))

                // Track.TW 資料來源標註
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "about.trackingDataSource"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        safariURL = IdentifiableURL(url: URL(string: "https://track.tw")!)
                    } label: {
                        Text("Track.TW")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                    }
                }
                .padding(16)
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Other Apps Section

    private var otherAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.otherApps"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                otherAppRow(
                    iconName: "FindToiletsIcon",
                    fallbackIcon: "mappin.and.ellipse",
                    fallbackColor: .blue,
                    name: "FindToilets",
                    subtitle: String(localized: "settings.otherApps.findtoilets"),
                    appStoreURL: "https://apps.apple.com/app/id6752564383"
                )

                Divider()
                    .background(Color.white.opacity(0.1))

                otherAppRow(
                    iconName: "MishIcon",
                    fallbackIcon: "book.fill",
                    fallbackColor: .indigo,
                    name: "Mish",
                    subtitle: String(localized: "settings.otherApps.mish"),
                    appStoreURL: "https://apps.apple.com/app/id6749848120"
                )

                Divider()
                    .background(Color.white.opacity(0.1))

                otherAppRow(
                    iconName: "MinoIcon",
                    fallbackIcon: "checklist",
                    fallbackColor: Color.brown,
                    name: "Mino",
                    subtitle: String(localized: "settings.otherApps.mino"),
                    appStoreURL: "https://apps.apple.com/app/id6746743276"
                )
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    /// 其他 App 列
    private func otherAppRow(iconName: String, fallbackIcon: String, fallbackColor: Color, name: String, subtitle: String, appStoreURL: String) -> some View {
        Button {
            if let url = URL(string: appStoreURL) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 14) {
                // App Icon（優先用 Assets 圖片，沒有則用 SF Symbol 佔位）
                Group {
                    if UIImage(named: iconName) != nil {
                        Image(iconName)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: fallbackIcon)
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(fallbackColor)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // 名稱 + 描述
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // 取得按鈕
                Text(String(localized: "settings.otherApps.get"))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray4).opacity(0.5))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Developer Section (DEBUG only)

    #if DEBUG
    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("開發者選項")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.orange)

            NavigationLink(destination: DeveloperOptionsView()) {
                HStack(spacing: 12) {
                    settingsIcon("hammer.fill", bgColor: .orange)

                    Text("開發者選項")
                        .foregroundStyle(.white)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Text("僅在 DEBUG 模式顯示")
                .font(.caption)
                .foregroundStyle(.orange.opacity(0.7))
        }
    }
    #endif

    // MARK: - Widget Section

    private var widgetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.widget.title"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    // Icon
                    Image(systemName: "rectangle.on.rectangle.angled.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "settings.widget.title"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)

                        Text(String(localized: "settings.widget.hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        if !subscriptionManager.isPro {
                            Text(String(localized: "settings.widget.freeDesc"))
                                .font(.caption)
                                .foregroundStyle(.orange.opacity(0.8))
                                .lineLimit(2)
                                .padding(.top, 2)
                        }
                    }

                    Spacer()
                }
                .padding(16)
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - General Section
    
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.general"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                // 主題顏色
                NavigationLink(destination: ThemeSettingsView()) {
                    HStack(spacing: 12) {
                        settingsIcon("paintpalette.fill", bgColor: .pink)

                        Text(String(localized: "settings.themeColor"))
                            .foregroundStyle(.white)

                        Spacer()

                        Circle()
                            .fill(themeManager.currentColor)
                            .frame(width: 24, height: 24)
                    }
                    .padding(16)
                }

                Divider()
                    .background(Color.cardBackground)

                // 常用取貨地點
                NavigationLink(destination: SavedLocationsView()) {
                    HStack(spacing: 12) {
                        settingsIcon("mappin.and.ellipse", bgColor: .orange)

                        Text(String(localized: "settings.savedLocations"))
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.gray)
                    }
                    .padding(16)
                }

                Divider()
                    .background(Color.cardBackground)

                // 首頁統計
                NavigationLink(destination: StatSettingsView()) {
                    HStack(spacing: 12) {
                        settingsIcon("chart.bar.fill", bgColor: .cyan)

                        Text(String(localized: "settings.homeStats"))
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.gray)
                    }
                    .padding(16)
                }

                Divider()
                    .background(Color.cardBackground)

                // 隱藏已取貨包裹
                settingsToggleRow(
                    icon: "eye.slash.fill",
                    iconBg: .gray,
                    title: String(localized: "settings.hideDelivered"),
                    isOn: $hideDeliveredPackages
                )

                Divider()
                    .background(Color.cardBackground)

                // 語言設定
                Button {
                    openAppSettings()
                } label: {
                    HStack(spacing: 12) {
                        settingsIcon("globe", bgColor: .blue)

                        Text(String(localized: "settings.language"))
                            .foregroundStyle(.white)

                        Spacer()

                        Text(currentLanguage)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.3))
                            .clipShape(Capsule())
                    }
                    .padding(16)
                }

                Divider()
                    .background(Color.cardBackground)

                // 帳號管理
                NavigationLink(destination: AccountManagementView()) {
                    HStack(spacing: 12) {
                        settingsIcon("person.badge.minus", bgColor: .red)

                        Text(String(localized: "settings.accountManagement"))
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.gray)
                    }
                    .padding(16)
                }
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // 語言設置提示
            Text(String(localized: "settings.languageHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Notification Section

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.notifications"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                // 推播通知總開關
                settingsToggleRow(
                    icon: "bell.fill",
                    iconBg: .red,
                    title: String(localized: "settings.pushNotification"),
                    isOn: $notificationsEnabled
                )

                Divider()
                    .background(Color.cardBackground)

                // 推播設定
                NavigationLink(destination: NotificationSettingsView()) {
                    HStack(spacing: 12) {
                        settingsIcon("bell.badge.fill", bgColor: .orange)

                        Text(String(localized: "settings.notificationSettings"))
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.gray)
                    }
                    .padding(16)
                }
                .disabled(!notificationsEnabled)
                .opacity(notificationsEnabled ? 1.0 : 0.5)
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Text(String(localized: "settings.notificationHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Management Section

    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.dataManagement"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                // 清除所有資料
                Button {
                    showClearDataConfirmation = true
                } label: {
                    HStack(spacing: 12) {
                        settingsIcon("trash.fill", bgColor: .red)

                        Text(String(localized: "settings.clearData"))
                            .foregroundStyle(.red)

                        Spacer()
                    }
                    .padding(16)
                }
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
    
    // MARK: - Helper Views

    /// 圓角方形圖示
    private func settingsIcon(_ icon: String, bgColor: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func settingsRow(icon: String, iconBg: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            settingsIcon(icon, bgColor: iconBg)

            Text(title)
                .foregroundStyle(.white)

            Spacer()

            Text(value)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private func settingsRowButton(icon: String, iconBg: Color, title: String) -> some View {
        HStack(spacing: 12) {
            settingsIcon(icon, bgColor: iconBg)

            Text(title)
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(16)
    }

    private func settingsToggleRow(icon: String, iconBg: Color, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            settingsIcon(icon, bgColor: iconBg)

            Toggle(title, isOn: isOn)
                .tint(Color.appAccent)
        }
        .padding(16)
    }
    
    // MARK: - Computed Properties
    
    private var currentLanguage: String {
        let preferredLanguage = Locale.preferredLanguages.first ?? "zh-Hant"
        if preferredLanguage.starts(with: "zh-Hant") {
            return String(localized: "language.traditionalChinese")
        } else if preferredLanguage.starts(with: "zh-Hans") {
            return String(localized: "language.simplifiedChinese")
        } else if preferredLanguage.starts(with: "en") {
            return String(localized: "language.english")
        } else {
            return String(localized: "language.traditionalChinese")
        }
    }

    // MARK: - Actions

    /// 從 Firestore 載入顯示名稱（背景更新，不影響已快取的名稱）
    private func loadDisplayName() {
        guard let userId = authService.currentUser?.uid else { return }

        let db = Firestore.firestore()
        Task {
            do {
                let doc = try await db.collection("users").document(userId).getDocument()

                if let photoURL = doc.data()?["photoURL"] as? String {
                    await MainActor.run {
                        cachedPhotoURL = photoURL
                    }
                }

                if let nickname = doc.data()?["nickname"] as? String, !nickname.isEmpty {
                    await MainActor.run {
                        cachedDisplayName = nickname
                    }
                } else if cachedDisplayName.isEmpty {
                    // Firestore 沒有暱稱且本地也沒快取，才用 email 前綴
                    await MainActor.run {
                        if let email = authService.currentUser?.email {
                            cachedDisplayName = email.components(separatedBy: "@").first ?? email
                        }
                    }
                }
            } catch {
                print("[Settings] Failed to load display name: \(error)")
                // 載入失敗且本地沒快取時，才用 email 前綴
                await MainActor.run {
                    if cachedDisplayName.isEmpty {
                        if let email = authService.currentUser?.email {
                            cachedDisplayName = email.components(separatedBy: "@").first ?? email
                        }
                    }
                }
            }
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openFeedbackEmail() {
        // 系統信息
        let systemInfo = """


        ---
        \(String(localized: "email.systemInfo")):
        App: \(AppConfiguration.appName)
        Version: \(AppConfiguration.fullVersionString)
        iOS: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model) (\(UIDevice.current.name))
        Language: \(Locale.preferredLanguages.first ?? "Unknown")
        """

        let subject = String(format: String(localized: "email.feedbackSubject"), AppConfiguration.appName)
        let body = systemInfo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        guard let url = URL(string: "mailto:\(AppConfiguration.feedbackEmail)?subject=\(subjectEncoded)&body=\(body)") else {
            showFeedbackError = true
            return
        }

        UIApplication.shared.open(url) { success in
            if !success {
                showFeedbackError = true
            }
        }
    }

    private func openPrivacyPolicy() {
        if let url = URL(string: "https://ripe-cereal-4f9.notion.site/Privacy-Policy-302341fcbfde81d589a2e4ba6713b911") {
            safariURL = IdentifiableURL(url: url)
        }
    }

    private func clearAllData() {
        do {
            // 1. 刪除所有包裹（cascade 會自動刪除 TrackingEvent）
            let packageDescriptor = FetchDescriptor<Package>()
            let allPackages = try modelContext.fetch(packageDescriptor)

            // 擷取 ID 用於 Firestore 刪除
            let packageIds = allPackages.map { $0.id }

            for package in allPackages {
                modelContext.delete(package)
            }

            try modelContext.save()

            // 2. 從 Firestore 刪除所有包裹
            for id in packageIds {
                FirebaseSyncService.shared.deletePackage(id)
            }

            // 4. 重置初次同步標記（下次登入時重新同步）
            if let uid = authService.currentUser?.uid {
                UserDefaults.standard.removeObject(forKey: "hasPerformedInitialSync_\(uid)")
            }

            // 5. 取消所有通知
            NotificationService.shared.cancelAllNotifications()

            // 7. 不清除用戶偏好（保留 refreshInterval, selectedTheme, 通知設定）

            // 8. 顯示成功訊息
            showClearDataSuccess = true

        } catch {
            print("Clear all data failed: \(error)")
        }
    }

    private func checkNotificationPermission() {
        Task {
            let status = await NotificationService.shared.getAuthorizationStatus()
            if status == .denied && notificationsEnabled {
                showNotificationDeniedAlert = true
            }
        }
    }

    // Notification settings are now per-device, synced via FirebasePushService.syncDeviceNotificationSettings()
}

// MARK: - Previews

#Preview {
    SettingsView()
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
