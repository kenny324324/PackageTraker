import SwiftUI
import SwiftData

/// 自定義啟動頁面
struct SplashView: View {
    @Environment(\.modelContext) private var modelContext
    var refreshService: PackageRefreshService

    @State private var progress: Double = 0
    @State private var boxOffset: CGFloat = -400 // 從畫面上方開始
    @State private var boxRotation: Double = -20 // 初始傾斜
    @State private var boxSquash: CGFloat = 1.0 // 壓扁效果
    @State private var shadowRadius: CGFloat = 0
    @State private var shadowOpacity: Double = 0
    @State private var shadowScale: CGFloat = 0.3
    @State private var showProgress = false
    @State private var isSyncing = false

    var onLoadingComplete: () -> Void

    /// 動態載入文字
    private var loadingText: String {
        if isSyncing {
            return String(localized: "splash.syncing")
        } else if progress >= 0.9 {
            return String(localized: "splash.almostDone")
        } else {
            return String(localized: "splash.loading")
        }
    }

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

                    Text(loadingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: loadingText)
                }
                .padding(.bottom, 80)
                .opacity(showProgress ? 1 : 0)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await startAnimation()
        }
        .onChange(of: refreshService.batchProgress) { _, newValue in
            // 將 API 進度（0~1）映射到進度條的 0.3~0.9 區間
            let mappedProgress = 0.3 + (newValue * 0.6)
            withAnimation(.linear(duration: 0.1)) {
                progress = min(mappedProgress, 0.9)
            }
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
        // 階段 1: SwiftData 預載
        await animateProgress(to: 0.3)
        let activePackages = await preloadPackageData()

        // 階段 2: API 刷新（帶 10 秒 timeout）
        if !activePackages.isEmpty {
            isSyncing = true
            await refreshService.refreshAllWithTimeout(
                activePackages,
                in: modelContext,
                timeout: 10.0,
                maxConcurrent: 3
            )
            isSyncing = false
        }
        // 進度由 .onChange(of: refreshService.batchProgress) 驅動

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

    /// 預載包裹資料，回傳需要 API 刷新的包裹
    private func preloadPackageData() async -> [Package] {
        let descriptor = FetchDescriptor<Package>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )

        do {
            let packages = try modelContext.fetch(descriptor)
            // 回傳未完成的包裹（需要 API 刷新）
            return packages.filter { !$0.status.isCompleted }
        } catch {
            print("預載資料失敗: \(error.localizedDescription)")
            return []
        }
    }
}

#Preview {
    SplashView(refreshService: PackageRefreshService()) {
        print("Loading complete")
    }
}
