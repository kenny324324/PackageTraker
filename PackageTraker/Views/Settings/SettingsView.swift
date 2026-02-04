import SwiftUI
import SwiftData
import StoreKit

/// 更新頻率選項
enum RefreshInterval: String, CaseIterable {
    case fifteenMinutes = "15min"
    case thirtyMinutes = "30min"
    case oneHour = "1hour"
    case twoHours = "2hours"
    case fourHours = "4hours"
    case manual = "manual"
    
    var displayName: String {
        switch self {
        case .fifteenMinutes: return String(localized: "interval.15min")
        case .thirtyMinutes: return String(localized: "interval.30min")
        case .oneHour: return String(localized: "interval.1hour")
        case .twoHours: return String(localized: "interval.2hours")
        case .fourHours: return String(localized: "interval.4hours")
        case .manual: return String(localized: "interval.manual")
        }
    }
    
    var seconds: TimeInterval {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .fourHours: return 4 * 60 * 60
        case .manual: return 0
        }
    }
}

/// 設定頁面
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview

    @Query private var linkedAccounts: [LinkedEmailAccount]

    @StateObject private var gmailAuthManager = GmailAuthManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var notificationsEnabled = true
    @State private var arrivalNotificationEnabled = true
    @State private var pickupReminderEnabled = true
    @State private var showClearDataConfirmation = false
    @AppStorage("refreshInterval") private var refreshInterval: RefreshInterval = .thirtyMinutes
    
    // App 資訊
    private let appName = "取貨吧"
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let developerName = "Kenny"
    private let feedbackEmail = "kenny@example.com"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 一般設定
                    generalSection
                    
                    // 通知設定
                    notificationSection

                    // 資料管理
                    dataManagementSection
                    
                    // 關於區塊
                    aboutSection
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .adaptiveBackground()
            .navigationTitle(String(localized: "settings.title"))
            .toolbarTitleDisplayMode(.inlineLarge)
            .confirmationDialog(
                String(localized: "settings.clearDataConfirm"),
                isPresented: $showClearDataConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "common.clear"), role: .destructive) {
                    clearAllData()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings.clearDataMessage"))
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.about"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                // App 資訊頭部
                HStack(spacing: 16) {
                    // App Icon
                    Image("SplashIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appName)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Version \(appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(16)
                
                Divider()
                    .background(Color.cardBackground)
                
                // 開發者
                settingsRow(
                    icon: "person.fill",
                    iconColor: .white,
                    title: String(localized: "settings.developer"),
                    value: developerName
                )

                Divider()
                    .background(Color.cardBackground)

                // 給予評分
                Button {
                    requestReview()
                } label: {
                    settingsRowButton(
                        icon: "star.fill",
                        iconColor: .white,
                        title: String(localized: "settings.rateApp")
                    )
                }

                Divider()
                    .background(Color.cardBackground)

                // 回報問題
                Button {
                    openFeedbackEmail()
                } label: {
                    settingsRowButton(
                        icon: "envelope.fill",
                        iconColor: .white,
                        title: String(localized: "settings.reportIssue")
                    )
                }
                
                Divider()
                    .background(Color.cardBackground)
                
                // 隱私政策
                Link(destination: URL(string: "https://example.com/privacy")!) {
                    settingsRowButton(
                        icon: "hand.raised.fill",
                        iconColor: .white,
                        title: String(localized: "settings.privacyPolicy")
                    )
                }
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - General Section
    
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.general"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                // 主題顏色
                NavigationLink(destination: ThemeSettingsView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 28)
                        
                        Text(String(localized: "settings.themeColor"))
                            .foregroundStyle(.white)
                        
                        Spacer()
                        
                        Circle()
                            .fill(themeManager.currentColor)
                            .frame(width: 24, height: 24)
                    }
                    .padding(16)
                }
                
                Divider()
                    .background(Color.cardBackground)
                
                // 語言設定
                Button {
                    openAppSettings()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 28)
                        
                        Text(String(localized: "settings.language"))
                            .foregroundStyle(.white)
                        
                        Spacer()
                        
                        Text(currentLanguage)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.3))
                            .clipShape(Capsule())
                    }
                    .padding(16)
                }
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - Notification Section

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.notifications"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                settingsToggleRow(
                    icon: "bell.fill",
                    iconColor: .white,
                    title: String(localized: "settings.pushNotification"),
                    isOn: $notificationsEnabled
                )

                Divider()
                    .background(Color.cardBackground)

                settingsToggleRow(
                    icon: "shippingbox.fill",
                    iconColor: .white,
                    title: String(localized: "settings.arrivalNotification"),
                    isOn: $arrivalNotificationEnabled
                )

                Divider()
                    .background(Color.cardBackground)

                settingsToggleRow(
                    icon: "clock.fill",
                    iconColor: .white,
                    title: String(localized: "settings.pickupReminder"),
                    isOn: $pickupReminderEnabled
                )
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(String(localized: "settings.notificationHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Management Section

    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.dataManagement"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                // 更新頻率
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 28)
                    
                    Text(String(localized: "settings.refreshInterval"))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Menu {
                        ForEach(RefreshInterval.allCases, id: \.self) { interval in
                            Button {
                                refreshInterval = interval
                            } label: {
                                if refreshInterval == interval {
                                    Label(interval.displayName, systemImage: "checkmark")
                                } else {
                                    Text(interval.displayName)
                                }
                            }
                        }
                    } label: {
                        Text(refreshInterval.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.3))
                            .clipShape(Capsule())
                    }
                }
                .padding(16)
                
                Divider()
                    .background(Color.cardBackground)
                
                // 清除所有資料
                Button {
                    showClearDataConfirmation = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.red)
                            .frame(width: 28)
                        
                        Text(String(localized: "settings.clearData"))
                            .foregroundStyle(.red)
                        
                        Spacer()
                    }
                    .padding(16)
                }
            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - Helper Views
    
    private func settingsRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            
            Text(title)
                .foregroundStyle(.white)
            
            Spacer()
            
            Text(value)
                .foregroundStyle(Color.appAccent)
        }
        .padding(16)
    }
    
    private func settingsRowButton(icon: String, iconColor: Color, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            
            Text(title)
                .foregroundStyle(.white)
            
            Spacer()
        }
        .padding(16)
    }
    
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
    
    // MARK: - Computed Properties
    
    private var currentLanguage: String {
        let preferredLanguage = Locale.preferredLanguages.first ?? "zh-Hant"
        if preferredLanguage.starts(with: "zh-Hant") {
            return String(localized: "language.traditionalChinese")
        } else if preferredLanguage.starts(with: "zh-Hans") {
            return String(localized: "language.simplifiedChinese")
        } else if preferredLanguage.starts(with: "en") {
            return String(localized: "language.english")
        } else {
            return String(localized: "language.traditionalChinese")
        }
    }

    // MARK: - Actions
    
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openFeedbackEmail() {
        let subject = "[\(appName)] 問題回報"
        let body = "\n\n---\nApp Version: \(appVersion)\niOS Version: \(UIDevice.current.systemVersion)\nDevice: \(UIDevice.current.model)"
        
        if let url = URL(string: "mailto:\(feedbackEmail)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            UIApplication.shared.open(url)
        }
    }

    private func clearAllData() {
        // 登出 Gmail
        gmailAuthManager.signOut()

        // 刪除所有 LinkedEmailAccount
        for account in linkedAccounts {
            modelContext.delete(account)
        }

        try? modelContext.save()
    }
}

// MARK: - Previews

#Preview {
    SettingsView()
        .modelContainer(for: [Package.self, TrackingEvent.self, LinkedEmailAccount.self], inMemory: true)
}
