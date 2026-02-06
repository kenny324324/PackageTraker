//
//  TrackTwTokenStorage.swift
//  PackageTraker
//
//  Track.TW API Token（寫死於 Secrets.swift）
//

import Foundation

/// Track.TW API Token 管理
/// Token 寫死在 Secrets.swift，不需使用者設定
final class TrackTwTokenStorage {

    static let shared = TrackTwTokenStorage()

    private init() {}

    /// 取得 API Token
    func getToken() -> String? {
        let token = Secrets.trackTwAPIToken
        guard !token.isEmpty, token != "在這裡貼上你的 API Token" else {
            return nil
        }
        return token
    }

    /// 是否有可用的 Token
    var hasToken: Bool {
        return getToken() != nil
    }
}
