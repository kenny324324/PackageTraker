import SwiftUI
import SpriteKit

/// SwiftUI 包裝：包裹罐子物理互動視圖
struct PackageJarView: View {
    let carriers: [Carrier]

    @State private var scene: PackageJarScene?
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady, let scene {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .frame(height: 300)
        .onAppear {
            if let scene {
                scene.resume()
            } else {
                prepareScene()
            }
        }
        .onDisappear {
            scene?.pause()
        }
    }

    /// 預先渲染紋理（批次處理），完成後建立 scene
    private func prepareScene() {
        let carrierList = carriers
        let diameter = PackageJarScene.ballDiameter(for: carrierList.count)
        let uniqueCarriers = Array(Set(carrierList))

        Task.detached(priority: .userInitiated) {
            // 一次性在 MainActor 批次渲染所有紋理（減少 main thread hop）
            let images: [(Carrier, UIImage?)] = await MainActor.run {
                let scale = UIScreen.main.scale
                return uniqueCarriers.map { carrier in
                    let view = CarrierLogoView(carrier: carrier, size: diameter)
                        .clipShape(Circle())
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = scale
                    return (carrier, renderer.uiImage)
                }
            }

            // 轉成 SKTexture（不需要 main thread）
            var cache: [Carrier: SKTexture] = [:]
            for (carrier, image) in images {
                if let image {
                    cache[carrier] = SKTexture(image: image)
                } else {
                    let s = CGSize(width: diameter, height: diameter)
                    let fallback = UIGraphicsImageRenderer(size: s).image { ctx in
                        UIColor(carrier.brandColor).setFill()
                        ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: s))
                    }
                    cache[carrier] = SKTexture(image: fallback)
                }
            }

            await MainActor.run {
                let newScene = PackageJarScene(carriers: carrierList, textureCache: cache)
                scene = newScene
                withAnimation(.easeIn(duration: 0.2)) {
                    isReady = true
                }
            }
        }
    }
}

// MARK: - Previews

#Preview {
    PackageJarView(carriers: [
        .shopee, .shopee, .shopee,
        .sevenEleven, .sevenEleven,
        .familyMart, .familyMart,
        .tcat, .hiLife, .postTW,
        .dhl, .fedex
    ])
    .padding()
    .adaptiveGradientBackground()
    .preferredColorScheme(.dark)
}
