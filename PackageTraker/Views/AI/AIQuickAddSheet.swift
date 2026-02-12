//
//  AIQuickAddSheet.swift
//  PackageTraker
//
//  AI 辨識結果快速新增包裹 Sheet
//

import SwiftUI
import SwiftData
import WidgetKit

/// AI 快速新增包裹 Sheet
struct AIQuickAddSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var existingPackages: [Package]

    let aiResult: AIVisionResult
    let trackingResult: TrackingResult
    let relationId: String
    let onDismiss: () -> Void

    // 可編輯欄位（從 AI 結果初始化）
    @State private var editedName: String
    @State private var editedPickupLocation: String
    @State private var editedPickupCode: String
    @State private var editedAmount: String
    @State private var editedPlatform: String

    @State private var isSaving = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showManualAdjust = false
    @State private var showDuplicateAlert = false

    init(aiResult: AIVisionResult, trackingResult: TrackingResult, relationId: String, onDismiss: @escaping () -> Void) {
        self.aiResult = aiResult
        self.trackingResult = trackingResult
        self.relationId = relationId
        self.onDismiss = onDismiss
        _editedName = State(initialValue: aiResult.packageName ?? "")
        _editedPickupLocation = State(initialValue: aiResult.pickupLocation ?? "")
        _editedPickupCode = State(initialValue: aiResult.pickupCode ?? "")
        _editedAmount = State(initialValue: aiResult.amount ?? "")
        _editedPlatform = State(initialValue: aiResult.purchasePlatform ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 單號（唯讀）
                infoCard(
                    title: String(localized: "ai.field.trackingNumber"),
                    trailing: { ConfidenceBadge(confidence: aiResult.confidence) }
                ) {
                    Text(aiResult.trackingNumber ?? "")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                }

                // 物流商（唯讀）
                infoCard(title: String(localized: "ai.field.carrier")) {
                    if let carrier = aiResult.detectedCarrier {
                        HStack(spacing: 10) {
                            CarrierLogoView(carrier: carrier, size: 28)
                            Text(carrier.displayName)
                                .foregroundStyle(.white)
                        }
                    } else {
                        Text(aiResult.carrier ?? String(localized: "ai.field.unknown"))
                            .foregroundStyle(.secondary)
                    }
                }

                // 包裹狀態（API）
                infoCard(title: String(localized: "ai.quickAdd.status")) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(trackingResult.currentStatus.color)
                            .frame(width: 10, height: 10)
                        Text(trackingResult.currentStatus.displayName)
                            .foregroundStyle(.white)
                    }
                }

                // 取件門市（API）
                if let storeName = trackingResult.storeName {
                    infoCard(title: String(localized: "ai.quickAdd.storeName")) {
                        Text(storeName)
                            .foregroundStyle(.white)
                    }
                }

                // 取件期限（API）
                if let deadline = trackingResult.pickupDeadline {
                    infoCard(title: String(localized: "detail.pickupDeadline")) {
                        Text(deadline)
                            .foregroundStyle(.white)
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                // 可編輯：包裹名稱
                editableCard(title: String(localized: "ai.field.packageName"),
                             placeholder: String(localized: "add.productNamePlaceholder"),
                             text: $editedName)

                // 可編輯：取件地點
                editableCard(title: String(localized: "ai.quickAdd.pickupLocation"),
                             placeholder: String(localized: "add.pickupLocationPlaceholder"),
                             text: $editedPickupLocation)

                // 可編輯：取件碼
                if !editedPickupCode.isEmpty || aiResult.pickupCode != nil {
                    editableCard(title: String(localized: "ai.field.pickupCode"),
                                 placeholder: "",
                                 text: $editedPickupCode)
                }

                // 可編輯：購買平台
                if !editedPlatform.isEmpty || aiResult.purchasePlatform != nil {
                    editableCard(title: String(localized: "add.platform"),
                                 placeholder: String(localized: "add.platformPlaceholder"),
                                 text: $editedPlatform)
                }

                // 可編輯：金額
                if !editedAmount.isEmpty || aiResult.amount != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "add.amount"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField(String(localized: "add.amountPlaceholder"), text: $editedAmount)
                                .keyboardType(.decimalPad)
                        }
                        .adaptiveInputStyle()
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .scrollDismissesKeyboard(.interactively)
        .adaptiveBackground()
        .navigationTitle(String(localized: "ai.quickAdd.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(String(localized: "common.cancel")) {
                    onDismiss()
                }
                .foregroundStyle(.white)
                .disabled(isSaving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomButtons
        }
        .fullScreenCover(isPresented: $showManualAdjust) {
            NavigationStack {
                PackageQueryView(
                    trackingNumber: aiResult.trackingNumber ?? "",
                    carrier: aiResult.detectedCarrier ?? .other,
                    onComplete: { onDismiss() },
                    popToRoot: { showManualAdjust = false },
                    prefillName: editedName.isEmpty ? nil : editedName,
                    prefillPickupLocation: editedPickupLocation.isEmpty ? nil : editedPickupLocation,
                    prefillPickupCode: editedPickupCode.isEmpty ? nil : editedPickupCode
                )
            }
        }
        .alert(String(localized: "ai.quickAdd.error"), isPresented: $showError) {
            Button(String(localized: "common.confirm"), role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert(String(localized: "error.duplicateTitle"), isPresented: $showDuplicateAlert) {
            Button(String(localized: "common.confirm"), role: .cancel) { }
        } message: {
            Text(String(localized: "error.duplicateMessage"))
        }
        .overlay {
            if showSuccess {
                AISuccessAnimation()
            }
        }
        .interactiveDismissDisabled(isSaving)
        .preferredColorScheme(.dark)
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            // 一鍵新增（主按鈕）
            Button {
                Task { await quickAdd() }
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        Text(String(localized: "ai.quickAdd.quickAdd"))
                    }
                }
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.5, green: 0.2, blue: 0.8),
                            Color(red: 0.2, green: 0.4, blue: 0.9)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isSaving)

            // 手動調整（次按鈕）
            Button {
                showManualAdjust = true
            } label: {
                Text(String(localized: "ai.quickAdd.manualAdjust"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .disabled(isSaving)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Card Views

    private func infoCard<Content: View, Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                trailing()
            }
            content()
        }
        .padding()
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func editableCard(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .adaptiveInputStyle()
        }
        .padding(.horizontal)
    }

    // MARK: - Quick Add

    private func quickAdd() async {
        // 重複檢查
        let trackingNumber = aiResult.trackingNumber ?? ""
        if existingPackages.contains(where: { $0.trackingNumber == trackingNumber }) {
            showDuplicateAlert = true
            return
        }

        isSaving = true

        do {
            guard let carrier = aiResult.detectedCarrier else {
                throw AIVisionError.parseError
            }

            let package = Package(
                trackingNumber: trackingNumber,
                carrier: carrier,
                customName: editedName.isEmpty ? nil : editedName,
                pickupCode: editedPickupCode.isEmpty ? nil : editedPickupCode,
                pickupLocation: trackingResult.events.first?.location ?? carrier.defaultPickupLocation,
                status: trackingResult.currentStatus,
                latestDescription: trackingResult.events.first?.description,
                amount: Double(editedAmount),
                purchasePlatform: editedPlatform.isEmpty ? nil : editedPlatform,
                userPickupLocation: editedPickupLocation.isEmpty ? nil : editedPickupLocation
            )
            package.trackTwRelationId = relationId

            if let storeName = trackingResult.storeName { package.storeName = storeName }
            if let serviceType = trackingResult.serviceType { package.serviceType = serviceType }
            if let pickupDeadline = trackingResult.pickupDeadline { package.pickupDeadline = pickupDeadline }

            // 新增 tracking events
            for eventDTO in trackingResult.events {
                let event = TrackingEvent(
                    timestamp: eventDTO.timestamp,
                    status: eventDTO.status,
                    description: eventDTO.description,
                    location: eventDTO.location
                )
                event.package = package
                package.events.append(event)
            }

            // 儲存到 SwiftData
            modelContext.insert(package)
            try modelContext.save()

            // 同步到 Firestore
            FirebaseSyncService.shared.syncPackage(package)

            // 更新 Widget
            WidgetDataService.shared.updateWidgetData(packages: existingPackages + [package])
            WidgetCenter.shared.reloadAllTimelines()

            // 顯示成功動畫
            showSuccess = true

            // 震動回饋
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // 延遲後關閉
            try await Task.sleep(for: .seconds(1))
            onDismiss()

        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isSaving = false
        }
    }
}

