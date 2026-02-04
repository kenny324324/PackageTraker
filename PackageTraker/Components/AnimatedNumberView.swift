//
//  AnimatedNumberView.swift
//  PackageTraker
//
//  使用 contentTransition(.numericText()) 的數字動畫組件
//

import SwiftUI

/// 動畫數字顯示視圖
/// 使用 iOS 16+ 的 contentTransition(.numericText()) 實現平滑數字過渡
struct AnimatedNumberView: View {
    let targetValue: Int
    let font: Font
    let fontWeight: Font.Weight
    let textColor: Color
    
    // 動畫狀態
    @State private var displayedValue: Int = 0
    @State private var hasAppeared = false
    
    init(
        value: Int,
        font: Font = .system(size: 32, design: .rounded),
        fontWeight: Font.Weight = .bold,
        textColor: Color = .primary
    ) {
        self.targetValue = value
        self.font = font
        self.fontWeight = fontWeight
        self.textColor = textColor
    }
    
    var body: some View {
        Text("\(displayedValue)")
            .font(font)
            .fontWeight(fontWeight)
            .foregroundStyle(textColor)
            .contentTransition(.numericText(countsDown: false))
            .onAppear {
                // 首次出現時從 0 動畫到目標值（如果目標是 0 則不動畫）
                guard !hasAppeared else { return }
                hasAppeared = true
                
                if targetValue != 0 {
                    // 使用 DispatchQueue 確保視圖已渲染
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 1.2)) {
                            displayedValue = targetValue
                        }
                    }
                }
            }
            .onChange(of: targetValue) { _, newValue in
                // 值變化時動畫
                withAnimation(.easeOut(duration: 0.6)) {
                    displayedValue = newValue
                }
            }
    }
}

// MARK: - Convenience Initializers

extension AnimatedNumberView {
    /// 統計卡片樣式
    static func statsStyle(value: Int) -> AnimatedNumberView {
        AnimatedNumberView(
            value: value,
            font: .system(size: 32, design: .rounded),
            fontWeight: .bold,
            textColor: .primary
        )
    }
}

// MARK: - Legacy Alias (為了相容性保留)

typealias RollingNumberView = AnimatedNumberView

// MARK: - Previews

#Preview("Animated Number") {
    struct PreviewWrapper: View {
        @State private var count = 0
        
        var body: some View {
            VStack(spacing: 24) {
                AnimatedNumberView.statsStyle(value: count)
                
                HStack(spacing: 16) {
                    Button("-") {
                        if count > 0 { count -= 1 }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("+") {
                        count += 1
                    }
                    .buttonStyle(.bordered)
                    
                    Button("+10") {
                        count += 10
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color.appBackground)
        }
    }
    
    return PreviewWrapper()
        .preferredColorScheme(.dark)
}

#Preview("Multiple Numbers") {
    VStack(spacing: 16) {
        HStack {
            Text("待取：")
            AnimatedNumberView.statsStyle(value: 5)
        }
        
        HStack {
            Text("本月已取：")
            AnimatedNumberView.statsStyle(value: 23)
        }
        
        HStack {
            Text("大數字：")
            AnimatedNumberView.statsStyle(value: 128)
        }
    }
    .padding()
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
