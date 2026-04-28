//
//  NotificationDiagnosticView.swift
//  PackageTraker
//
//  推播通知診斷頁：協助使用者排查「為什麼收不到推播」
//

import SwiftUI
import UserNotifications
import UIKit

/// 推播通知診斷
struct NotificationDiagnosticView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("arrivalNotificationEnabled") private var arrivalNotificationEnabled = true
    @AppStorage("shippedNotificationEnabled") private var shippedNotificationEnabled = true
    @AppStorage("pickupReminderEnabled") private var pickupReminderEnabled = true

    @ObservedObject private var pushService = FirebasePushService.shared

    @State private var systemAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var remoteSettings: RemoteNotificationSettings?
    @State private var isLoadingRemote = false
    @State private var isResyncing = false
    @State private var resyncMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 說明區塊
                explanationCard

                // 檢查項目
                VStack(spacing: 0) {
                    diagnosticRow(
                        title: String(localized: "diagnostic.systemPermission"),
                        status: systemPermissionStatus,
                        action: systemPermissionAction
                    )

                    Divider().background(Color.white.opacity(0.1))

                    diagnosticRow(
                        title: String(localized: "diagnostic.appToggle"),
                        status: appTogglesStatus,
                        action: nil
                    )

                    Divider().background(Color.white.opacity(0.1))

                    diagnosticRow(
                        title: String(localized: "diagnostic.fcmToken"),
                        status: fcmTokenStatus,
                        action: nil
                    )

                    Divider().background(Color.white.opacity(0.1))

                    diagnosticRow(
                        title: String(localized: "diagnostic.serverSettings"),
                        status: serverSettingsStatus,
                        action: serverSettingsAction
                    )
                }
                .background(Color.secondaryCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                // 重試按鈕
                Button {
                    Task {
                        await pushService.registerForPushNotifications()
                        await loadRemote()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(String(localized: "diagnostic.retryRegistration"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.appAccent.opacity(0.2))
                    .foregroundStyle(Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 4)

                if let msg = resyncMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.contains("✅") ? .green : .red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .adaptiveBackground()
        .navigationTitle(String(localized: "diagnostic.title"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task {
            await refreshSystemStatus()
            await loadRemote()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshSystemStatus()
                await loadRemote()
            }
        }
    }

    // MARK: - Subviews

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.appAccent)
                Text(String(localized: "diagnostic.howItWorks.title"))
                    .font(.headline)
            }
            Text(String(localized: "diagnostic.howItWorks.body"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondaryCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func diagnosticRow(
        title: String,
        status: DiagnosticStatus,
        action: DiagnosticAction?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: status.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(status.color)
                    .frame(width: 24)

                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                Text(status.label)
                    .font(.caption.bold())
                    .foregroundStyle(status.color)
            }
            if let detail = status.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 36)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action = action {
                Button(action: action.handler) {
                    HStack(spacing: 4) {
                        Text(action.title)
                            .font(.caption.bold())
                        if action.isLoading {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                    .foregroundStyle(Color.appAccent)
                }
                .disabled(action.isLoading)
                .padding(.leading, 36)
            }
        }
        .padding(16)
    }

    // MARK: - Computed States

    private var systemPermissionStatus: DiagnosticStatus {
        switch systemAuthStatus {
        case .authorized, .ephemeral, .provisional:
            return .ok(label: String(localized: "diagnostic.status.granted"))
        case .denied:
            return .bad(
                label: String(localized: "diagnostic.status.denied"),
                detail: String(localized: "diagnostic.systemPermission.deniedDetail")
            )
        case .notDetermined:
            return .warn(
                label: String(localized: "diagnostic.status.notDetermined"),
                detail: String(localized: "diagnostic.systemPermission.notDeterminedDetail")
            )
        @unknown default:
            return .warn(label: String(localized: "diagnostic.status.unknown"), detail: nil)
        }
    }

    private var systemPermissionAction: DiagnosticAction? {
        guard systemAuthStatus == .denied else { return nil }
        return DiagnosticAction(
            title: String(localized: "diagnostic.openSystemSettings")
        ) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    private var appTogglesStatus: DiagnosticStatus {
        let allOn = arrivalNotificationEnabled && shippedNotificationEnabled && pickupReminderEnabled
        if !notificationsEnabled {
            return .bad(
                label: String(localized: "diagnostic.status.off"),
                detail: String(localized: "diagnostic.appToggle.offDetail")
            )
        }
        if !allOn {
            // 列出哪些被關掉
            var disabled: [String] = []
            if !arrivalNotificationEnabled { disabled.append(String(localized: "settings.arrivalNotification")) }
            if !shippedNotificationEnabled { disabled.append(String(localized: "settings.shippedNotification")) }
            if !pickupReminderEnabled { disabled.append(String(localized: "settings.pickupReminder")) }
            let detail = String(format: String(localized: "diagnostic.appToggle.partialOffDetail"),
                                disabled.joined(separator: "、"))
            return .warn(
                label: String(localized: "diagnostic.status.partialOn"),
                detail: detail
            )
        }
        return .ok(label: String(localized: "diagnostic.status.on"))
    }

    private var fcmTokenStatus: DiagnosticStatus {
        if let token = pushService.fcmToken, !token.isEmpty {
            return .ok(
                label: String(localized: "diagnostic.status.registered"),
                detail: String(token.prefix(16)) + "…"
            )
        }
        return .warn(
            label: String(localized: "diagnostic.status.notRegistered"),
            detail: String(localized: "diagnostic.fcmToken.missingDetail")
        )
    }

    private var serverSettingsStatus: DiagnosticStatus {
        if isLoadingRemote {
            return .warn(
                label: String(localized: "diagnostic.status.loading"),
                detail: nil
            )
        }
        guard let remote = remoteSettings else {
            return .bad(
                label: String(localized: "diagnostic.status.notFound"),
                detail: String(localized: "diagnostic.serverSettings.notFoundDetail")
            )
        }
        if remote.matchesLocal() {
            let detailLines: [String] = [
                "\(String(localized: "settings.arrivalNotification")): \(remote.arrivalNotification ? "✓" : "✗")",
                "\(String(localized: "settings.shippedNotification")): \(remote.shippedNotification ? "✓" : "✗")",
                "\(String(localized: "settings.pickupReminder")): \(remote.pickupReminder ? "✓" : "✗")",
                lastUploadDetail(remote.lastTokenUploadAt)
            ]
            return .ok(
                label: String(localized: "diagnostic.status.synced"),
                detail: detailLines.joined(separator: "\n")
            )
        } else {
            return .bad(
                label: String(localized: "diagnostic.status.outOfSync"),
                detail: String(localized: "diagnostic.serverSettings.outOfSyncDetail")
            )
        }
    }

    private var serverSettingsAction: DiagnosticAction? {
        // 不一致 / 找不到 / 載入完成都顯示重新同步按鈕
        guard !isLoadingRemote else { return nil }
        let needsResync = remoteSettings == nil || (remoteSettings?.matchesLocal() == false)
        guard needsResync else { return nil }
        return DiagnosticAction(
            title: String(localized: "diagnostic.forceResync"),
            isLoading: isResyncing
        ) {
            Task { await forceResync() }
        }
    }

    private func lastUploadDetail(_ date: Date?) -> String {
        guard let date = date else {
            return String(localized: "diagnostic.lastUpload.unknown")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return String(format: String(localized: "diagnostic.lastUpload.format"),
                      formatter.string(from: date))
    }

    // MARK: - Actions

    private func refreshSystemStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            systemAuthStatus = settings.authorizationStatus
        }
    }

    private func loadRemote() async {
        isLoadingRemote = true
        let result = await pushService.fetchRemoteNotificationSettings()
        await MainActor.run {
            remoteSettings = result
            isLoadingRemote = false
        }
    }

    private func forceResync() async {
        isResyncing = true
        resyncMessage = nil
        let ok = await pushService.uploadToken()
        await loadRemote()
        await MainActor.run {
            isResyncing = false
            resyncMessage = ok
                ? "✅ " + String(localized: "diagnostic.resync.success")
                : "❌ " + String(localized: "diagnostic.resync.failed")
        }
    }
}

// MARK: - Helper Types

private struct DiagnosticAction {
    let title: String
    var isLoading: Bool = false
    let handler: () -> Void
}

private enum DiagnosticStatus {
    case ok(label: String, detail: String? = nil)
    case warn(label: String, detail: String?)
    case bad(label: String, detail: String?)

    var label: String {
        switch self {
        case .ok(let label, _), .warn(let label, _), .bad(let label, _):
            return label
        }
    }

    var detail: String? {
        switch self {
        case .ok(_, let detail), .warn(_, let detail), .bad(_, let detail):
            return detail
        }
    }

    var color: Color {
        switch self {
        case .ok: return .green
        case .warn: return .orange
        case .bad: return .red
        }
    }

    var iconName: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.circle.fill"
        case .bad: return "xmark.circle.fill"
        }
    }
}

#Preview {
    NavigationStack {
        NotificationDiagnosticView()
    }
}
