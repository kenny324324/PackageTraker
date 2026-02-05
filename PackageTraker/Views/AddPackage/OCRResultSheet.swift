//
//  OCRResultSheet.swift
//  PackageTraker
//
//  顯示 OCR 辨識結果的 Sheet
//

import SwiftUI

/// OCR 結果選取回調
struct OCRSelection {
    let trackingNumber: String
    let suggestedCarrier: Carrier?
}

/// OCR 辨識結果顯示 Sheet
struct OCRResultSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let result: OCRResult
    let onSelect: (OCRSelection) -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if result.hasTrackingNumbers {
                    // 有辨識到單號時，顯示候選清單
                    trackingNumbersView
                } else {
                    // 沒有辨識到單號時，顯示所有文字讓使用者選擇
                    allTextsView
                }
            }
            .adaptiveBackground()
            .navigationTitle(String(localized: "ocr.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Tracking Numbers View
    
    private var trackingNumbersView: some View {
        candidatesList
    }
    
    private var candidatesList: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(String(localized: "ocr.tapToSelect"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                
                ForEach(result.trackingNumberCandidates) { candidate in
                    candidateRow(candidate)
                }
            }
            .padding(.vertical)
        }
    }
    
    private func candidateRow(_ candidate: TrackingNumberCandidate) -> some View {
        Button {
            onSelect(OCRSelection(
                trackingNumber: candidate.trackingNumber,
                suggestedCarrier: candidate.suggestedCarrier
            ))
            dismiss()
        } label: {
            HStack(spacing: 12) {
                // 物流商 Logo
                if let carrier = candidate.suggestedCarrier {
                    CarrierLogoView(carrier: carrier, size: 40)
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 40)
                        Image(systemName: "shippingbox")
                            .foregroundStyle(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // 單號
                    Text(candidate.trackingNumber)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    // 建議物流商
                    if let carrier = candidate.suggestedCarrier {
                        Text(String(format: String(localized: "ocr.possiblyCarrier"), carrier.displayName))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // 選取箭頭
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
    
    // MARK: - All Texts View
    
    private var allTextsView: some View {
        VStack(spacing: 0) {
            // 說明文字
            Text(String(localized: "ocr.manualSelection"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            
            allTextsList
        }
    }
    
    private var allTextsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(result.allRecognizedTexts) { text in
                    textRow(text)
                }
            }
            .padding()
        }
    }
    
    private func textRow(_ text: RecognizedText) -> some View {
        Button {
            // 清理文字後回傳
            let cleanedText = text.text
                .replacingOccurrences(of: " ", with: "")
                .uppercased()
            
            onSelect(OCRSelection(
                trackingNumber: cleanedText,
                suggestedCarrier: nil
            ))
            dismiss()
        } label: {
            HStack {
                Text(text.text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("有辨識結果") {
    OCRResultSheet(
        result: OCRResult(
            trackingNumberCandidates: [
                TrackingNumberCandidate(
                    trackingNumber: "T1234567890",
                    suggestedCarrier: .familyMart,
                    confidence: 0.95
                ),
                TrackingNumberCandidate(
                    trackingNumber: "9876543210123",
                    suggestedCarrier: .sevenEleven,
                    confidence: 0.8
                )
            ],
            allRecognizedTexts: [
                RecognizedText(text: "T1234567890", confidence: 0.95, boundingBox: .zero),
                RecognizedText(text: "訂單編號", confidence: 0.9, boundingBox: .zero),
                RecognizedText(text: "9876543210123", confidence: 0.85, boundingBox: .zero)
            ]
        ),
        onSelect: { _ in }
    )
}

#Preview("無辨識結果") {
    OCRResultSheet(
        result: OCRResult(
            trackingNumberCandidates: [],
            allRecognizedTexts: [
                RecognizedText(text: "訂單已出貨", confidence: 0.95, boundingBox: .zero),
                RecognizedText(text: "請至門市取貨", confidence: 0.9, boundingBox: .zero),
                RecognizedText(text: "ABC123XYZ", confidence: 0.85, boundingBox: .zero)
            ]
        ),
        onSelect: { _ in }
    )
}
