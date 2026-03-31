//
//  AIScanningView.swift
//  PackageTraker
//
//  AI 掃描全頁面 — 有機光影球動畫 + 兩階段載入
//

import SwiftUI
import SwiftData

// MARK: - ViewModel（導航與結果狀態，避免 view 重建時遺失）
@Observable
final class AIScanningViewModel {
    // 載入狀態
    var loadingStage: AIScanningView.ScanStage = .aiRecognition

    // 結果
    var aiResult: AIVisionResult?
    var apiTrackingResult: TrackingResult?
    var apiRelationId: String?

    // 導航
    var navigateToQuickAdd = false
    var workflowCompleted = false
    var isProcessingWorkflow = false
    var workflowTask: Task<Void, Never>?

    // 錯誤
    var showError = false
    var errorMessage = ""
    var isNoTrackingDataError = false
    var isQuotaError = false
    var showManualAdd = false
    var showCancelConfirm = false
}

/// AI 掃描全頁面（全高，類似 PackageQueryView 的過場）
struct AIScanningView: View {
    let carrier: Carrier       // 使用者選的物流商
    let image: UIImage
    let onDismiss: () -> Void  // 成功新增後關閉整個流程
    let onCancel: () -> Void   // 取消回到選擇頁

    enum ScanStage: Equatable {
        case aiRecognition
        case apiVerification
        case complete
        case failed
    }

    @State private var vm = AIScanningViewModel()

    private let trackingManager = TrackingManager()
    private let aiService = AIVisionService.shared

    var body: some View {
        @Bindable var vm = vm
        ZStack {
            // 背景
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // 有機光影球動畫（阻止 loadingStage 的隱式 layout 動畫）
                OrganicOrbAnimation(stage: vm.loadingStage)
                    .frame(height: 280)
                    .animation(nil, value: vm.loadingStage)

                Spacer()
                    .frame(height: 40)

                // 階段文字
                VStack(spacing: 10) {
                    Text(stageTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.4), value: vm.loadingStage)

                    Text(stageSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.4), value: vm.loadingStage)
                }
                .frame(height: 50)

                Spacer()