// MARK: - Confidence Badge

struct ConfidenceBadge: View {
    let confidence: Double?

    var body: some View {
        if let confidence = confidence {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(text)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
        }
    }

    private var color: Color {
        guard let confidence = confidence else { return .gray }
        if confidence >= 0.9 { return .green }
        if confidence >= 0.7 { return .orange }
        return .gray
    }

    private var text: String {
        guard let confidence = confidence else { return String(localized: "ai.confidence.low") }
        if confidence >= 0.9 { return String(localized: "ai.confidence.high") }
        if confidence >= 0.7 { return String(localized: "ai.confidence.medium") }
        return String(localized: "ai.confidence.low")
    }
}

// MARK: - Success Animation

struct AISuccessAnimation: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text(String(localized: "ai.quickAdd.success"))
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    scale = 1.0
                    opacity = 1.0
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AIQuickAddSheet(
        aiResult: AIVisionResult(
            trackingNumber: "TW259426993523H",
            carrier: "蝦皮店到店",
            pickupLocation: "全家 台北信義店",
            pickupCode: "1234",
            packageName: "藍牙耳機",
            estimatedDelivery: nil,
            purchasePlatform: "蝦皮購物",
            amount: "199",
            confidence: 0.95
        ),
        trackingResult: TrackingResult(
            trackingNumber: "TW259426993523H",
            carrier: .shopee,
            currentStatus: .arrivedAtStore,
            events: [],
            rawResponse: nil,
            storeName: "全家信義店"
        ),
        relationId: "test-relation-id",
        onDismiss: {}
    )
    .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
