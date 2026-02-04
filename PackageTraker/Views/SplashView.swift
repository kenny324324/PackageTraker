import SwiftUI
import SwiftData

/// 自定義啟動頁面
struct SplashView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var progress: Double = 0
    @State private var boxOffset: CGFloat = -400 // 從畫面上方開始
    @State private var boxRotation: Double = -20 // 初始傾斜
    @State private var boxSquash: CGFloat = 1.0 // 壓扁效果
    @State private var shadowRadius: CGFloat = 0
    @State private var shadowOpacity: Double = 0
    @State private var shadowScale: CGFloat = 0.3
    @State private var showProgress = false
    
    var onLoadingComplete: () -> Void
    
    var body: some View {
        ZStack {
            // 背景色
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // 箱子 - 從天而降動畫
                VStack(spacing: 0) {
                    Image("SplashIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(boxRotation))
                        .scaleEffect(x: 1.0 / boxSquash, y: boxSquash, anchor: .bottom) // 落地壓扁效果
                        .offset(y: boxOffset)
                    
                    // 落地陰影
                    Ellipse()
                        .fill(Color.black.opacity(shadowOpacity))
                        .frame(width: 80, height: 24)
                        .blur(radius: shadowRadius)
                        .scaleEffect(shadowScale)
                        .offset(y: -15)
                }
                
                Spacer()
                
                // 進度條 + 文字
                VStack(spacing: 16) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .appAccent))
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                        .frame(width: 200)
                    
                    Text(String(localized: "splash.loading"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 80)
                .opacity(showProgress ? 1 : 0)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await startAnimation()
        }
    }
    
    private func startAnimation() async {
        // 等待一小段時間讓畫面準備好
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // 掉落過程中陰影漸漸出現並變大
        await MainActor.run {
            withAnimation(.easeIn(duration: 0.35)) {
                shadowOpacity = 0.25
                shadowRadius = 10
                shadowScale = 0.8
            }
        }
        
        // 箱子快速掉落（保持傾斜）
        await MainActor.run {
            withAnimation(.easeIn(duration: 0.35)) {
                boxOffset = 0
            }
        }
        
        try? await Task.sleep(nanoseconds: 350_000_000)
        
        // 第一次落地：壓扁 + 往外傾斜更多
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.06)) {
                boxSquash = 0.8
                boxRotation = -25
                shadowOpacity = 0.4
                shadowRadius = 5
                shadowScale = 1.0
            }
        }
        
        try? await Task.sleep(nanoseconds: 60_000_000)
        
        // 第一次彈起
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.2)) {
                boxSquash = 1.0
                boxOffset = -40
                boxRotation = 10 // 往另一邊傾斜
                shadowOpacity = 0.2
                shadowScale = 0.6
            }
        }
        
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // 第二次落地
        await MainActor.run {
            withAnimation(.easeIn(duration: 0.15)) {
                boxOffset = 0
                shadowScale = 0.9
            }
        }
        
        try? await Task.sleep(nanoseconds: 150_000_000)
        
        // 第二次壓扁（較輕微）
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.05)) {
                boxSquash = 0.9
                boxRotation = -5
                shadowOpacity = 0.35
                shadowScale = 1.0
            }
        }
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        // 最終回正
        await MainActor.run {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                boxSquash = 1.0
                boxRotation = 0
                shadowOpacity = 0.15
                shadowRadius = 12
                shadowScale = 0.85
            }
        }
        
        // 等待回正完成
        try? await Task.sleep(nanoseconds: 400_000_000)
        
        // 顯示進度條
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.3)) {
                showProgress = true
            }
        }
        
        // 開始載入資料
        await loadData()
    }
    
    private func loadData() async {
        // 階段 1: 開始
        await animateProgress(to: 0.3)
        
        // 階段 2: 載入資料
        await preloadPackageData()
        await animateProgress(to: 0.8)
        
        // 階段 3: 完成
        await animateProgress(to: 1.0)
        
        // 短暫延遲後進入主畫面
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        await MainActor.run {
            onLoadingComplete()
        }
    }
    
    private func animateProgress(to value: Double) async {
        let steps = 20
        let stepDuration: UInt64 = 15_000_000 // 15ms per step
        let increment = (value - progress) / Double(steps)
        
        for _ in 0..<steps {
            await MainActor.run {
                withAnimation(.linear(duration: 0.015)) {
                    progress += increment
                }
            }
            try? await Task.sleep(nanoseconds: stepDuration)
        }
        
        await MainActor.run {
            progress = value
        }
    }
    
    /// 預載包裹資料
    private func preloadPackageData() async {
        // 觸發 SwiftData 查詢，讓資料預載到記憶體
        let descriptor = FetchDescriptor<Package>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        
        do {
            let _ = try modelContext.fetch(descriptor)
        } catch {
            print("預載資料失敗: \(error.localizedDescription)")
        }
        
        // 模擬一些載入時間
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}

#Preview {
    SplashView {
        print("Loading complete")
    }
}
