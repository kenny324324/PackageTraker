//
//  WhatsNewSheet.swift
//  PackageTraker
//
//  版本更新內容 Sheet（每個版本只顯示一次）
//

import SwiftUI

struct WhatsNewSheet: View {
    let data: WhatsNewData
    var markAsRead: Bool = true
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // App Icon
                Image("SplashIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)

                // 可滾動的功能列表容器
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(data.features.enumerated()), id: \.offset) { _, feature in
                            HStack(alignment: .top, spacing: 12) {
                                Text("•")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)

                                Text(feature)
                                    .font(.body)
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(16)
                }
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer(minLength: 0)

                // Dismiss button
                Button {
                    if markAsRead {
                        WhatsNewService.shared.markAsSeen(version: data.targetVersion)
                    }
                    dismiss()
                    onDismiss?()
                } label: {
                    Text(String(localized: "whatsNew.dismiss"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .adaptiveSheetCTAStyle(tint: .appAccent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .navigationTitle(String(format: NSLocalizedString("whatsNew.title", comment: ""), data.targetVersion))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationBackground {
            if #available(iOS 26, *) {
                Color.clear
            } else {
                Color.appBackground
            }
        }
        .preferredColorScheme(.dark)
    }
}