                Text(String(localized: "query.doNotLeave"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 16)
                    .opacity(vm.loadingStage == .complete || vm.loadingStage == .failed ? 0 : 1)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(String(localized: "common.cancel")) {
                    vm.showCancelConfirm = true
                }
                .foregroundStyle(.white)
            }
        }
        .navigationDestination(isPresented: $vm.navigateToQuickAdd) {
            if let aiResult = vm.aiResult,
               let trackingResult = vm.apiTrackingResult,
               let relationId = vm.apiRelationId {
                AIQuickAddSheet(
                    aiResult: aiResult,
                    trackingResult: trackingResult,
                    relationId: relationId,
                    onDismiss: {
                        onDismiss()
                    }
                )
            }
        }
        .sheet(isPresented: $vm.showManualAdd) {
            if let result = vm.aiResult {
                NavigationStack {
                    PackageQueryView(
                        trackingNumber: result.trackingNumber ?? "",
                        carrier: self.carrier,
                        onComplete: { onDismiss() },
                        popToRoot: { vm.showManualAdd = false }
                    )
                }
                .interactiveDismissDisabled()
                .preferredColorScheme(.dark)
            }
        }
        .alert(String(localized: "ai.scanning.cancelConfirmMessage"), isPresented: $vm.showCancelConfirm) {
            Button(String(localized: "common.confirm")) {
                onCancel()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .alert(String(localized: "ai.error.title"), isPresented: $vm.showError) {
            if vm.isNoTrackingDataError {
                Button(String(localized: "common.ok")) {
                    onDismiss()
                }
            } else if vm.isQuotaError {
                // Quota exceeded — 重試沒用，讓使用者稍後再試
                Button(String(localized: "common.ok")) {
                    onCancel()
                }
            } else {
                Button(String(localized: "addMethod.retry")) {
                    vm.workflowCompleted = false
                    Task { await processAIWorkflow() }
                }
                if let trackingNumber = vm.aiResult?.trackingNumber,
                   CarrierDetector.isValidFormat(trackingNumber) {
                    Button(String(localized: "addMethod.manualInput")) {
                        vm.showError = false
                        vm.showManualAdd = true
                    }
                }
                Button(String(localized: "common.cancel"), role: .cancel) {
                    onCancel()
                }
            }
        } message: {
            Text(vm.errorMessage)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard vm.workflowTask == nil, !vm.isProcessingWorkflow, !vm.workflowCompleted else { return }
            vm.workflowTask = Task { @MainActor in
                await processAIWorkflow()
            }
        }
    }

    // MARK: - Stage Text

    private var stageTitle: String {
        switch vm.loadingStage {
        case .aiRecognition:
            return String(localized: "addMethod.loading.aiRecognition")
        case .apiVerification:
            return String(localized: "addMethod.loading.apiVerification")
        case .complete:
            return String(localized: "query.found")
        case .failed:
            return String(localized: "ai.error.title")
        }
    }

    private var stageSubtitle: String {
        switch vm.loadingStage {
        case .aiRecognition:
            return String(localized: "addMethod.loading.aiRecognitionDesc")
        case .apiVerification:
            return String(localized: "addMethod.loading.apiVerificationDesc")
        case .complete, .failed:
            return ""
        }
    }

    // MARK: - AI Workflow

    private func processAIWorkflow() async {
        // 防止 .task 重複執行（view lifecycle 可能觸發多次）
        guard !vm.workflowCompleted, !vm.isProcessingWorkflow else {
            print("⚠️ [AIScanningView] processAIWorkflow skipped (completed=\(vm.workflowCompleted), processing=\(vm.isProcessingWorkflow))")
            return
        }

        print("🟢 [AIScanningView] processAIWorkflow 開始")
        vm.isProcessingWorkflow = true
        defer {
            vm.isProcessingWorkflow = false
            print("🔚 [AIScanningView] processAIWorkflow 結束")
        }

        vm.showError = false
        vm.errorMessage = ""
        vm.isNoTrackingDataError = false
        vm.isQuotaError = false

        do {
            // 階段 1：AI 辨識
            vm.loadingStage = .aiRecognition
            AnalyticsService.logAIScanStarted()

            print("📸 [AIScanningView] 開始 AI 辨識...")
            let result = try await analyzeImageWithRetry(image)
            print("✅ [AIScanningView] AI 辨識完成")
            vm.aiResult = result

            // 階段 2：API 驗證
            vm.loadingStage = .apiVerification

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

            vm.aiResult = result
            vm.apiTrackingResult = trackResult
            vm.apiRelationId = relationId

            // 完成
            vm.loadingStage = .complete
            AnalyticsService.logAIScanCompleted(
                carrier: carrier.displayName,
                hasPickupCode: result.pickupCode != nil
            )

            // 震動回饋
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // 短暫延遲後顯示結果
            try? await Task.sleep(for: .milliseconds(600))
            vm.workflowCompleted = true
            vm.navigateToQuickAdd = true

        } catch is CancellationError {
            print("🚫 [AIScanningView] Task 被取消 (CancellationError)！")
            AnalyticsService.logAIScanFailed(errorType: "cancelled")
            vm.loadingStage = .failed
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            vm.errorMessage = String(localized: "error.networkError")
            vm.showError = true
        } catch let urlError as URLError where urlError.code == .cancelled {
            print("🚫 [AIScanningView] URLSession 被取消 (URLError.cancelled)！")
            AnalyticsService.logAIScanFailed(errorType: "url_cancelled")
            vm.loadingStage = .failed
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            vm.errorMessage = String(localized: "error.networkError")
            vm.showError = true
        } catch {
            print("❌ [AIScanningView] 錯誤: \(error)")
            let errorType: String
            if let aiError = error as? AIVisionError {
                if aiError.isQuotaExceeded {
                    vm.isQuotaError = true
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
                    vm.isNoTrackingDataError = true
                } else {
                    errorType = "tracking_error"
                }
            } else {
                errorType = "unknown"
            }
            AnalyticsService.logAIScanFailed(errorType: errorType)
            vm.loadingStage = .failed
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            vm.errorMessage = friendlyErrorMessage(for: error)
            vm.showError = true
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
    @State private var breatheOpacity: CGFloat = 1.0
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
        case .failed:
            return [
                Color(red: 0.9, green: 0.15, blue: 0.15),
                Color(red: 0.8, green: 0.1, blue: 0.3),
                Color(red: 1.0, green: 0.25, blue: 0.2)
            ]
        }
    }

    var body: some View {
        // .drawingGroup() 將整個 ZStack 合成為單一 Metal 渲染層
        // rotation/blur/offset 全在 GPU 繪圖層處理，不影響 SwiftUI layout bounds
        ZStack {
            // 外層光暈
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                primaryColors[i % primaryColors.count].opacity(0.2),
                                primaryColors[i % primaryColors.count].opacity(0.06),
                                primaryColors[i % primaryColors.count].opacity(0.02),
                                .clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 140
                        )
                    )
                    .frame(width: 200 + CGFloat(i) * 30,
                           height: 200 + CGFloat(i) * 30)
                    .rotationEffect(.degrees(outerRotation + Double(i) * 120))
                    .blur(radius: 14 + CGFloat(i) * 4)
                    .animation(.linear(duration: 40).repeatForever(autoreverses: false), value: outerRotation)
            }

            // 中層流體光球
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    primaryColors[i % primaryColors.count].opacity(0.4),
                                    primaryColors[(i + 1) % primaryColors.count].opacity(0.12),
                                    primaryColors[(i + 2) % primaryColors.count].opacity(0.04),
                                    .clear
                                ],
                                center: UnitPoint(
                                    x: 0.5 + sin(phase + Double(i) * 1.5) * 0.15,
                                    y: 0.5
                                ),
                                startRadius: 5,
                                endRadius: 70
                            )
                        )
                        .frame(width: 110, height: 110)
                        .offset(x: sin(phase + Double(i) * 1.6) * 12)
                        .blur(radius: 8)
                        .animation(.linear(duration: 14).repeatForever(autoreverses: false), value: phase)
                }
            }
            .opacity(breatheOpacity)
            .rotationEffect(.degrees(innerRotation))
            .animation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true), value: breatheOpacity)
            .animation(.linear(duration: 24).repeatForever(autoreverses: false), value: innerRotation)

            // 核心光點
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.7),
                            .white.opacity(0.25),
                            primaryColors[0].opacity(0.15),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 40
                    )
                )
                .frame(width: 80, height: 80)
                .opacity(breatheOpacity)
                .blur(radius: 3)
                .animation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true), value: breatheOpacity)

            // 完成 / 失敗圖標
            if stage == .complete {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.5), radius: 8)
            } else if stage == .failed {
                Image(systemName: "xmark")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.5), radius: 8)
            }
        }
        .frame(width: 280, height: 280)
        .drawingGroup()
        .onAppear {
            startAnimations()
        }
        .onChange(of: stage) { _, _ in
            breatheOpacity = 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                breatheOpacity = 0.7
            }
        }
    }

    private func startAnimations() {
        // 直接設值，動畫由各元素的 .animation(value:) 驅動，避免 withAnimation 洩漏
        breatheOpacity = 0.7
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
