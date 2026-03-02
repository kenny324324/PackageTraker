//
//  ForceUpdateView.swift
//  PackageTraker
//
//  版本過舊時的強制更新畫面（無法關閉）
//

import SwiftUI

/// 強制更新畫面：版本低於 Firestore minimumVersion 時全螢幕遮擋
struct ForceUpdateView: View {
    let storeURL: String

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)

                Text(String(localized: "forceUpdate.title"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text(String(localized: "forceUpdate.message"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    if let url = URL(string: storeURL) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(String(localized: "forceUpdate.button"))
                        .fontWeight(.bold)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 40)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}
