//
//  ForceUpdateService.swift
//  PackageTraker
//
//  從 Firestore 讀取最低版本需求，判斷是否需要強制更新
//

import Foundation
import FirebaseFirestore

/// 強制更新檢查結果
enum UpdateRequirement: Equatable {
    case upToDate
    case forceUpdate(storeURL: String)
}

/// 從 Firestore `/config/app` 讀取最低版本，啟動時檢查
final class ForceUpdateService {
    static let shared = ForceUpdateService()
    private init() {}

    /// 檢查是否需要強制更新
    /// Firestore 文件：`/config/app`
    /// 欄位：`minimumVersion` (String, e.g. "1.2.0"), `storeURL` (String)
    func checkForUpdate() async -> UpdateRequirement {
        do {
            let doc = try await Firestore.firestore()
                .collection("config").document("app").getDocument()

            guard let data = doc.data(),
                  let minimumVersion = data["minimumVersion"] as? String else {
                return .upToDate
            }

            let storeURL = data["storeURL"] as? String
                ?? "https://apps.apple.com/app/id0000000000" // placeholder

            let currentVersion = AppConfiguration.appVersion

            if compareVersions(currentVersion, isOlderThan: minimumVersion) {
                return .forceUpdate(storeURL: storeURL)
            }

            return .upToDate
        } catch {
            // 檢查失敗不阻擋使用（寧可放行也不要擋住用戶）
            return .upToDate
        }
    }

    /// 語意化版本比較：current < minimum → true
    private func compareVersions(_ current: String, isOlderThan minimum: String) -> Bool {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let minimumParts = minimum.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(currentParts.count, minimumParts.count) {
            let c = i < currentParts.count ? currentParts[i] : 0
            let m = i < minimumParts.count ? minimumParts[i] : 0
            if c < m { return true }
            if c > m { return false }
        }
        return false
    }
}
