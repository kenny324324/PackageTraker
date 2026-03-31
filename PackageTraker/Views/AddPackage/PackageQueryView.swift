import SwiftUI
import UIKit

// MARK: - ViewModel（導航與查詢結果狀態，避免 view 重建時遺失）
@Observable
final class PackageQueryViewModel {
    // 查詢結果 + 導航
    var trackingResult: TrackingResult?
    var fetchedRelationId: String?
    var showStep2 = false

    // 動畫狀態
    var fillProgress: CGFloat = 0
    var logoScale: CGFloat = 1.0
    var isFound = false

    // 錯誤處理
    var showError = false
    var errorMessage = ""
    var showCancelAlert = false

    // 防止 .task 重複執行
    var queryStarted = false
}

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

    @State private var vm = PackageQueryViewModel()

    private let trackingManager = TrackingManager()

    var body: some View {
        @Bindable var vm = vm
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
                                    .frame(height: geo.size.height * vm.fillProgress)
                                    .animation(.easeOut(duration: 4.0), value: vm.fillProgress)
                            }
                        }
                    )
            }
            .scaleEffect(vm.logoScale)
            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: vm.logoScale)

            // 狀態文字
            Text(vm.isFound ? String(localized: "query.found") : String(localized: "query.searching"))
                .font(.headline)
                .foregroundStyle(vm.isFound ? .primary : .secondary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: vm.isFound)

            Spacer()

            Text(String(localized: "query.doNotLeave"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
                .opacity(vm.isFound ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .adaptiveBackground()
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    vm.showCancelAlert = true
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
        .navigationDestination(isPresented: $vm.showStep2) {
            if let result = vm.trackingResult,
               let relationId = vm.fetchedRelationId {
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
        .alert(String(localized: "error.queryFailed"), isPresented: $vm.showError) {
            Button(String(localized: "common.confirm"), role: .cancel) {
                dismiss()
            }
        } message: {
            Text(vm.errorMessage)
        }
        .alert(String(localized: "query.cancelTitle"), isPresented: $vm.showCancelAlert) {
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
        guard !vm.queryStarted else { return }
        vm.queryStarted = true

        // 開始緩慢填色（動畫由 Rectangle 上的 .animation() 驅動）
        vm.fillProgress = 0.7

        do {
            let relationId = try await trackingManager.importPackage(number: trackingNumber, carrier: carrier)

            let result = try await trackingManager.track(number: trackingNumber, carrier: carrier)

            if result.events.isEmpty {
                vm.errorMessage = String(localized: "error.noHistory")
                vm.showError = true
                return
            }

            // 查詢成功 → 儲存結果
            vm.trackingResult = result
            vm.fetchedRelationId = relationId

            // 快速填滿
            vm.fillProgress = 1.0

            // 標記已找到
            vm.isFound = true

            // 震動回饋
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // 彈跳動畫
            vm.logoScale = 1.15
            try? await Task.sleep(for: .milliseconds(200))
            vm.logoScale = 1.0

            // 延遲後自動導航
            try? await Task.sleep(for: .milliseconds(800))
            vm.showStep2 = true

        } catch {
            vm.errorMessage = mapErrorMessage(error)
            vm.showError = true
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
            case .noTrackingData:
                return String(localized: "ai.error.noTrackingData")
            }
        }
        return "查詢時遇到問題：\(error.localizedDescription)"
    }
}
