import SwiftUI

/// 物流商 Logo 元件（圖片優先，無圖片則顯示彩色方塊 + 縮寫）
struct CarrierLogoView: View {
    let carrier: Carrier
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let imageName = carrier.logoImageName {
                // 有 Logo 圖片時使用圖片
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
            } else {
                // 沒有圖片時使用文字縮寫
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.25)
                        .fill(carrier.brandColor)

                    Text(carrier.abbreviation)
                        .font(.system(size: size * 0.35, weight: .bold))
                        .foregroundStyle(carrier.textColor)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .frame(width: size, height: size)
            }
        }
    }
}

// MARK: - Previews

#Preview("All Carriers") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
            ForEach(Carrier.allCases) { carrier in
                VStack(spacing: 8) {
                    CarrierLogoView(carrier: carrier, size: 56)
                    Text(carrier.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}

#Preview("Sizes") {
    HStack(spacing: 20) {
        CarrierLogoView(carrier: .sfExpress, size: 32)
        CarrierLogoView(carrier: .sfExpress, size: 44)
        CarrierLogoView(carrier: .sfExpress, size: 56)
    }
    .padding()
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
