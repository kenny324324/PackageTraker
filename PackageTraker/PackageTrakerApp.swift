//
//  PackageTrakerApp.swift
//  PackageTraker
//
//  Created by Kenny's Macbook on 2026/2/2.
//

import SwiftUI
import SwiftData
import StoreKit
import Combine
import BackgroundTasks
import UserNotifications
import WidgetKit
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging
import FirebaseCrashlytics
import FirebaseAnalytics

/// App 啟動流程狀態
enum AppFlow: Equatable {
    case signIn     // 未登入：顯示 SignInView
    case coldStart  // 已登入冷啟動：SplashView（箱子掉落 + 進度條）
    case main       // 主畫面
}

@main
struct PackageTrakerApp: App {

    // APNs Token 轉發給 FCM
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // 背景任務識別碼
    static let emailSyncTaskIdentifier = "com.packagetraker.emailsync"

    // SwiftData Container（登出時需要存取 mainContext 清除本地資料）
    private let sharedModelContainer: ModelContainer = {
        let schema = Schema([Package.self, TrackingEvent.self, LinkedEmailAccount.self, SavedPickupLocation.self])
        return try! ModelContainer(for: schema)
    }()

    // App 流程狀態（根據初始認證狀態決定）
    @State private var appFlow: AppFlow

    // 共享的刷新服務
    @State private var refreshService = PackageRefreshService()

    // Tab 選擇（進入主畫面時重設為首頁）
    @State private var selectedTab = 0

    // Deep Link：推播點擊後待導航的包裹 ID
    @State private var pendingPackageId: UUID?

    // Widget Quick Add：從桌面快速新增包裹
    @State private var showAddPackage = false

    // 邀請碼 Deep Link：待套用的推薦碼
    @State private var pendingReferralCode: String?
    // 分享追蹤 Deep Link：待帶入的物流商 + 單號
    @State private var pendingTrackCarrier: String?
    @State private var pendingTrackNumber: String?
    // 邀請碼套用結果
    @State private var showReferralResult = false
    @State private var referralResultMessage = ""
    @State private var referralResultIsError = false
    // 試用到期 Paywall
    @State private var showReferralTrialExpiredPaywall = false

    // 強制更新狀態
    @State private var forceUpdateURL: String?

    // What's New
    @State private var whatsNewData: WhatsNewData?

    // Scene phase（用於清除 badge）
    @Environment(\.scenePhase) private var scenePhase

    // 軟 Paywall
    @State private var showSoftPaywall = false
    @State private var showSoftPaywallFullPaywall = false
    @State private var showPromoSheet = false

    // Firebase 認證服務
    @StateObject private var authService = FirebaseAuthService.shared

    // 訂閱管理器
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    init() {
        // 推播通知預設全開啟（首次安裝時 UserDefaults 尚無值，register 提供預設）
        UserDefaults.standard.register(defaults: [
            "notificationsEnabled": true,
            "arrivalNotificationEnabled": true,
            "shippedNotificationEnabled": true,
            "pickupReminderEnabled": true
        ])

        // 記錄首次安裝日期（用於軟 Paywall 觸發條件）
        if UserDefaults.standard.object(forKey: "appFirstLaunchDate") == nil {
            UserDefaults.standard.set(Date(), forKey: "appFirstLaunchDate")
        }

        // 初始化 Firebase
        FirebaseApp.configure()

        // 啟用 Crashlytics
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)

        // 設置通知中心代理
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // 初始化 FCM 推播服務（設定 Messaging delegate）
        _ = FirebasePushService.shared

        // 根據初始認證狀態決定流程
        // Auth.auth().currentUser 在 configure() 後可同步取得
        if Auth.auth().currentUser != nil {
            _appFlow = State(initialValue: .coldStart)
        } else {
            _appFlow = State(initialValue: .signIn)
        }

        // 註冊背景任務（郵件同步功能暫時停用）
        if FeatureFlags.emailAutoImportEnabled {
            registerBackgroundTasks()
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // 主畫面始終存在底層（已完成佈局，避免 TabView/NavigationStack 插入時的內部動畫）
                MainTabView(selectedTab: $selectedTab, pendingPackageId: $pendingPackageId, showAddPackage: $showAddPackage, prefillCarrier: $pendingTrackCarrier, prefillTrackingNumber: $pendingTrackNumber)
                    .environment(refreshService)
                    .onOpenURL { url in
                        handleIncomingURL(url)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .didTapPackageNotification)) { notification in
                        guard let packageId = notification.userInfo?["packageId"] as? UUID else { return }
                        selectedTab = 0
                        pendingPackageId = packageId
                    }
                    .allowsHitTesting(appFlow == .main)

