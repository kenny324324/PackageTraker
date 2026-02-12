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

    // 錯誤
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showManualAdd = false

    private let trackingManager = TrackingManager()
    private let aiService = AIVisionService.shared

    var body: some View {
        NavigationStack {
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

                        Text(stageSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .contentTransition(.numericText())
                    }
                    .animation(.easeInOut(duration: 0.4), value: loadingStage)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onCancel()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                            Text(String(localized: "common.cancel"))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.7))
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
                            carrier: result.detectedCarrier ?? .other,
                            onComplete: { onDismiss() },
                            popToRoot: { showManualAdd = false }
                        )
                    }
                }
            }
            .alert(String(localized: "ai.error.title"), isPresented: $showError) {
                Button(String(localized: "addMethod.retry")) {
                    Task { await processAIWorkflow() }
                }
                if aiResult?.trackingNumber != nil {
                    Button(String(localized: "addMethod.manualInput")) {
                        showError = false
                        showManualAdd = true
                    }
                }
                Button(String(localized: "common.cancel"), role: .cancel) {
                    onCancel()
                }
            } message: {
                Text(errorMessage)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await processAIWorkflow()
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
        showError = false
        errorMessage = ""
        navigateToQuickAdd = false

        do {
            // 階段 1：AI 辨識
            loadingStage = .aiRecognition

            let result = try await analyzeImageWithRetry(image)
            self.aiResult = result

            // 階段 2：API 驗證
            withAnimation { loadingStage = .apiVerification }

            guard let trackingNumber = result.trackingNumber,
                  let carrier = result.detectedCarrier else {
                throw TrackingError.invalidTrackingNumber
            }

            let relationId = try await trackingManager.importPackage(
                number: trackingNumber,
                carrier: carrier
            )

            let trackingResult = try await trackingManager.track(
                number: trackingNumber,
                carrier: carrier
            )

            self.apiTrackingResult = trackingResult
            self.apiRelationId = relationId

            // 完成
            withAnimation { loadingStage = .complete }

            // 震動回饋
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // 短暫延遲後顯示結果
            try? await Task.sleep(for: .milliseconds(600))
            navigateToQuickAdd = true

        } catch {
            errorMessage = error.localizedDescription
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
        case .apiError, .parseError:
            return true
        default:
            return false
        }
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
                }
            }
            .scaleEffect(breatheScale)
            .rotationEffect(.degrees(innerRotation))

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

            // 只在完成顯示中心圖標，辨識中不顯示星星
            if stage == .complete {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .scaleEffect(breatheScale * 0.9)
                    .shadow(color: .white.opacity(0.5), radius: 8)
            }
        }
        .onAppear {
            startAnimations()
        }
        .onChange(of: stage) { _, _ in
            // 階段切換時加一個彈跳
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                breatheScale = 1.15
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    breatheScale = 1.0
                }
            }
        }
        .animation(.easeInOut(duration: 1.0), value: stage)
    }

    private func startAnimations() {
        // 呼吸縮放
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            breatheScale = 1.08
        }

        // 內圈旋轉
        withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
            innerRotation = 360
        }

        // 外圈旋轉（反方向）
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            outerRotation = -360
        }

        // 相位偏移（控制流體位移）
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
            phase = .pi * 2
        }
    }
}

// MARK: - Preview

#Preview("AI Scanning") {
    AIScanningView(
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
