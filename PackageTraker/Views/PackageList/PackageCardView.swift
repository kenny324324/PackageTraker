import SwiftUI

/// 包裹卡片視圖
struct PackageCardView: View {
    let package: Package
    var namespace: Namespace.ID?
    var onTap: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 12) {
                // 頂部：Logo + 狀態/價格
                HStack(alignment: .top, spacing: 12) {
                    CarrierLogoView(carrier: package.carrier, size: 40)

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 6) {
                        StatusBadgeView(
                            status: package.status,
                            showText: true,
                            showCheckbox: package.status.isPendingPickup
                        )
                        
                        // 價格標籤
                        if let amount = package.formattedAmount {
                            Text(amount)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // 品名 或 取件碼/單號
                Text(package.cardMainText)
                    .font(.system(size: 22, weight: .bold, design: package.customName != nil ? .default : .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // 底部：地點 + 訂單日期
                HStack {
                    Text(package.displayPickupLocation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                    
                    // 訂單成立日期
                    Text(package.formattedOrderCreatedTime)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .adaptiveInteractiveCardStyle()
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.appAccent.opacity(package.status == .arrivedAtStore ? 0.7 : 0), lineWidth: 1.5)
            )
            .overlay(
                // 內陰影：邊緣向內發光
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.appAccent.opacity(package.status == .arrivedAtStore ? 0.6 : 0), lineWidth: 4)
                    .blur(radius: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .shadow(color: Color.appAccent.opacity(package.status == .arrivedAtStore ? 1.0 : 0), radius: 4, x: 0, y: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(String(localized: "common.edit")) {
                onEdit?()
            }
            Button(String(localized: "common.delete"), role: .destructive) {
                onDelete?()
            }
        }
        .modifier(HeroTransitionModifier(id: package.id, namespace: namespace))
    }
}

/// Hero 轉場修飾符
struct HeroTransitionModifier: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?
    
    func body(content: Content) -> some View {
        if let namespace = namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// 簡化版包裹卡片（用於更緊湊的顯示）
struct CompactPackageCard: View {
    let package: Package
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(alignment: .center, spacing: 12) {
                CarrierLogoView(carrier: package.carrier, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(package.displayName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(package.displayCode)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    StatusIconBadge(status: package.status)

                    // 顯示訂單成立時間
                    Text(package.formattedOrderCreatedTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("所有狀態") {
    ScrollView {
        VStack(spacing: 16) {
            // 待出貨 - 灰色
            PackageCardView(
                package: Package(
                    trackingNumber: "TW123456789H",
                    carrier: .shopee,
                    customName: "藍牙耳機",
                    pickupLocation: "全家福美店",
                    status: .pending,
                    amount: 599
                )
            )
            
            // 已出貨 - 橘色
            PackageCardView(
                package: Package(
                    trackingNumber: "N01234567890",
                    carrier: .sevenEleven,
                    customName: "手機殼",
                    pickupLocation: "7-11 景安店",
                    status: .shipped,
                    amount: 299
                )
            )
            
            // 配送中 - 藍色
            PackageCardView(
                package: Package(
                    trackingNumber: "15326511523",
                    carrier: .familyMart,
                    customName: "充電線",
                    pickupLocation: "全家中和店",
                    status: .inTransit,
                    amount: 199
                )
            )
            
            // 已到貨 - 綠色
            PackageCardView(
                package: Package(
                    trackingNumber: "OK123456789",
                    carrier: .okMart,
                    customName: "保護貼",
                    pickupCode: "6-5-29-14",
                    pickupLocation: "OK 景安店",
                    status: .arrivedAtStore,
                    amount: 99
                )
            )
            
            // 已取貨 - 綠色
            PackageCardView(
                package: Package(
                    trackingNumber: "TW999888777H",
                    carrier: .shopee,
                    customName: "行動電源",
                    pickupLocation: "全家福美店",
                    status: .delivered,
                    amount: 899
                )
            )
        }
        .padding()
    }
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}

#Preview("無品名/價格") {
    VStack(spacing: 16) {
        PackageCardView(
            package: Package(
                trackingNumber: "TW268979373141Z",
                carrier: .shopee,
                pickupLocation: "蝦皮店到店",
                status: .arrivedAtStore
            )
        )
        
        PackageCardView(
            package: Package(
                trackingNumber: "N01856100569",
                carrier: .sevenEleven,
                pickupLocation: "7-ELEVEN",
                status: .inTransit
            )
        )
    }
    .padding()
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
