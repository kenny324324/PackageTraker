//
//  SignInView.swift
//  PackageTraker
//
//  Apple Sign In 登入畫面
//

import SwiftUI
import SwiftData
import AuthenticationServices
import FirebaseAuth

/// 登入畫面：使用 Apple Sign In 登入
struct SignInView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var authService = FirebaseAuthService.shared

    var refreshService: PackageRefreshService
    var onLoadingComplete: () -> Void

    @State private var showError = false
    @State private var errorMessage = ""

    // 箱子掉落動畫相關狀態
    @State private var boxOffset: CGFloat = -400 // 從畫面上方開始
    @State private var boxRotation: Double = -20 // 初始傾斜
    @State private var boxSquash: CGFloat = 1.0 // 壓扁效果
    @State private var contentOpacity: Double = 0

    // 載入進度相關狀態
    @State private var showProgress = false
    @State private var progress: Double = 0
    @State private var isSyncing = false
    @State private var safariURL: IdentifiableURL?

    var body: some View {
        ZStack {
            // 背景底色（與設定頁一致）
            Color.adaptiveAppBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo + 標題
                VStack(spacing: 24) {
                    // 箱子 - 從天而降動畫（無陰影版本）
                    Image("SplashIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(boxRotation))
                        .scaleEffect(x: 1.0 / boxSquash, y: boxSquash, anchor: .bottom) // 落地壓扁效果
                        .offset(y: boxOffset)

                    VStack(spacing: 12) {
                        Text(AppConfiguration.appName)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)

                        Text(String(localized: "auth.signIn.subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .opacity(contentOpacity)
                }

                Spacer()

                // 底部區塊（登入按鈕 或 進度條）
                if showProgress {
                    // 載入進度條
                    VStack(spacing: 16) {
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .appAccent))
                            .scaleEffect(x: 1, y: 2, anchor: .center)
                            .frame(width: 200)

                        Text(loadingText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: loadingText)
                    }
                    .padding(.bottom, 80)
                    .transition(.opacity)
                } else {
                    // 登入按鈕區塊
                    VStack(spacing: 20) {
                        // Apple Sign In 按鈕（膠囊狀）
                        SignInWithAppleButton(
                            .signIn,
                            onRequest: configureAppleSignIn,
                            onCompletion: handleAppleSignInResult
                        )
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 50)
                        .clipShape(Capsule())

                        // 服務條款與隱私政策（兩行，可點擊連結）
                        VStack(spacing: 4) {
                            Text(String(localized: "auth.signIn.termsLine1"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            HStack(spacing: 4) {
                                Text(String(localized: "auth.signIn.termsLink"))
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .underline()
                                    .onTapGesture {
                                        openTermsOfService()
                                    }

                                Text(String(localized: "auth.signIn.and"))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)

                                Text(String(localized: "auth.signIn.privacyLink"))
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .underline()
                                    .onTapGesture {
                                        openPrivacyPolicy()
                                    }
                            }
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                    .opacity(contentOpacity)
                    .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $safariURL) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        .alert(String(localized: "auth.error.title"), isPresented: $showError) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await startAnimation()
        }
        .onChange(of: authService.isAuthenticated) { oldValue, newValue in
            // 登入成功
            if !oldValue && newValue {
                Task {
                    await showLoadingAndLoadData()
                }
            }
        }
        .onChange(of: refreshService.batchProgress) { _, newValue in
            // 將 API 進度（0~1）映射到進度條的 0.3~0.9 區間
            let mappedProgress = 0.3 + (newValue * 0.6)
            withAnimation(.linear(duration: 0.1)) {
                progress = min(mappedProgress, 0.9)
            }
        }
    }

    /// 動態載入文字
    private var loadingText: String {
        if isSyncing {
            return String(localized: "splash.syncing")
        } else if progress >= 0.9 {
            return String(localized: "splash.almostDone")
        } else {
            return String(localized: "splash.loading")
        }
    }

    // MARK: - Loading

    /// 顯示進度條並載入資料
    private func showLoadingAndLoadData() async {
        // 隱藏登入按鈕，顯示進度條
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.3)) {
                showProgress = true
            }
        }

        // 開始載入資料
        await loadData()
    }

    private func loadData() async {
        // 帳號切換偵測：若 UID 不同，先清除前一個帳號的本地資料
        if let currentUid = FirebaseAuthService.shared.currentUser?.uid {
            let lastUid = UserDefaults.standard.string(forKey: "lastSignedInUid")
            if let lastUid, lastUid != currentUid {
                print("[SignIn] ⚠️ Account switched (\(lastUid) → \(currentUid)), clearing local data...")
                FirebaseSyncService.shared.clearLocalData(modelContext: modelContext)
                ReferralService.shared.clearCache()
            }
            UserDefaults.standard.set(currentUid, forKey: "lastSignedInUid")
        }

        // 階段 0.5: 下載用戶偏好設定（訂閱層級、通知設定、主題等）
        await FirebaseSyncService.shared.downloadUserPreferences()

        // 階段 0.6: 下載常用取貨地點
        await FirebaseSyncService.shared.downloadSavedLocations(into: modelContext)

        // 階段 1: 從 Firestore 下載雲端包裹（新裝置或其他裝置的變更）
        let downloadCount = await FirebaseSyncService.shared.downloadAllPackages(into: modelContext)
        if downloadCount > 0 {
            print("[SignIn] Downloaded \(downloadCount) packages from cloud")
        }
        await animateProgress(to: 0.15)

        // 階段 2: SwiftData 預載
        await animateProgress(to: 0.3)
        let activePackages = await preloadPackageData()

        // 階段 3: API 刷新（帶 10 秒 timeout）
        if !activePackages.isEmpty {
            isSyncing = true
            await refreshService.refreshAllWithTimeout(
                activePackages,
                in: modelContext,
                timeout: 10.0,
                maxConcurrent: 3
            )
            isSyncing = false
        }
        // 進度由 .onChange(of: refreshService.batchProgress) 驅動

        // 階段 3.5: 啟動即時監聽器
        FirebaseSyncService.shared.startListening(modelContext: modelContext)

        // 階段 3.5b: 補傳本地有但 Firestore 沒有的包裹（背景執行）
        Task { await FirebaseSyncService.shared.uploadMissingPackages(from: modelContext) }

        // 階段 3.5c: 一次性清理歷史重複事件
        Task { await FirebaseSyncService.shared.deduplicateEventsIfNeeded(in: modelContext) }

        // 階段 4: 完成
        await animateProgress(to: 1.0)

        // 短暫延遲後進入主畫面
        try? await Task.sleep(nanoseconds: 200_000_000)

        await MainActor.run {
            onLoadingComplete()
        }
    }

    private func animateProgress(to value: Double) async {
        let steps = 20
        let stepDuration: UInt64 = 15_000_000 // 15ms per step
        let increment = (value - progress) / Double(steps)

        for _ in 0..<steps {
            await MainActor.run {
                withAnimation(.linear(duration: 0.015)) {
                    progress += increment
                }
            }
            try? await Task.sleep(nanoseconds: stepDuration)
        }

        await MainActor.run {
            progress = value
        }
    }

    /// 預載包裹資料，回傳需要 API 刷新的包裹
    private func preloadPackageData() async -> [Package] {
        let descriptor = FetchDescriptor<Package>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )

        do {
            let packages = try modelContext.fetch(descriptor)
            // 回傳未完成的包裹（需要 API 刷新）
            return packages.filter { !$0.status.isCompleted }
        } catch {
            print("預載資料失敗: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Animation

    private func startAnimation() async {
        // 等待一小段時間讓畫面準備好
        try? await Task.sleep(nanoseconds: 100_000_000)

        // 箱子快速掉落（保持傾斜）
        await MainActor.run {
            withAnimation(.easeIn(duration: 0.35)) {
                boxOffset = 0
            }
        }

        try? await Task.sleep(nanoseconds: 350_000_000)

        // 第一次落地：壓扁 + 往外傾斜更多
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.06)) {
                boxSquash = 0.8
                boxRotation = -25
            }
        }

        try? await Task.sleep(nanoseconds: 60_000_000)

        // 第一次彈起
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.2)) {
                boxSquash = 1.0
                boxOffset = -40
                boxRotation = 10 // 往另一邊傾斜
            }
        }

        try? await Task.sleep(nanoseconds: 200_000_000)

        // 第二次落地
        await MainActor.run {
            withAnimation(.easeIn(duration: 0.15)) {
                boxOffset = 0
            }
        }

        try? await Task.sleep(nanoseconds: 150_000_000)

        // 第二次壓扁（較輕微）
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.05)) {
                boxSquash = 0.9
                boxRotation = -5
            }
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        // 最終回正
        await MainActor.run {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                boxSquash = 1.0
                boxRotation = 0
            }
        }

        // 等待回正完成
        try? await Task.sleep(nanoseconds: 400_000_000)

        // 顯示登入內容
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.5)) {
                contentOpacity = 1
            }
        }
    }

    // MARK: - External Links

    private func openTermsOfService() {
        if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
            safariURL = IdentifiableURL(url: url)
        }
    }

    private func openPrivacyPolicy() {
        if let url = URL(string: "https://ripe-cereal-4f9.notion.site/Privacy-Policy-302341fcbfde81d589a2e4ba6713b911") {
            safariURL = IdentifiableURL(url: url)
        }
    }

    // MARK: - Apple Sign In

    private func configureAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        let appleRequest = authService.startSignInWithAppleFlow()
        request.requestedScopes = appleRequest.requestedScopes
        request.nonce = appleRequest.nonce
    }

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                return
            }

            Task {
                do {
                    try await authService.signInWithApple(credential: credential)
                } catch {
                    // 印出完整錯誤資訊以便除錯
                    let nsError = error as NSError
                    print("🔴 Sign In Error: \(nsError)")
                    print("🔴 Error Code: \(nsError.code)")
                    print("🔴 Error Domain: \(nsError.domain)")
                    if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                        print("🔴 Underlying Error: \(underlyingError)")
                        print("🔴 Underlying UserInfo: \(underlyingError.userInfo)")
                    }
                    if let details = nsError.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any] {
                        print("🔴 Firebase Response: \(details)")
                    }

                    // 顯示更詳細的錯誤資訊
                    if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                        errorMessage = "[\(nsError.code)] \(underlyingError.localizedDescription)"
                    } else if let details = nsError.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any],
                              let message = details["message"] as? String {
                        errorMessage = "[\(nsError.code)] \(message)"
                    } else {
                        errorMessage = "[\(nsError.code)] \(error.localizedDescription)"
                    }
                    showError = true
                }
            }

        case .failure(let error):
            // 用戶取消不顯示錯誤
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

#Preview {
    SignInView(refreshService: PackageRefreshService()) {
        print("Loading complete")
    }
    .modelContainer(for: [Package.self, TrackingEvent.self, LinkedEmailAccount.self], inMemory: true)
}
