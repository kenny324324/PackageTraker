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

    @StateObject private var gmailAuthManager = GmailAuthManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var authService = FirebaseAuthService.shared

    // 通知設定（持久化到 UserDefaults，並同步到 Firestore）
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("arrivalNotificationEnabled") private var arrivalNotificationEnabled = false
    @AppStorage("shippedNotificationEnabled") private var shippedNotificationEnabled = false
    @AppStorage("pickupReminderEnabled") private var pickupReminderEnabled = false

    @State private var showClearDataConfirmation = false
    @State private var showClearDataSuccess = false
    @State private var showNotificationDeniedAlert = false
    @State private var showFeedbackError = false
    @State private var showSignOutAlert = false
    @State private var safariURL: IdentifiableURL?
    @State private var cachedEmail: String? = nil // 快取 email，登出轉場時不消失
    @AppStorage("refreshInterval") private var refreshInterval: RefreshInterval = .thirtyMinutes
    @AppStorage("hideDeliveredPackages") private var hideDeliveredPackages = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 帳號設定
                    accountSection

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
            .alert(String(localized: "settings.signOut.confirmTitle"), isPresented: $showSignOutAlert) {
                Button(String(localized: "common.cancel"), role: .cancel) {}
                Button(String(localized: "settings.signOut"), role: .destructive) {
                    signOut()
                }
            } message: {
                Text(String(localized: "settings.signOut.confirmMessage"))
            }
            .onAppear {
                checkNotificationPermission()
                // 快取 email，登出轉場時保持顯示
                if cachedEmail == nil {
                    cachedEmail = authService.currentUser?.email
                }
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
            .onChange(of: arrivalNotificationEnabled) { _, _ in
                syncNotificationSettingsToFirestore()
            }
            .onChange(of: shippedNotificationEnabled) { _, _ in
                syncNotificationSettingsToFirestore()
            }
            .onChange(of: pickupReminderEnabled) { _, _ in
                syncNotificationSettingsToFirestore()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.account"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                // Apple ID 顯示
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "settings.appleId"))
                            .foregroundStyle(.white)
                            .font(.body)

                        if let email = cachedEmail ?? authService.currentUser?.email {
                            Text(email)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Spacer()
                }
                .padding(16)

                Divider()
                    .background(Color.cardBackground)

                // 登出按鈕
                Button {
                    showSignOutAlert = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 18))
                            .foregroundStyle(.red)
                            .frame(width: 28)

                        Text(String(localized: "settings.signOut"))
                            .foregroundStyle(.red)

                        Spacer()
                    }
                    .padding(16)
                }
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
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
            .clipShape(RoundedRectangle(cornerRadius: 16))
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
            .clipShape(RoundedRectangle(cornerRadius: 16))

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
            .clipShape(RoundedRectangle(cornerRadius: 16))

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
                settingsToggleRow(
                    icon: "bell.fill",
                    iconColor: .white,
                    title: String(localized: "settings.pushNotification"),
                    isOn: $notificationsEnabled
                )

                Divider()
                    .background(Color.cardBackground)

                settingsToggleRow(
                    icon: "shippingbox.fill",
                    iconColor: .white,
                    title: String(localized: "settings.arrivalNotification"),
                    isOn: $arrivalNotificationEnabled
                )

                Divider()
                    .background(Color.cardBackground)

                settingsToggleRow(
                    icon: "truck.box.fill",
                    iconColor: .white,
                    title: String(localized: "settings.shippedNotification"),
                    isOn: $shippedNotificationEnabled
                )

                Divider()
                    .background(Color.cardBackground)

                settingsToggleRow(
                    icon: "clock.fill",
                    iconColor: .white,
                    title: String(localized: "settings.pickupReminder"),
                    isOn: $pickupReminderEnabled
                )
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))

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
            .clipShape(RoundedRectangle(cornerRadius: 16))
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

    private func signOut() {
        // 清除 FCM Token（在 signOut 前，還能取得 userId）
        Task {
            await FirebasePushService.shared.clearToken()
        }

        do {
            try authService.signOut()
        } catch {
            print("Sign out failed: \(error)")
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
