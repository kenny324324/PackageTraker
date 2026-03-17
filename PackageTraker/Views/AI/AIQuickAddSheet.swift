//
//  AIQuickAddSheet.swift
//  PackageTraker
//
//  AI 辨識結果確認頁 — 仿 PackageDetailView 佈局，下一步前往 PackageInfoView
//

import SwiftUI
import SwiftData

/// AI 辨識結果確認頁
struct AIQuickAddSheet: View {
    let aiResult: AIVisionResult
    let onDismiss: () -> Void

    @State private var currentTrackingResult: TrackingResult
    @State private var currentRelationId: String
    @State private var showPackageInfo = false
    @State private var editedTrackingNumber = ""
    @State private var editedCarrier: Carrier = .other
    @State private var showEditSheet = false
    @State private var isPollingEvents = false
    @State private var isRetracking = false

    private let trackingManager = TrackingManager()

    init(aiResult: AIVisionResult, trackingResult: TrackingResult, relationId: String, onDismiss: @escaping () -> Void) {
        self.aiResult = aiResult
        self.onDismiss = onDismiss
        self._currentTrackingResult = State(initialValue: trackingResult)
        self._currentRelationId = State(initialValue: relationId)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 頂部：包裹資訊卡片
                packageInfoCard

                // 物流追蹤歷程
                trackingTimelineSection
            }
            .padding()
            .padding(.bottom, 80)
        }
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
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPackageInfo = true
                } label: {
                    Text(String(localized: "ai.quickAdd.nextStep"))
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
                .tint(Color.appAccent)
            }
        }
        // .safeAreaInset(edge: .bottom) {
        //     bottomToolbar
        // }
        .navigationDestination(isPresented: $showPackageInfo) {
            PackageInfoView(
                trackingNumber: editedTrackingNumber,
                carrier: editedCarrier,
                trackingResult: currentTrackingResult,
                relationId: currentRelationId,
                onComplete: { onDismiss() },
                popToRoot: { showPackageInfo = false },
                prefillName: aiResult.packageName,
                prefillPickupLocation: aiResult.pickupLocation,
                prefillPickupCode: aiResult.pickupCode,
                prefillPlatform: aiResult.detectedPlatform,
                prefillAmount: aiResult.amount
            )
        }
        .sheet(isPresented: $showEditSheet) {
            AIEditSheet(
                carrier: $editedCarrier
            )
        }
        .onAppear {
            editedTrackingNumber = aiResult.trackingNumber ?? ""
            editedCarrier = currentTrackingResult.carrier
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Package Info Card

    private var carrierDisplayTitle: String {
        if let storeName = currentTrackingResult.storeName, !storeName.isEmpty {
            if editedCarrier == .sevenEleven {
                return "\(editedCarrier.displayName) \(storeName)"
            } else if editedCarrier == .familyMart {
                return storeName
            }
        }
        return editedCarrier.displayName
    }

    private var packageInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 物流商與狀態
            HStack {
                CarrierLogoView(carrier: editedCarrier, size: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(carrierDisplayTitle)
                        .font(.headline)

                    Text(editedTrackingNumber)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }

                Spacer()

                StatusIconBadge(status: currentTrackingResult.currentStatus)
            }

            // 取貨地點
            if let storeName = currentTrackingResult.storeName {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.secondary)
                    Text(storeName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // 取件期限
            if let deadline = currentTrackingResult.pickupDeadline {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("\(String(localized: "detail.deadline")) \(deadline)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .adaptiveCardStyle()
    }

    // MARK: - Tracking Timeline

    private var trackingTimelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "ai.quickAdd.trackingTimeline"))
                .font(.headline)

            if !currentTrackingResult.events.isEmpty {
                VStack(spacing: 0) {
                    let sortedEvents = currentTrackingResult.events
                        .sorted { $0.timestamp > $1.timestamp }
                    ForEach(Array(sortedEvents.enumerated()), id: \.offset) { index, event in
                        TimelineEventRow(
                            event: event,
                            isFirst: index == 0,
                            isLast: index == sortedEvents.count - 1
                        )
                    }
                }
                .adaptiveCardStyle()
            } else {
                HStack(spacing: 10) {
                    if isPollingEvents {
                        ProgressView()
                            .tint(.secondary)
                    } else {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Text(String(localized: isPollingEvents ? "ai.quickAdd.fetchingTracking" : "ai.quickAdd.pendingTracking"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .adaptiveCardStyle()
            }
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack {
            Spacer()

            Button {
                showEditSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.title3)
                    Text(String(localized: "detail.edit"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .adaptiveCapsuleButtonStyle()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

// MARK: - AI Edit Sheet

private struct AIEditSheet: View {
    @Binding var carrier: Carrier

    @Environment(\.dismiss) private var dismiss
    @State private var showCarrierPicker = false

    // 暫存編輯值，取消時不影響原值
    @State private var tempCarrier: Carrier = .other

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // 物流商
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "ai.field.carrier"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        showCarrierPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            CarrierLogoView(carrier: tempCarrier, size: 36)
                            Text(tempCarrier.displayName)
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                    }
                    .adaptiveInteractiveCardStyle()
                }

                Spacer()
            }
            .padding()
            .navigationTitle(String(localized: "detail.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) {
                        carrier = tempCarrier
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
        .onAppear {
            tempCarrier = carrier
        }
        .sheet(isPresented: $showCarrierPicker) {
            CarrierPickerSheet(
                selectedCarrier: $tempCarrier,
                isPresented: $showCarrierPicker
            )
        }
    }
}

// MARK: - Carrier Picker

private struct CarrierPickerSheet: View {
    @Binding var selectedCarrier: Carrier
    @Binding var isPresented: Bool

    private let carriers: [Carrier] = Carrier.allCases.map { $0 }
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool

    private var filteredCarriers: [Carrier] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return carriers }

        return carriers.filter { carrier in
            carrier.displayName.localizedCaseInsensitiveContains(keyword)
                || carrier.rawValue.localizedCaseInsensitiveContains(keyword)
                || carrier.abbreviation.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCarriers, id: \.rawValue) { (carrier: Carrier) in
                            carrierRow(carrier)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    isSearchFieldFocused = false
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isSearchFieldFocused = false
            }
            .navigationTitle(String(localized: "ai.field.carrier"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(String(localized: "carrier.searchPlaceholder"), text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($isSearchFieldFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.secondaryCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func carrierRow(_ carrier: Carrier) -> some View {
        Button {
            selectedCarrier = carrier
            isPresented = false
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CarrierLogoView(carrier: carrier, size: 32)
                    Text(carrier.displayName)
                        .foregroundStyle(.white)
                    Spacer()
                    if carrier == selectedCarrier {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.appAccent)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                Divider()
                    .padding(.leading, 56)
            }
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

// MARK: - Preview

#Preview {
    NavigationStack {
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
    }
    .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
