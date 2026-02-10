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

    @Query private var linkedAccounts: [LinkedEmailAccount]
    @Query private var existingPackages: [Package]

    @StateObject private var gmailAuthManager = GmailAuthManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var authService = FirebaseAuthService.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    // 通知設定（持久化到 UserDefaults，並同步到 Firestore）
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("arrivalNotificationEnabled") private var arrivalNotificationEnabled = false
    @AppStorage("shippedNotificationEnabled") private var shippedNotificationEnabled = false
    @AppStorage("pickupReminderEnabled") private var pickupReminderEnabled = false

    @State private var showClearDataConfirmation = false
    @State private var showClearDataSuccess = false
    @State private var showNotificationDeniedAlert = false
    @State private var showFeedbackError = false
    @State private var showPaywall = false
    @State private var showAccountDetail = false
    @State private var safariURL: IdentifiableURL?
    @State private var cachedDisplayName: String? = nil
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

                    // 資料管理
                    dataManagementSection

                    // 關於區塊
                    aboutSection

                    #if DEBUG
                    // 開發者選項（僅 DEBUG 模式）
                    developerSection
                    #endif
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
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showAccountDetail) {
                AccountDetailView()
            }
            .onAppear {
                checkNotificationPermission()
                loadDisplayName()
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
                        syncNotificationSettingsToFirestore()
                    }
                } else if !newValue && oldValue {
                    // 用戶關閉通知，取消所有通知
                    NotificationService.shared.cancelAllNotifications()
                    syncNotificationSettingsToFirestore()
                }
            }
        }
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
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(.systemGray3))

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
                    Text(subscriptionManager.isPro
                         ? String(localized: "settings.subscription.pro")
                         : String(localized: "settings.subscription.free"))
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
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.yellow)
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
    }

    /// 顯示名稱（優先順序：快取 > email username > 未知）
    private var displayName: String {
        if let cached = cachedDisplayName, !cached.isEmpty {
            return cached
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

    /// 計算活躍包裹數量
    private var activePackageCount: Int {
        existingPackages.filter { !$0.isArchived }.count
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
                    .background(Color.cardBackground)
                
                // 開發者
                settingsRow(
                    icon: "person.fill",
                    iconColor: .white,
                    title: String(localized: "settings.developer"),
                    value: AppConfiguration.developerName
                )

                Divider()
                    .background(Color.cardBackground)

                // 給予評分
                Button {
                    requestReview()
                } label: {
                    settingsRowButton(
                        icon: "star.fill",
                        iconColor: .white,
                        title: String(localized: "settings.rateApp")
                    )
                }

                Divider()
                    .background(Color.cardBackground)

                // 回報問題
                Button {
                    openFeedbackEmail()
                } label: {
                    settingsRowButton(
                        icon: "envelope.fill",
                        iconColor: .white,
                        title: String(localized: "settings.reportIssue")
                    )
                }
                
                Divider()
                    .background(Color.cardBackground)
                
                // 隱私政策
                Button {
                    openPrivacyPolicy()
                } label: {
                    settingsRowButton(
                        icon: "hand.raised.fill",
                        iconColor: .white,
                        title: String(localized: "settings.privacyPolicy")
                    )
                }
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
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
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                        .frame(width: 28)

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
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 28)
                        
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
                
                // 語言設定
                Button {
                    openAppSettings()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 28)
                        
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

                // 隱藏已取貨包裹
                settingsToggleRow(
                    icon: "eye.slash.fill",
                    iconColor: .white,
                    title: String(localized: "settings.hideDelivered"),
                    isOn: $hideDeliveredPackages
                )
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
                    iconColor: .white,
                    title: String(localized: "settings.pushNotification"),
                    isOn: $notificationsEnabled
                )

                Divider()
                    .background(Color.cardBackground)

                // 推播設定
                NavigationLink(destination: NotificationSettingsView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 28)

                        Text(String(localized: "settings.notificationSettings"))
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.gray)
                    }
                    .padding(16)
                }
                .tint(Color.gray)
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
                        Image(systemName: "trash.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.red)
                            .frame(width: 28)
                        
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
    
    private func settingsRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            
            Text(title)
                .foregroundStyle(.white)
            
            Spacer()
            
            Text(value)
                .foregroundStyle(Color.appAccent)
        }
        .padding(16)
    }
    
    private func settingsRowButton(icon: String, iconColor: Color, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            
            Text(title)
                .foregroundStyle(.white)
            
            Spacer()
        }
        .padding(16)
    }
    
    private func settingsToggleRow(icon: String, iconColor: Color, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            
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

    /// 從 Firestore 載入顯示名稱
    private func loadDisplayName() {
        guard let userId = authService.currentUser?.uid else {
            // 沒有登入，使用預設值
            if cachedDisplayName == nil {
                if let email = authService.currentUser?.email {
                    cachedDisplayName = email.components(separatedBy: "@").first ?? email
                }
            }
            return
        }

        let db = Firestore.firestore()
        Task {
            do {
                let doc = try await db.collection("users").document(userId).getDocument()

                if let nickname = doc.data()?["nickname"] as? String, !nickname.isEmpty {
                    await MainActor.run {
                        cachedDisplayName = nickname
                    }
                } else {
                    // 沒有暱稱，使用 email 前綴作為預設值
                    await MainActor.run {
                        if cachedDisplayName == nil {
                            if let email = authService.currentUser?.email {
                                cachedDisplayName = email.components(separatedBy: "@").first ?? email
                            }
                        }
                    }
                }
            } catch {
                print("[Settings] Failed to load display name: \(error)")
                // 載入失敗時使用預設值
                await MainActor.run {
                    if cachedDisplayName == nil {
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

            // 2. 刪除所有 LinkedEmailAccount
            for account in linkedAccounts {
                modelContext.delete(account)
            }

            try modelContext.save()

            // 3. 從 Firestore 刪除所有包裹
            for id in packageIds {
                FirebaseSyncService.shared.deletePackage(id)
            }

            // 4. 重置初次同步標記（下次登入時重新同步）
            if let uid = authService.currentUser?.uid {
                UserDefaults.standard.removeObject(forKey: "hasPerformedInitialSync_\(uid)")
            }

            // 5. Gmail 登出
            gmailAuthManager.signOut()

            // 6. 取消所有通知
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

    /// 將通知設定同步到 Firestore（fire-and-forget）
    private func syncNotificationSettingsToFirestore() {
        guard let userId = authService.currentUser?.uid else { return }

        let db = Firestore.firestore()
        let settings: [String: Any] = [
            "notificationSettings": [
                "enabled": notificationsEnabled,
                "arrivalNotification": arrivalNotificationEnabled,
                "shippedNotification": shippedNotificationEnabled,
                "pickupReminder": pickupReminderEnabled
            ]
        ]

        Task {
            do {
                try await db.collection("users").document(userId).setData(settings, merge: true)
                print("[Settings] Notification settings synced to Firestore")
            } catch {
                print("[Settings] Failed to sync notification settings: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Previews

#Preview {
    SettingsView()
        .modelContainer(for: [Package.self, TrackingEvent.self, LinkedEmailAccount.self], inMemory: true)
}