                // 登入覆蓋層
                if appFlow == .signIn {
                    SignInView(refreshService: refreshService) {
                        selectedTab = 0 // 確保回到包裹列表
                        // 進入主畫面時震動回饋
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        withAnimation(.easeOut(duration: 0.4)) {
                            appFlow = .main
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }

                // 強制更新覆蓋層
                if let storeURL = forceUpdateURL {
                    ForceUpdateView(storeURL: storeURL)
                        .transition(.opacity)
                        .zIndex(2)
                }

                // 冷啟動覆蓋層
                if appFlow == .coldStart {
                    SplashView(refreshService: refreshService) {
                        selectedTab = 0
                        // 進入主畫面時震動回饋
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        withAnimation(.easeOut(duration: 0.4)) {
                            appFlow = .main
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .overlay(alignment: .top) {
                if appFlow == .main && !NetworkMonitor.shared.isConnected {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                            .font(.caption2)
                        Text(String(localized: "network.offline"))
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.85), in: Capsule())
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: NetworkMonitor.shared.isConnected)
                }
            }
            .sheet(item: $whatsNewData) { data in
                WhatsNewSheet(data: data) {
                    checkSoftPaywall()
                }
            }
            .sheet(isPresented: $showSoftPaywall) {
                SoftPaywallSheet {
                    showSoftPaywallFullPaywall = true
                }
            }
            .sheet(isPresented: $showPromoSheet) {
                PromoSheet {
                    showSoftPaywallFullPaywall = true
                }
            }
            .fullScreenCover(isPresented: $showSoftPaywallFullPaywall) {
                PaywallView()
            }
            .fullScreenCover(isPresented: $showReferralTrialExpiredPaywall) {
                PaywallView(trigger: .referralTrialExpired)
            }
            .alert(String(localized: "referral.notice"), isPresented: $showReferralResult) {
                Button(String(localized: "common.ok")) { }
            } message: {
                Text(referralResultMessage)
            }
            .animation(.easeOut(duration: 0.4), value: appFlow)
            .preferredColorScheme(.dark)
            .task {
                let result = await ForceUpdateService.shared.checkForUpdate()
                if case .forceUpdate(let url) = result {
                    forceUpdateURL = url
                }
                // 啟動時同步訂閱層級到 Widget（確保 Widget 能讀取到正確狀態，含試用期）
                WidgetDataService.shared.updateSubscriptionTier(subscriptionManager.isPro ? .pro : .free)

                // 載入邀請碼資料
                if FeatureFlags.referralEnabled {
                    await ReferralService.shared.loadReferralData()
                }
            }
            .onChange(of: subscriptionManager.currentTier) { _, newTier in
                if newTier == .free {
                    ThemeManager.shared.resetToDefaultIfNeeded()
                }
                // 同步訂閱層級到 Widget（含試用期）
                WidgetDataService.shared.updateSubscriptionTier(subscriptionManager.isPro ? .pro : .free)
                WidgetCenter.shared.reloadAllTimelines()
            }
            .onChange(of: appFlow) { _, newFlow in
                guard newFlow == .main else { return }
                checkWhatsNewThenPaywall()
                checkReferralTrialExpiry()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    // App 回到前景時清除 badge 紅點
                    UNUserNotificationCenter.current().setBadgeCount(0)
                }
            }
            .onChange(of: authService.isAuthenticated) { oldValue, newValue in
                // 登出處理（登入由 SignInView 內部處理）
                if oldValue && !newValue {
                    print("[App] 🔴 Sign-out detected, clearing local data...")
                    // 停止 Firestore 即時監聽器
                    FirebaseSyncService.shared.stopListening()
                    // 清除本地 SwiftData 資料（防止帳號切換時殘留舊資料）
                    FirebaseSyncService.shared.clearLocalData(modelContext: sharedModelContainer.mainContext)
                    // 清除邀請碼快取
                    ReferralService.shared.clearCache()
                    // 清除 Widget 資料
                    WidgetDataService.shared.updateWidgetData(packages: [])
                    WidgetCenter.shared.reloadAllTimelines()
                    withAnimation(.easeOut(duration: 0.4)) {
                        selectedTab = 0 // 重置 tab
                        appFlow = .signIn
                    }
                }
                // 登入成功：註冊 FCM 推播 + 設定監控 user ID
                if !oldValue && newValue {
                    if let uid = Auth.auth().currentUser?.uid {
                        Crashlytics.crashlytics().setUserID(uid)
                        Analytics.setUserID(uid)
                    }
                    Task {
                        await FirebasePushService.shared.registerForPushNotifications()

                        // 登入後載入邀請碼資料 + 套用待處理的邀請碼
                        if FeatureFlags.referralEnabled {
                            await ReferralService.shared.loadReferralData()
                            if let code = pendingReferralCode {
                                pendingReferralCode = nil
                                applyReferralCode(code)
                            }
                        }
                    }
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - What's New

    /// 先檢查 What's New，再走軟 Paywall 流程
    private func checkWhatsNewThenPaywall() {
        Task {
            if let data = await WhatsNewService.shared.checkWhatsNew() {
                try? await Task.sleep(for: .seconds(0.5))
                await MainActor.run {
                    whatsNewData = data
                }
                // checkSoftPaywall() 在 WhatsNewSheet onDismiss 中呼叫
            } else {
                checkSoftPaywall()
            }
        }
    }

    // MARK: - Soft Paywall

    /// 檢查是否該顯示限時優惠或軟 Paywall
    private func checkSoftPaywall() {
        guard !subscriptionManager.isPro else { return }

        // 優先顯示限時優惠（每次啟動都彈）
        if LaunchPromoManager.shared.isPromoActive {
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    showPromoSheet = true
                }
            }
            return
        }

        // 優惠不在進行中 → 走軟 Paywall 邏輯（只彈一次）
        guard !UserDefaults.standard.bool(forKey: "hasSeenSoftPaywall") else { return }

        let daysSinceInstall: Int = {
            guard let firstLaunch = UserDefaults.standard.object(forKey: "appFirstLaunchDate") as? Date else { return 0 }
            return Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
        }()
        let totalAdded = UserDefaults.standard.integer(forKey: "totalPackagesAdded")

        guard daysSinceInstall >= 3 || totalAdded >= 3 else { return }

        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                showSoftPaywall = true
                UserDefaults.standard.set(true, forKey: "hasSeenSoftPaywall")
            }
        }
    }

    // MARK: - Referral

    /// 套用邀請碼並顯示結果
    private func applyReferralCode(_ code: String) {
        Task {
            do {
                try await ReferralService.shared.applyReferralCode(code)
                referralResultMessage = String(localized: "referral.codeBound")
                referralResultIsError = false
            } catch {
                referralResultMessage = error.localizedDescription
                referralResultIsError = true
            }
            showReferralResult = true
        }
    }

    /// 檢查邀請試用是否剛到期（過去 24 小時內）
    private func checkReferralTrialExpiry() {
        guard FeatureFlags.referralEnabled,
              !subscriptionManager.isPro,
              let endDate = ReferralService.shared.referralTrialEndDate else { return }

        let hoursSinceExpiry = Date().timeIntervalSince(endDate) / 3600
        guard hoursSinceExpiry > 0 && hoursSinceExpiry < 24 else { return }

        // 避免重複彈出
        let lastShownKey = "referralTrialExpiredPaywallLastShown"
        if let lastShown = UserDefaults.standard.object(forKey: lastShownKey) as? Date,
           Date().timeIntervalSince(lastShown) < 86400 { return }

        UserDefaults.standard.set(Date(), forKey: lastShownKey)

        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                showReferralTrialExpiredPaywall = true
            }
        }
    }

    // MARK: - URL Handling

    private func handleIncomingURL(_ url: URL) {
        // 處理 Widget Quick Add: packagetraker://addPackage
        if url.scheme == "packagetraker",
           url.host == "addPackage" {
            selectedTab = 0
            showAddPackage = true
            return
        }

        // 處理 Widget Deep Link: packagetraker://package/{uuid}
        if url.scheme == "packagetraker",
           url.host == "package",
           let uuidString = url.pathComponents.last,
           let packageId = UUID(uuidString: uuidString) {
            selectedTab = 0
            pendingPackageId = packageId
            return
        }

        // 處理邀請碼 Deep Link: packagetraker://invite/{code}
        if url.scheme == "packagetraker",
           url.host == "invite",
           let code = url.pathComponents.dropFirst().first, // dropFirst 跳過 "/"
           !code.isEmpty {
            if authService.isAuthenticated {
                applyReferralCode(code)
            } else {
                pendingReferralCode = code
            }
            return
        }

        // 處理分享追蹤 Deep Link: packagetraker://track/{carrier}/{trackingNumber}
        if url.scheme == "packagetraker",
           url.host == "track" {
            let components = url.pathComponents.dropFirst() // 跳過 "/"
            if components.count >= 2 {
                let carrier = String(components[components.startIndex])
                let trackingNumber = String(components[components.index(after: components.startIndex)])
                pendingTrackCarrier = carrier
                pendingTrackNumber = trackingNumber
                selectedTab = 0
                showAddPackage = true
            }
            return
        }

        // 處理 Google OAuth 回調
        if url.scheme?.contains("googleusercontent") == true {
            _ = GmailAuthManager.shared.handleURL(url)
        }
    }

    // MARK: - Background Tasks

    private func registerBackgroundTasks() {
        // 註冊郵件同步背景任務
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.emailSyncTaskIdentifier,
            using: nil
        ) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else { return }
            self.handleEmailSyncTask(task: appRefreshTask)
        }
    }

    private func handleEmailSyncTask(task: BGAppRefreshTask) {
        // 排程下次任務
        scheduleEmailSyncTask()

        // 建立同步任務
        let syncTask = Task {
            await performEmailSync()
        }

        // 設定過期處理
        task.expirationHandler = {
            syncTask.cancel()
        }

        // 等待任務完成
        Task {
            _ = await syncTask.result
            task.setTaskCompleted(success: true)
        }
    }

    private func performEmailSync() async {
        // 檢查是否已登入
        guard GmailAuthManager.shared.isSignedIn else { return }

        let gmailService = GmailService()
        let emailParser = TaiwaneseEmailParser.shared

        do {
            // 取得物流相關郵件
            let messages = try await gmailService.fetchTrackingEmails(maxResults: 20)

            // 解析郵件
            let results = emailParser.parseEmails(messages)

            // 這裡應該將結果儲存到 SwiftData
            // 但背景任務中存取 ModelContext 需要特殊處理
            // 實際實作時需要使用 ModelContainer 的背景 context

            print("背景同步完成：解析了 \(results.count) 封郵件")
        } catch {
            print("背景同步失敗：\(error.localizedDescription)")
        }
    }

    /// 排程郵件同步背景任務
    static func scheduleEmailSyncTask() {
        let request = BGAppRefreshTaskRequest(identifier: emailSyncTaskIdentifier)
        // 最早在 15 分鐘後執行
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("無法排程背景任務：\(error.localizedDescription)")
        }
    }
}

