//
//  AIVisionResultSheet.swift
//  PackageTraker
//
//  Displays AI vision recognition results with editable fields
//

import SwiftUI

/// AI 辨識結果回調
struct AIVisionSelection {
    let trackingNumber: String
    let carrier: Carrier?
    let pickupLocation: String?
    let pickupCode: String?
    let packageName: String?
}

/// AI 辨識結果顯示 Sheet
struct AIVisionResultSheet: View {
    @Environment(\.dismiss) private var dismiss

    let result: AIVisionResult
    let onConfirm: (AIVisionSelection) -> Void

    @State private var trackingNumber: String = ""
    @State private var selectedCarrier: Carrier?
    @State private var pickupLocation: String = ""
    @State private var pickupCode: String = ""
    @State private var packageName: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // AI 結果欄位
                    fieldSection(
                        title: String(localized: "ai.field.trackingNumber"),
                        text: $trackingNumber,
                        confidence: result.confidence ?? 0
                    )

                    carrierSection

                    fieldSection(
                        title: String(localized: "ai.field.pickupLocation"),
                        text: $pickupLocation,
                        confidence: result.pickupLocation != nil ? (result.confidence ?? 0.5) : 0
                    )

                    fieldSection(
                        title: String(localized: "ai.field.pickupCode"),
                        text: $pickupCode,
                        confidence: result.pickupCode != nil ? (result.confidence ?? 0.5) : 0
                    )

                    fieldSection(
                        title: String(localized: "ai.field.packageName"),
                        text: $packageName,
                        confidence: result.packageName != nil ? (result.confidence ?? 0.5) : 0
                    )

                    // 確認按鈕
                    Button {
                        onConfirm(AIVisionSelection(
                            trackingNumber: trackingNumber,
                            carrier: selectedCarrier,
                            pickupLocation: pickupLocation.isEmpty ? nil : pickupLocation,
                            pickupCode: pickupCode.isEmpty ? nil : pickupCode,
                            packageName: packageName.isEmpty ? nil : packageName
                        ))
                        dismiss()
                    } label: {
                        Text(String(localized: "ai.confirm"))
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.appAccent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(trackingNumber.isEmpty)
                }
                .padding()
            }
            .adaptiveBackground()
            .navigationTitle(String(localized: "ai.resultTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .onAppear {
                trackingNumber = result.trackingNumber ?? ""
                selectedCarrier = result.detectedCarrier
                pickupLocation = result.pickupLocation ?? ""
                pickupCode = result.pickupCode ?? ""
                packageName = result.packageName ?? ""
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Views

    private func fieldSection(title: String, text: Binding<String>, confidence: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                confidenceBadge(confidence)
            }

            TextField(title, text: text)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .adaptiveInputStyle()
                .autocorrectionDisabled()
        }
    }

    private var carrierSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "ai.field.carrier"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                confidenceBadge(result.carrier != nil ? (result.confidence ?? 0.5) : 0)
            }

            if let carrier = selectedCarrier {
                HStack(spacing: 12) {
                    CarrierLogoView(carrier: carrier, size: 32)
                    Text(carrier.displayName)
                        .foregroundStyle(.white)
                    Spacer()
                    if let rawCarrier = result.carrier {
                        Text(rawCarrier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.secondaryCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text(result.carrier ?? String(localized: "ai.field.unknown"))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondaryCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func confidenceBadge(_ confidence: Double) -> some View {
        let color: Color
        let text: String

        if confidence >= 0.9 {
            color = .green
            text = String(localized: "ai.confidence.high")
        } else if confidence >= 0.7 {
            color = .yellow
            text = String(localized: "ai.confidence.medium")
        } else {
            color = .gray
            text = String(localized: "ai.confidence.low")
        }

        return Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    AIVisionResultSheet(
        result: AIVisionResult(
            trackingNumber: "TW259426993523H",
            carrier: "蝦皮店到店",
            pickupLocation: "全家 台北信義店",
            pickupCode: "1234",
            packageName: "藍牙耳機",
            estimatedDelivery: "2026-02-12",
            confidence: 0.95
        ),
        onConfirm: { _ in }
    )
}
