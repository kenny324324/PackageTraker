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

@main
struct PackageTrakerApp: App {

    // 背景任務識別碼
    static let emailSyncTaskIdentifier = "com.packagetraker.emailsync"
    
    // 控制是否顯示啟動頁
    @State private var showSplash = true

    // 共享的刷新服務
    @State private var refreshService = PackageRefreshService()

    init() {
        // 設置通知中心代理
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // 註冊背景任務（郵件同步功能暫時停用）
        if FeatureFlags.emailAutoImportEnabled {
            registerBackgroundTasks()
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()
                    .environment(refreshService)
                    .onOpenURL { url in
                        // 處理 OAuth 回調 URL
                        handleIncomingURL(url)
                    }

                if showSplash {
                    SplashView(refreshService: refreshService) {
                        withAnimation(.easeOut(duration: 0.4)) {
                            showSplash = false
                        }
                    }
                    .zIndex(1)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.4), value: showSplash)
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
