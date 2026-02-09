//
//  PackageTrakerApp.swift
//  PackageTraker
//
//  Created by Kenny's Macbook on 2026/2/2.
//

import SwiftUI
import SwiftData
import BackgroundTasks
import UserNotifications
import FirebaseCore
import FirebaseAuth

/// App 啟動流程狀態
enum AppFlow: Equatable {
    case signIn     // 未登入：顯示 SignInView
    case coldStart  // 已登入冷啟動：SplashView（箱子掉落 + 進度條）
    case main       // 主畫面
}

@main
struct PackageTrakerApp: App {

    // 背景任務識別碼
    static let emailSyncTaskIdentifier = "com.packagetraker.emailsync"

    // App 流程狀態（根據初始認證狀態決定）
    @State private var appFlow: AppFlow

    // 共享的刷新服務
    @State private var refreshService = PackageRefreshService()

    // Tab 選擇（進入主畫面時重設為首頁）
    @State private var selectedTab = 0

    // Firebase 認證服務
    @StateObject private var authService = FirebaseAuthService.shared

    init() {
        // 初始化 Firebase
        FirebaseApp.configure()

        // 設置通知中心代理
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

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
                MainTabView(selectedTab: $selectedTab)
                    .environment(refreshService)
                    .onOpenURL { url in
                        handleIncomingURL(url)
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
            .animation(.easeOut(duration: 0.4), value: appFlow) // 驅動覆蓋層的淡入淡出轉場
            .preferredColorScheme(.dark)
            .onChange(of: authService.isAuthenticated) { oldValue, newValue in
                // 只處理登出（登入由 SignInView 內部處理）
                if oldValue && !newValue {
                    withAnimation(.easeOut(duration: 0.4)) {
                        selectedTab = 0 // 重置 tab
                        appFlow = .signIn
                    }
                }
            }
        }
        .modelContainer(for: [
            Package.self,
            TrackingEvent.self,
            LinkedEmailAccount.self
        ])
    }

    // MARK: - URL Handling

    private func handleIncomingURL(_ url: URL) {
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

// MARK: - Notification Delegate

/// 通知代理：處理前景通知顯示
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// 在前景顯示通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 在前景也顯示通知
        completionHandler([.banner, .sound])
    }
}
