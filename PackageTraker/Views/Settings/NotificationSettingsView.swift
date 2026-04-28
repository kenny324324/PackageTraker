//
//  NotificationSettingsView.swift
//  PackageTraker
//
//  推播通知細項設定頁面
//

import SwiftUI
import UserNotifications
import UIKit

/// 推播通知細項設定
struct NotificationSettingsView: View {
    @AppStorage("arrivalNotificationEnabled") private var arrivalNotificationEnabled = true
    @AppStorage("shippedNotificationEnabled") private var shippedNotificationEnabled = true
    @AppStorage("pickupReminderEnabled") private var pickupReminderEnabled = true

    @State private var systemAuthStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 系統權限提示橫幅（拒絕或未授權時顯示）
                permissionBanner

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
                .opacity(systemAuthStatus == .denied ? 0.4 : 1)
                .allowsHitTesting(systemAuthStatus != .denied)

                // Footer 說明：解釋推播觸發時機
                Text(String(localized: "settings.notification.footer"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)

                #if DEBUG
                // 診斷入口（DEBUG only — 上線版本不會顯示給使用者）
                NavigationLink {
                    NotificationDiagnosticView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "stethoscope")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 28)
                        Text(String(localized: "diagnostic.title"))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .background(Color.secondaryCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                #endif
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .adaptiveBackground()
        .navigationTitle(String(localized: "settings.notificationSettings"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await refreshSystemStatus() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshSystemStatus() }
        }
        .onChange(of: arrivalNotificationEnabled) { _, _ in
            FirebasePushService.shared.syncDeviceNotificationSettingsInBackground()
        }
        .onChange(of: shippedNotificationEnabled) { _, _ in
            FirebasePushService.shared.syncDeviceNotificationSettingsInBackground()
        }
        .onChange(of: pickupReminderEnabled) { _, _ in
            FirebasePushService.shared.syncDeviceNotificationSettingsInBackground()
        }
    }

    // MARK: - Permission Banner

    @ViewBuilder
    private var permissionBanner: some View {
        switch systemAuthStatus {
        case .denied:
            bannerView(
                icon: "exclamationmark.triangle.fill",
                tint: .red,
                title: String(localized: "settings.notification.permissionDenied.title"),
                body: String(localized: "settings.notification.permissionDenied.body"),
                actionTitle: String(localized: "diagnostic.openSystemSettings"),
                action: openSystemSettings
            )
        case .notDetermined:
            bannerView(
                icon: "bell.badge.fill",
                tint: .orange,
                title: String(localized: "settings.notification.permissionNeeded.title"),
                body: String(localized: "settings.notification.permissionNeeded.body"),
                actionTitle: String(localized: "settings.notification.allowNow"),
                action: requestPermission
            )
        default:
            EmptyView()
        }
    }

    private func bannerView(
        icon: String,
        tint: Color,
        title: String,
        body: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.bold())
            }
            Text(body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Text(actionTitle)
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(tint, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func refreshSystemStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            systemAuthStatus = settings.authorizationStatus
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func requestPermission() {
        Task {
            await FirebasePushService.shared.registerForPushNotifications()
            await refreshSystemStatus()
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
