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
                    trackingNumbersView
                } else {
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
                    Text(candidate.trackingNumber)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    if let carrier = candidate.suggestedCarrier {
                        Text(String(format: String(localized: "ocr.possiblyCarrier"), carrier.displayName))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

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

    // MARK: - All Texts View (Fallback)

    private var allTextsView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)

                Text(String(localized: "ocr.noResultTitle"))
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(String(localized: "ocr.noResultMessage"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()

            allTextsList
        }
    }

    /// 過濾短文字，高亮含數字序列的文字
    private var filteredTexts: [RecognizedText] {
        result.allRecognizedTexts
            .filter { $0.text.count >= 5 }
            .sorted { textRelevance($0) > textRelevance($1) }
    }

    /// 文字相關性評分（含數字越多，分數越高）
    private func textRelevance(_ text: RecognizedText) -> Int {
        let digitCount = text.text.filter(\.isNumber).count
        let alphanumCount = text.text.filter(\.isLetter).count + digitCount
        if digitCount >= 8 { return 100 + digitCount }
        if digitCount >= 5 { return 50 + digitCount }
        if alphanumCount >= 8 { return 30 + alphanumCount }
        return digitCount
    }

    private var allTextsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredTexts) { text in
                    textRow(text)
                }

                if filteredTexts.isEmpty {
                    Text(String(localized: "ocr.noTextsFound"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                }
            }
            .padding()
        }
    }

    private func textRow(_ text: RecognizedText) -> some View {
        let hasDigitSequence = text.text.filter(\.isNumber).count >= 5

        return Button {
            let cleanedText = text.text
                .replacingOccurrences(of: " ", with: "")
                .uppercased()

            let detected = CarrierDetector.detectBest(cleanedText)

            onSelect(OCRSelection(
                trackingNumber: cleanedText,
                suggestedCarrier: detected?.carrier
            ))
            dismiss()
        } label: {
            HStack {
                if hasDigitSequence {
                    Image(systemName: "number")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .frame(width: 20)
                }

                Text(text.text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(hasDigitSequence ? Color.white : Color.secondary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(hasDigitSequence ? Color.cardBackground : Color.secondaryCardBackground)
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
