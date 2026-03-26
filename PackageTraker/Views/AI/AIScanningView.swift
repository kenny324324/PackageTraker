//
//  AIScanningView.swift
//  PackageTraker
//
//  AI 掃描全頁面 — 有機光影球動畫 + 兩階段載入
//

import SwiftUI
import SwiftData

/// AI 掃描全頁面（全高，類似 PackageQueryView 的過場）
struct AIScanningView: View {
    let carrier: Carrier       // 使用者選的物流商
    let image: UIImage
    let onDismiss: () -> Void  // 成功新增後關閉整個流程
    let onCancel: () -> Void   // 取消回到選擇頁

    // 載入狀態
    @State private var loadingStage: ScanStage = .aiRecognition

    enum ScanStage: Equatable {
        case aiRecognition
        case apiVerification
        case complete
    }

    // 結果
    @State private var aiResult: AIVisionResult?
    @State private var apiTrackingResult: TrackingResult?
    @State private var apiRelationId: String?

    // 顯示結果
    @State private var navigateToQuickAdd = false
    @State private var workflowCompleted = false
    @State private var isProcessingWorkflow = false
    @State private var workflowTask: Task<Void, Never>?

    // 錯誤
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isNoTrackingDataError = false
    @State private var isQuotaError = false
    @State private var showManualAdd = false
    @State private var showCancelConfirm = false

    private let trackingManager = TrackingManager()
    private let aiService = AIVisionService.shared