// MARK: - Helper Extension

extension PackageTrakerApp {
    private func scheduleEmailSyncTask() {
        Self.scheduleEmailSyncTask()
    }
}

// MARK: - App Delegate (APNs Token)

/// 處理 APNs Device Token，轉發給 Firebase Messaging
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[APNs] Registration failed: \(error.localizedDescription)")
    }
}

// MARK: - Notification Delegate

/// 通知代理：處理前景通知顯示與點擊跳轉
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// 在前景顯示通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 在前景也顯示通知（badge 不顯示，因為使用者正在使用 App）
        completionHandler([.banner, .sound])

        // 前景收到通知時立即清除 badge
        clearBadge()
    }

    /// 點擊通知後跳轉到對應包裹
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let packageIdString = userInfo["packageId"] as? String,
           let packageId = UUID(uuidString: packageIdString) {
            NotificationCenter.default.post(
                name: .didTapPackageNotification,
                object: nil,
                userInfo: ["packageId": packageId]
            )
        }

        // 點擊通知進入 App 時清除 badge
        clearBadge()

        completionHandler()
    }

    /// 清除 App 圖示上的 badge 紅點
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// 推播通知被點擊，需跳轉到包裹詳情
    static let didTapPackageNotification = Notification.Name("didTapPackageNotification")
}
