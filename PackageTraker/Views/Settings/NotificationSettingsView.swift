//
//  NotificationSettingsView.swift
//  PackageTraker
//
//  推播通知細項設定頁面
//

import SwiftUI

/// 推播通知細項設定
struct NotificationSettingsView: View {
    @AppStorage("arrivalNotificationEnabled") private var arrivalNotificationEnabled = false
    @AppStorage("shippedNotificationEnabled") private var shippedNotificationEnabled = false
    @AppStorage("pickupReminderEnabled") private var pickupReminderEnabled = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 0) {
                    // 到貨通知
                    settingsToggleRow(
                        icon: "shippingbox.fill",
                        iconColor: .white,
                        title: String(localized: "settings.arrivalNotification"),
                        isOn: $arrivalNotificationEnabled
                    )

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // 出貨通知
                    settingsToggleRow(
                        icon: "truck.box.fill",
                        iconColor: .white,
                        title: String(localized: "settings.shippedNotification"),
                        isOn: $shippedNotificationEnabled
                    )

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // 取貨提醒
                    settingsToggleRow(
                        icon: "clock.fill",
                        iconColor: .white,
                        title: String(localized: "settings.pickupReminder"),
                        isOn: $pickupReminderEnabled
                    )
                }
                .background(Color.secondaryCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .adaptiveBackground()
        .navigationTitle(String(localized: "settings.notificationSettings"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onChange(of: arrivalNotificationEnabled) { _, _ in
            FirebasePushService.shared.syncDeviceNotificationSettings()
        }
        .onChange(of: shippedNotificationEnabled) { _, _ in
            FirebasePushService.shared.syncDeviceNotificationSettings()
        }
        .onChange(of: pickupReminderEnabled) { _, _ in
            FirebasePushService.shared.syncDeviceNotificationSettings()
        }
    }

    // MARK: - Helper Views

    private func settingsToggleRow(icon: String, iconColor: Color, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 28)

            Toggle(title, isOn: isOn)
                .tint(Color.appAccent)
        }
        .padding(16)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