    var body: some View {
        ZStack {
            // 背景
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // 有機光影球動畫
                OrganicOrbAnimation(stage: loadingStage)
                    .frame(height: 280)

                Spacer()
                    .frame(height: 40)

                // 階段文字
                VStack(spacing: 10) {
                    Text(stageTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.4), value: loadingStage)

                    Text(stageSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.4), value: loadingStage)
                }

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(String(localized: "common.cancel")) {
                    showCancelConfirm = true
                }
                .foregroundStyle(.white)
            }
        }
        .navigationDestination(isPresented: $navigateToQuickAdd) {
            if let aiResult = aiResult,
               let trackingResult = apiTrackingResult,
               let relationId = apiRelationId {
                AIQuickAddSheet(
                    aiResult: aiResult,
                    trackingResult: trackingResult,
                    relationId: relationId,
                    onDismiss: {
                        navigateToQuickAdd = false
                        onDismiss()
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showManualAdd) {
            if let result = aiResult {
                NavigationStack {
                    PackageQueryView(
                        trackingNumber: result.trackingNumber ?? "",
                        carrier: self.carrier,
                        onComplete: { onDismiss() },
                        popToRoot: { showManualAdd = false }
                    )
                }
            }
        }
        .alert(String(localized: "ai.scanning.cancelConfirmMessage"), isPresented: $showCancelConfirm) {
            Button(String(localized: "common.confirm")) {
                onCancel()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .alert(String(localized: "ai.error.title"), isPresented: $showError) {
            if isNoTrackingDataError {
                Button(String(localized: "common.ok")) {
                    onDismiss()
                }
            } else if isQuotaError {
                // Quota exceeded — 重試沒用，讓使用者稍後再試
                Button(String(localized: "common.ok")) {
                    onCancel()
                }
            } else {
                Button(String(localized: "addMethod.retry")) {
                    workflowCompleted = false
                    Task { await processAIWorkflow() }
                }
                if let trackingNumber = aiResult?.trackingNumber,
                   CarrierDetector.isValidFormat(trackingNumber) {
                    Button(String(localized: "addMethod.manualInput")) {
                        showError = false
                        showManualAdd = true
                    }
                }
                Button(String(localized: "common.cancel"), role: .cancel) {
                    onCancel()
                }
            }
        } message: {
            Text(errorMessage)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard workflowTask == nil, !isProcessingWorkflow, !workflowCompleted else { return }
            workflowTask = Task { @MainActor in
                await processAIWorkflow()
            }
        }
    }

    // MARK: - Stage Text

    private var stageTitle: String {
        switch loadingStage {
        case .aiRecognition:
            return String(localized: "addMethod.loading.aiRecognition")
        case .apiVerification:
            return String(localized: "addMethod.loading.apiVerification")
        case .complete:
            return String(localized: "query.found")
        }
    }

    private var stageSubtitle: String {
        switch loadingStage {
        case .aiRecognition:
            return String(localized: "addMethod.loading.aiRecognitionDesc")
        case .apiVerification:
            return String(localized: "addMethod.loading.apiVerificationDesc")
        case .complete:
            return ""
        }
    }

    // MARK: - AI Workflow

    private func processAIWorkflow() async {
        // 防止 .task 重複執行（view lifecycle 可能觸發多次）
        guard !workflowCompleted, !isProcessingWorkflow else {
            print("⚠️ [AIScanningView] processAIWorkflow skipped (completed=\(workflowCompleted), processing=\(isProcessingWorkflow))")
            return
        }

        print("🟢 [AIScanningView] processAIWorkflow 開始")
        isProcessingWorkflow = true
        defer {
            isProcessingWorkflow = false
            print("🔚 [AIScanningView] processAIWorkflow 結束")
        }

        showError = false
        errorMessage = ""
        isNoTrackingDataError = false
        isQuotaError = false

        do {
            // 階段 1：AI 辨識
            loadingStage = .aiRecognition
            AnalyticsService.logAIScanStarted()

            print("📸 [AIScanningView] 開始 AI 辨識...")
            let result = try await analyzeImageWithRetry(image)
            print("✅ [AIScanningView] AI 辨識完成")
            self.aiResult = result

            // 階段 2：API 驗證
            withAnimation { loadingStage = .apiVerification }

            guard let trackingNumber = result.trackingNumber, !trackingNumber.isEmpty else {
                throw TrackingError.invalidTrackingNumber
            }

            // 驗證單號基本格式
            guard CarrierDetector.isValidFormat(trackingNumber) else {
                print("❌ [AIScanningView] 單號格式不正確: \(trackingNumber)")
                throw TrackingError.invalidTrackingNumber
            }

            // 直接用使用者選的 carrier
            let carrier = self.carrier
            print("📋 [AIScanningView] 使用者選擇: \(carrier.displayName)")

            let relationId = try await trackingManager.importPackage(
                number: trackingNumber,
                carrier: carrier
            )
            var trackResult = try await trackingManager.track(
                number: trackingNumber,
                carrier: carrier
            )
            print("✅ [AIScanningView] \(carrier.displayName) 追蹤完成，\(trackResult.events.count) 筆事件")

            // 事件輪詢：若初次無事件，最多再試 5 次
            if trackResult.events.isEmpty {
                for attempt in 1...5 {
                    try await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { break }
                    trackResult = try await trackingManager.track(number: trackingNumber, carrier: carrier)
                    if !trackResult.events.isEmpty {
                        print("✅ 第 \(attempt) 次輪詢取得 \(trackResult.events.count) 筆事件")
                        break
                    }
                }
            }

            // 仍然無事件 → 報錯
            if trackResult.events.isEmpty {
                throw TrackingError.noTrackingData
            }

            self.aiResult = result
            self.apiTrackingResult = trackResult
            self.apiRelationId = relationId

            // 完成
            withAnimation { loadingStage = .complete }
            AnalyticsService.logAIScanCompleted(
                carrier: carrier.displayName,
                hasPickupCode: result.pickupCode != nil
            )

            // 震動回饋
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // 短暫延遲後顯示結果
            try? await Task.sleep(for: .milliseconds(600))
            workflowCompleted = true
            navigateToQuickAdd = true

        } catch is CancellationError {
            print("🚫 [AIScanningView] Task 被取消 (CancellationError)！")
            AnalyticsService.logAIScanFailed(errorType: "cancelled")
            errorMessage = String(localized: "error.networkError")
            showError = true
        } catch let urlError as URLError where urlError.code == .cancelled {
            print("🚫 [AIScanningView] URLSession 被取消 (URLError.cancelled)！")
            AnalyticsService.logAIScanFailed(errorType: "url_cancelled")
            errorMessage = String(localized: "error.networkError")
            showError = true
        } catch {
            print("❌ [AIScanningView] 錯誤: \(error)")
            let errorType: String
            if let aiError = error as? AIVisionError {
                if aiError.isQuotaExceeded {
                    isQuotaError = true
                }
                switch aiError {
                case .dailyLimitReached:
                    errorType = "daily_limit"
                    AnalyticsService.logAIDailyLimitHit(count: 20)
                case .proRequired:
                    errorType = "pro_required"
                default:
                    errorType = "ai_error"
                }
            } else if let trackingError = error as? TrackingError {
                if case .noTrackingData = trackingError {
                    errorType = "no_tracking_data"
                    isNoTrackingDataError = true
                } else {
                    errorType = "tracking_error"
                }
            } else {
                errorType = "unknown"
            }
            AnalyticsService.logAIScanFailed(errorType: errorType)
            errorMessage = friendlyErrorMessage(for: error)
            showError = true
        }
    }

    private func analyzeImageWithRetry(_ image: UIImage, maxAttempts: Int = 2) async throws -> AIVisionResult {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await aiService.analyzePackageImage(image)
            } catch {
                lastError = error

                guard attempt < maxAttempts, shouldRetryAIRequest(after: error) else {
                    throw error
                }

                try? await Task.sleep(for: .milliseconds(450))
            }
        }

        throw lastError ?? AIVisionError.parseError
    }

    private func shouldRetryAIRequest(after error: Error) -> Bool {
        guard let aiError = error as? AIVisionError else { return false }

        switch aiError {
        case .apiError:
            return !aiError.isQuotaExceeded
        case .parseError:
            return true
        case .dailyLimitReached, .proRequired, .subscriptionRequired:
            return false
        default:
            return false
        }
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        if let aiError = error as? AIVisionError {
            if aiError.isQuotaExceeded {
                return String(localized: "ai.error.quotaExceeded")
            }

            switch aiError {
            case .dailyLimitReached:
                return String(localized: "ai.error.dailyLimitReached")
            case .proRequired:
                return String(localized: "ai.error.subscriptionRequired")
            case .apiError:
                return String(localized: "ai.error.serviceUnavailable")
            default:
                return aiError.errorDescription ?? String(localized: "ai.error.serviceUnavailable")
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed:
                return String(localized: "error.networkError")
            default:
                break
            }
        }

        return error.localizedDescription
    }
}

// MARK: - Organic Orb Animation

/// 有機光影球動畫 — 像呼吸一樣的流體光球
struct OrganicOrbAnimation: View {
    let stage: AIScanningView.ScanStage

    // 動畫參數
    @State private var phase: CGFloat = 0
    @State private var breatheScale: CGFloat = 1.0
    @State private var innerRotation: Double = 0
    @State private var outerRotation: Double = 0

    private var primaryColors: [Color] {
        switch stage {
        case .aiRecognition:
            return [
                Color(red: 0.4, green: 0.2, blue: 0.9),
                Color(red: 0.6, green: 0.1, blue: 0.8),
                Color(red: 0.2, green: 0.3, blue: 1.0)
            ]
        case .apiVerification:
            return [
                Color(red: 0.1, green: 0.5, blue: 0.9),
                Color(red: 0.2, green: 0.7, blue: 0.8),
                Color(red: 0.3, green: 0.4, blue: 1.0)
            ]
        case .complete:
            return [
                Color(red: 0.2, green: 0.8, blue: 0.5),
                Color(red: 0.1, green: 0.6, blue: 0.7),
                Color(red: 0.3, green: 0.9, blue: 0.6)
            ]
        }
    }

    var body: some View {
        ZStack {
            // 外層光暈
            ForEach(0..<3, id: \.self) { i in
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                primaryColors[i % primaryColors.count].opacity(0.3),
                                primaryColors[i % primaryColors.count].opacity(0.05),
                                .clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 120
                        )
                    )
                    .frame(width: 200 + CGFloat(i) * 30,
                           height: 180 + CGFloat(i) * 20)
                    .rotationEffect(.degrees(outerRotation + Double(i) * 120))
                    .offset(
                        x: sin(phase + Double(i) * 2.1) * 8,
                        y: cos(phase + Double(i) * 1.7) * 6
                    )
                    .blur(radius: 20 + CGFloat(i) * 5)
                    .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: outerRotation)
                    .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: phase)
            }

            // 中層流體光球
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    primaryColors[i % primaryColors.count].opacity(0.6),
                                    primaryColors[(i + 1) % primaryColors.count].opacity(0.2),
                                    .clear
                                ],
                                center: UnitPoint(
                                    x: 0.5 + sin(phase + Double(i) * 1.5) * 0.2,
                                    y: 0.5 + cos(phase + Double(i) * 1.8) * 0.2
                                ),
                                startRadius: 5,
                                endRadius: 60
                            )
                        )
                        .frame(width: 100, height: 100)
                        .offset(
                            x: sin(phase + Double(i) * 1.6) * 15,
                            y: cos(phase + Double(i) * 2.0) * 12
                        )
                        .blur(radius: 8)
                        .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: phase)
                }
            }
            .scaleEffect(breatheScale)
            .rotationEffect(.degrees(innerRotation))
            .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: breatheScale)
            .animation(.linear(duration: 12).repeatForever(autoreverses: false), value: innerRotation)

            // 核心光點
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.9),
                            .white.opacity(0.4),
                            primaryColors[0].opacity(0.3),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 35
                    )
                )
                .frame(width: 70, height: 70)
                .scaleEffect(breatheScale)
                .blur(radius: 2)
                .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: breatheScale)

            // 只在完成顯示中心圖標，辨識中不顯示星星
            if stage == .complete {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .scaleEffect(breatheScale * 0.9)
                    .shadow(color: .white.opacity(0.5), radius: 8)
                    .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: breatheScale)
            }
        }
        .onAppear {
            startAnimations()
        }
        .onChange(of: stage) { _, _ in
            // 階段切換時加一個彈跳
            breatheScale = 1.15
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                breatheScale = 1.0
            }
        }
    }

    private func startAnimations() {
        // 直接設值，動畫由各元素的 .animation(value:) 驅動，避免 withAnimation 洩漏
        breatheScale = 1.08
        innerRotation = 360
        outerRotation = -360
        phase = .pi * 2
    }
}

// MARK: - Preview

#Preview("AI Scanning") {
    AIScanningView(
        carrier: .shopee,
        image: UIImage(systemName: "photo")!,
        onDismiss: {},
        onCancel: {}
    )
    .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}

#Preview("Orb Animation") {
    ZStack {
        Color.black.ignoresSafeArea()
        OrganicOrbAnimation(stage: .aiRecognition)
            .frame(height: 280)
    }
}
