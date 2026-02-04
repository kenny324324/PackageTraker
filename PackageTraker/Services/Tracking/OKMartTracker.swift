import Foundation

/// OK 超商追蹤服務
/// 參考：https://github.com/NCNU-OpenSource/parcel-tracker
final class OKMartTracker: TrackingServiceProtocol {

    var supportedCarriers: [Carrier] {
        [.okMart]
    }

    private let validateURL = URL(string: "https://ecservice.okmart.com.tw/Tracking/ValidateNumber.ashx")!
    private let resultURL = URL(string: "https://ecservice.okmart.com.tw/Tracking/Result")!

    // 使用獨立的 session 來保持 cookie
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()

    func track(number: String, carrier: Carrier) async throws -> TrackingResult {
        guard carrier == .okMart else {
            throw TrackingError.unsupportedCarrier(carrier)
        }

        // Step 1: 取得驗證碼
        let validationCode = try await getValidationCode(orderID: number)

        // Step 2: 查詢結果
        return try await fetchResult(orderID: number, validationCode: validationCode)
    }

    // MARK: - Private

    private func getValidationCode(orderID: String) async throws -> String {
        var components = URLComponents(url: validateURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "inputOdNo", value: orderID)
        ]

        guard let url = components.url else {
            throw TrackingError.invalidTrackingNumber
        }

        let request = URLRequest(url: url)
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TrackingError.invalidResponse
        }

        // 從 Set-Cookie header 提取驗證碼
        // Cookie 格式類似: "ValidCode=XXXXX; ..."
        if let cookies = httpResponse.value(forHTTPHeaderField: "Set-Cookie") {
            // 使用 regex 提取 5 字元驗證碼
            let pattern = "ValidCode=([A-Za-z0-9]{5})"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: cookies, range: NSRange(cookies.startIndex..., in: cookies)),
               let range = Range(match.range(at: 1), in: cookies) {
                return String(cookies[range])
            }
        }

        throw TrackingError.parsingError(message: "無法取得 OK 超商驗證碼")
    }

    private func fetchResult(orderID: String, validationCode: String) async throws -> TrackingResult {
        var components = URLComponents(url: resultURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "inputOdNo", value: orderID),
            URLQueryItem(name: "inputCode1", value: validationCode)
        ]

        guard let url = components.url else {
            throw TrackingError.invalidTrackingNumber
        }

        let request = URLRequest(url: url)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TrackingError.invalidResponse
        }

        let rawString = String(data: data, encoding: .utf8) ?? ""
        return try parseHTMLResponse(rawString, trackingNumber: orderID)
    }

    private func parseHTMLResponse(_ html: String, trackingNumber: String) throws -> TrackingResult {
        // OK 超商回傳 HTML，需要解析
        // 這裡用簡單的字串匹配，不需要 SwiftSoup

        // 檢查是否有錯誤訊息
        if html.contains("查無此筆資料") || html.contains("查詢失敗") {
            throw TrackingError.trackingNumberNotFound
        }

        // 嘗試提取狀態
        var status = TrackingStatus.pending
        var statusDescription = ""
        var storeName: String?

        // 常見狀態關鍵字
        if html.contains("已到店") || html.contains("待取件") {
            status = .arrivedAtStore
            statusDescription = "已到店待取件"
        } else if html.contains("已取件") || html.contains("取件完成") {
            status = .delivered
            statusDescription = "已取件完成"
        } else if html.contains("配送中") || html.contains("運送中") {
            status = .inTransit
            statusDescription = "配送中"
        } else if html.contains("已寄件") {
            status = .shipped
            statusDescription = "已寄件"
        }

        // 嘗試提取店名 (通常在 class="store" 或類似的元素中)
        if let storeMatch = extractBetween(html, prefix: "取件門市", suffix: "<") {
            storeName = storeMatch.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "：", with: "")
                .replacingOccurrences(of: ":", with: "")
        }

        // 建立事件
        let events: [TrackingEventDTO] = [
            TrackingEventDTO(
                timestamp: Date(),
                status: status,
                description: statusDescription,
                location: storeName
            )
        ]

        return TrackingResult(
            trackingNumber: trackingNumber,
            carrier: .okMart,
            currentStatus: status,
            events: events,
            rawResponse: html
        )
    }

    private func extractBetween(_ string: String, prefix: String, suffix: String) -> String? {
        guard let prefixRange = string.range(of: prefix) else { return nil }
        let startIndex = prefixRange.upperBound
        let remaining = string[startIndex...]
        guard let suffixRange = remaining.range(of: suffix) else { return nil }
        return String(remaining[..<suffixRange.lowerBound])
    }
}
