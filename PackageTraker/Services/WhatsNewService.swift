//
//  WhatsNewService.swift
//  PackageTraker
//
//  從 Firebase Remote Config 讀取版本更新內容，啟動時顯示 What's New
//

import Foundation
import FirebaseRemoteConfig

/// What's New 資料模型
struct WhatsNewData: Identifiable {
    let id = UUID()
    let targetVersion: String
    let emoji: String
    let features: [String]

    /// 從 JSON 字串解析，自動根據語系選擇對應功能列表
    static func from(jsonString: String) -> WhatsNewData? {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let targetVersion = dict["targetVersion"] as? String,
              let featuresMap = dict["features"] as? [String: [String]] else {
            return nil
        }

        let emoji = dict["emoji"] as? String ?? "✨"
        let localizedFeatures = Self.resolveFeatures(from: featuresMap)

        guard !localizedFeatures.isEmpty else { return nil }

        return WhatsNewData(
            targetVersion: targetVersion,
            emoji: emoji,
            features: localizedFeatures
        )
    }

    /// 根據當前語系從 features map 選擇對應語言
    private static func resolveFeatures(from map: [String: [String]]) -> [String] {
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"

        if languageCode == "zh" {
            // 區分繁體/簡體
            let script = Locale.current.language.script?.identifier ?? "Hant"
            let key = script == "Hans" ? "zh-Hans" : "zh-Hant"
            if let features = map[key], !features.isEmpty { return features }
            // fallback: 嘗試另一個中文變體
            let fallbackKey = script == "Hans" ? "zh-Hant" : "zh-Hans"
            if let features = map[fallbackKey], !features.isEmpty { return features }
        }

        if let features = map[languageCode], !features.isEmpty { return features }

        // fallback to English
        return map["en"] ?? []
    }
}

/// 從 Firebase Remote Config 檢查是否有新版本更新內容
final class WhatsNewService {
    static let shared = WhatsNewService()
    private init() {}

    private let seenVersionKey = "lastSeenWhatsNewVersion"
    private let remoteConfigKey = "whats_new"

    /// 檢查是否有未讀的 What's New 內容
    /// - Returns: `WhatsNewData` 如果有未讀更新，否則 `nil`
    func checkWhatsNew() async -> WhatsNewData? {
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600 // 1 小時快取
        remoteConfig.configSettings = settings

        do {
            let status = try await remoteConfig.fetchAndActivate()
            guard status == .successFetchedFromRemote || status == .successUsingPreFetchedData else {
                return nil
            }
        } catch {
            return nil
        }

        let jsonString = remoteConfig.configValue(forKey: remoteConfigKey).stringValue ?? ""
        guard !jsonString.isEmpty,
              let whatsNewData = WhatsNewData.from(jsonString: jsonString) else {
            return nil
        }

        // 只在版本完全匹配時顯示
        guard whatsNewData.targetVersion == AppConfiguration.appVersion else {
            return nil
        }

        // 已看過則不再顯示
        let lastSeen = UserDefaults.standard.string(forKey: seenVersionKey)
        guard lastSeen != whatsNewData.targetVersion else {
            return nil
        }

        return whatsNewData
    }

    /// 從 Remote Config 讀取資料（跳過版本匹配與已讀檢查，Debug 用）
    func fetchWhatsNewData() async -> WhatsNewData? {
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 0 // Debug 不快取
        remoteConfig.configSettings = settings

        do {
            let status = try await remoteConfig.fetchAndActivate()
            guard status == .successFetchedFromRemote || status == .successUsingPreFetchedData else {
                return nil
            }
        } catch {
            return nil
        }

        let jsonString = remoteConfig.configValue(forKey: remoteConfigKey).stringValue ?? ""
        guard !jsonString.isEmpty,
              let data = WhatsNewData.from(jsonString: jsonString) else {
            return nil
        }
        return data
    }

    /// 標記該版本的 What's New 為已讀
    func markAsSeen(version: String) {
        UserDefaults.standard.set(version, forKey: seenVersionKey)
    }

    /// 重置已讀狀態（Debug 用）
    func resetSeen() {
        UserDefaults.standard.removeObject(forKey: seenVersionKey)
    }

    /// 取得目前已讀版本（Debug 用）
    var lastSeenVersion: String? {
        UserDefaults.standard.string(forKey: seenVersionKey)
    }
}
