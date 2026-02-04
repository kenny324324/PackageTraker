import SwiftUI

// MARK: - Version-Aware Glass Effect Modifiers

extension View {
    /// 卡片樣式 - iOS 26+ 使用 Liquid Glass，舊版使用傳統深色卡片
    @ViewBuilder
    func adaptiveCardStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .padding(16)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            self
                .padding(16)
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    /// 互動式卡片樣式 - iOS 26+ 具有觸控回饋
    @ViewBuilder
    func adaptiveInteractiveCardStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .padding(16)
                .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            self
                .padding(16)
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    /// 次要卡片樣式
    @ViewBuilder
    func adaptiveSecondaryCardStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .padding(12)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            self
                .padding(12)
                .background(Color.secondaryCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 徽章樣式 - 適用於狀態標籤
    @ViewBuilder
    func adaptiveBadgeStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: Capsule())
        } else {
            self
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondaryCardBackground)
                .clipShape(Capsule())
        }
    }

    /// 帶顏色的徽章樣式
    @ViewBuilder
    func adaptiveTintedBadgeStyle(tint: Color) -> some View {
        if #available(iOS 26, *) {
            self
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(tint), in: Capsule())
        } else {
            self
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint.opacity(0.2))
                .clipShape(Capsule())
        }
    }

    /// 按鈕樣式
    @ViewBuilder
    func adaptiveButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.cardBackground)
                .clipShape(Capsule())
        }
    }

    /// 統計數據卡片樣式
    @ViewBuilder
    func adaptiveStatsCardStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .padding(16)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            self
                .padding(16)
                .background(
                    LinearGradient(
                        colors: [
                            Color.appAccent.opacity(0.15),
                            Color.appAccent.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    /// 輸入框樣式
    @ViewBuilder
    func adaptiveInputStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .padding(14)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            self
                .padding(14)
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 導航欄樣式 - 移除背景讓系統 Liquid Glass 生效
    @ViewBuilder
    func adaptiveNavigationStyle() -> some View {
        if #available(iOS 26, *) {
            self
                .toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    /// 物流商選擇按鈕背景
    @ViewBuilder
    func carrierButtonBackground(isSelected: Bool, brandColor: Color) -> some View {
        if #available(iOS 26, *) {
            if isSelected {
                self
                    .glassEffect(.regular.tint(brandColor).interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                self
                    .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            self
                .background(isSelected ? brandColor.opacity(0.1) : Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? brandColor : Color.clear, lineWidth: 2)
                )
        }
    }

    /// 底部 Toolbar 按鈕樣式（圓形）
    @ViewBuilder
    func adaptiveToolbarButtonStyle(tint: Color? = nil) -> some View {
        if #available(iOS 26, *) {
            if let tint = tint {
                self.glassEffect(.regular.tint(tint).interactive(), in: Circle())
            } else {
                self.glassEffect(.regular.interactive(), in: Circle())
            }
        } else {
            self
                .background(tint?.opacity(0.15) ?? Color.cardBackground)
                .clipShape(Circle())
        }
    }

    /// 底部 Toolbar 膠囊按鈕樣式（帶文字）
    @ViewBuilder
    func adaptiveCapsuleButtonStyle(tint: Color? = nil) -> some View {
        if #available(iOS 26, *) {
            if let tint = tint {
                self.glassEffect(.regular.tint(tint).interactive(), in: Capsule())
            } else {
                self.glassEffect(.regular.interactive(), in: Capsule())
            }
        } else {
            self
                .background(tint?.opacity(0.15) ?? Color.cardBackground)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Adaptive Background

extension View {
    /// 自適應背景 - iOS 26+ 使用純色讓玻璃效果更明顯
    @ViewBuilder
    func adaptiveBackground() -> some View {
        if #available(iOS 26, *) {
            self.background(Color.adaptiveAppBackground.ignoresSafeArea())
        } else {
            self.background(Color.appBackground.ignoresSafeArea())
        }
    }

    /// 自適應背景帶漸層
    @ViewBuilder
    func adaptiveGradientBackground() -> some View {
        if #available(iOS 26, *) {
            self.background(
                ZStack {
                    Color.adaptiveAppBackground

                    // iOS 26 使用更深的漸層
                    LinearGradient(
                        colors: [
                            Color.appAccent.opacity(0.35),
                            Color.appAccent.opacity(0.18),
                            Color.appAccent.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 500)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .ignoresSafeArea()
            )
        } else {
            self.background(
                ZStack {
                    Color.appBackground

                    LinearGradient(
                        colors: [
                            Color.appAccent.opacity(0.5),
                            Color.appAccent.opacity(0.28),
                            Color.appAccent.opacity(0.12),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 450)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .ignoresSafeArea()
            )
        }
    }
}

// MARK: - Adaptive Colors

extension Color {
    /// 自適應背景色 - iOS 26 使用稍亮的背景讓玻璃效果更明顯
    static var adaptiveAppBackground: Color {
        if #available(iOS 26, *) {
            return Color(hex: "1A1A1A") // 稍亮的背景
        } else {
            return appBackground
        }
    }

    /// 自適應卡片背景
    static var adaptiveCardBackground: Color {
        if #available(iOS 26, *) {
            return Color.clear // iOS 26 使用玻璃效果
        } else {
            return cardBackground
        }
    }
}

// MARK: - Glass Effect Container Wrapper

/// 玻璃效果容器 - 用於群組多個玻璃元素
struct AdaptiveGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 20, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}
