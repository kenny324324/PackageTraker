import SwiftUI

/// 可重用的 SplashIcon 填充動畫
/// 沿用 PackageQueryView 的技術：灰階底層 + 全彩 mask 從下往上填充
struct RefreshAnimationView: View {
    /// icon 大小
    var size: CGFloat = 32
    /// 填充進度（0.0 ~ 1.0）
    var fillProgress: CGFloat
    /// 是否正在動畫
    var isAnimating: Bool

    /// 自動循環的填充動畫（當 fillProgress 不綁定外部時使用）
    @State private var autoFill: CGFloat = 0

    /// 實際使用的填充值
    private var effectiveFill: CGFloat {
        // 如果外部有傳入進度就用外部的，否則用自動循環
        fillProgress > 0 ? fillProgress : autoFill
    }

    var body: some View {
        ZStack {
            // 底層：灰階半透明
            Image("SplashIcon")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .saturation(0)
                .opacity(0.2)

            // 上層：全彩，mask 從下往上裁切
            Image("SplashIcon")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .mask(
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle()
                                .frame(height: geo.size.height * effectiveFill)
                        }
                    }
                )
        }
        .onAppear {
            guard isAnimating, fillProgress == 0 else { return }
            startAutoAnimation()
        }
        .onChange(of: isAnimating) { _, newValue in
            if newValue && fillProgress == 0 {
                startAutoAnimation()
            }
        }
    }

    private func startAutoAnimation() {
        autoFill = 0
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            autoFill = 1.0
        }
    }
}

/// 帶文字的刷新動畫 pill（用於首頁和詳細頁）
struct RefreshPillView: View {
    var fillProgress: CGFloat
    var isAnimating: Bool

    var body: some View {
        HStack(spacing: 8) {
            RefreshAnimationView(
                size: 24,
                fillProgress: fillProgress,
                isAnimating: isAnimating
            )

            Text(String(localized: "refresh.syncing"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}
