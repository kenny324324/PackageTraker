import SwiftUI
import UIKit

/// 查詢包裹 — 中間過場頁面（填色動畫 + 自動導航）
struct PackageQueryView: View {
    @Environment(\.dismiss) private var dismiss

    let trackingNumber: String
    let carrier: Carrier
    let onComplete: () -> Void
    let popToRoot: () -> Void

    // AI 預填欄位（可選）
    var prefillName: String? = nil
    var prefillPickupLocation: String? = nil
    var prefillPickupCode: String? = nil

    // 動畫狀態
    @State private var fillProgress: CGFloat = 0
    @State private var logoScale: CGFloat = 1.0
    @State private var isFound = false

    // 查詢結果
    @State private var trackingResult: TrackingResult?
    @State private var fetchedRelationId: String?
    @State private var showStep2 = false

    // 錯誤處理
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showCancelAlert = false

    private let trackingManager = TrackingManager()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo 填色動畫
            ZStack {
                // 底層：灰階半透明
                Image("SplashIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .saturation(0)
                    .opacity(0.2)

                // 上層：全彩，用 mask 從下往上裁切
                Image("SplashIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .mask(
                        GeometryReader { geo in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                Rectangle()
                                    .frame(height: geo.size.height * fillProgress)
                            }
                        }
                    )
            }
            .scaleEffect(logoScale)

            // 狀態文字
            Text(isFound ? String(localized: "query.found") : String(localized: "query.searching"))
                .font(.headline)
                .foregroundStyle(isFound ? .primary : .secondary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: isFound)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .adaptiveBackground()
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showCancelAlert = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(String(localized: "add.title"))
                    }
                }
                .foregroundStyle(.white)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "add.button")) {
                    // 不執行任何動作，這是視覺過渡用的
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
                .disabled(true)
            }
        }
        .navigationDestination(isPresented: $showStep2) {
            if let result = trackingResult,
               let relationId = fetchedRelationId {
                PackageInfoView(
                    trackingNumber: trackingNumber,
                    carrier: carrier,
                    trackingResult: result,
                    relationId: relationId,
                    onComplete: onComplete,
                    popToRoot: popToRoot,
                    prefillName: prefillName,
                    prefillPickupLocation: prefillPickupLocation,
                    prefillPickupCode: prefillPickupCode
                )
            }
        }
        .alert(String(localized: "error.queryFailed"), isPresented: $showError) {
            Button(String(localized: "common.confirm"), role: .cancel) {
                dismiss()
            }
        } message: {
            Text(errorMessage)
        }
        .alert(String(localized: "query.cancelTitle"), isPresented: $showCancelAlert) {
            Button(String(localized: "common.cancel"), role: .cancel) { }
            Button(String(localized: "query.cancelConfirm"), role: .destructive) {
                dismiss()
            }
        } message: {
            Text(String(localized: "query.cancelMessage"))
        }
        .task {
            await performQuery()
        }
    }

    // MARK: - Query + Animation

    private func performQuery() async {
        // 開始緩慢填色（背景動畫）
        withAnimation(.easeOut(duration: 4.0)) {
            fillProgress = 0.7
        }

        do {
            let relationId = try await trackingManager.importPackage(number: trackingNumber, carrier: carrier)

            let result = try await trackingManager.track(number: trackingNumber, carrier: carrier)

            if result.events.isEmpty {
                errorMessage = String(localized: "error.noHistory")
                showError = true
                return
            }

            // 查詢成功 → 儲存結果
            trackingResult = result
            fetchedRelationId = relationId

            // 快速填滿
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                fillProgress = 1.0
            }

            // 標記已找到
            withAnimation {
                isFound = true
            }

            // 震動回饋
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // 彈跳動畫
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                logoScale = 1.15
            }
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                logoScale = 1.0
            }

            // 延遲後自動導航
            try? await Task.sleep(for: .milliseconds(800))
            showStep2 = true

        } catch {
            errorMessage = mapErrorMessage(error)
            showError = true
        }
    }

    // MARK: - Helpers

    private func mapErrorMessage(_ error: Error) -> String {
        if let trackingError = error as? TrackingError {
            switch trackingError {
            case .trackingNumberNotFound:
                return "查無此單號，請確認單號是否正確"
            case .unsupportedCarrier:
                return "目前尚未支援此物流商"
            case .networkError:
                return "網路連線異常，請檢查網路後再試"
            case .parsingError(let message):
                return "資料格式有誤：\(message)"
            case .invalidResponse:
                return "伺服器回應異常，請稍後再試"
            case .rateLimited:
                return "查詢過於頻繁，請稍後再試"
            case .invalidTrackingNumber:
                return "單號格式不正確，請檢查是否輸入正確"
            case .unauthorized:
                return "API Token 已過期或需要重新設定，請至設定頁面處理"
            case .serverError(let message):
                return "伺服器異常：\(message)"
            }
        }
        return "查詢時遇到問題：\(error.localizedDescription)"
    }
}
