//
//  GmailService.swift
//  PackageTraker
//
//  Gmail API 服務
//

import Foundation

/// Gmail API 服務
/// 負責與 Gmail API 通訊，取得郵件內容
final class GmailService {

    // MARK: - Constants

    private let baseURL = "https://gmail.googleapis.com/gmail/v1"

    // 搜尋物流相關郵件的 query
    // 同時搜尋主題和寄件者，涵蓋更多台灣物流郵件
    private let trackingSearchQuery = """
        (subject:(shipping OR tracking OR 物流 OR 配送 OR 到店 OR 取貨 OR 出貨 OR 寄送 OR 包裹 OR 訂單 OR 已送達 OR 派送 OR 賣貨便 OR 交貨便) OR from:(shopee OR momo OR pchome OR 7-11 OR myship OR family OR t-cat OR 黑貓 OR sfexpress)) newer_than:14d
        """

    // MARK: - Properties

    private let authManager: GmailAuthManager
    private let contentProcessor = EmailContentProcessor.shared

    // MARK: - Initialization

    init(authManager: GmailAuthManager = .shared) {
        self.authManager = authManager
    }

    // MARK: - Public Methods

    /// 取得物流相關郵件
    func fetchTrackingEmails(maxResults: Int = 50) async throws -> [GmailMessage] {
        let accessToken = try await authManager.getValidAccessToken()

        // 1. 搜尋郵件列表
        let messageIds = try await searchMessages(
            query: trackingSearchQuery,
            maxResults: maxResults,
            accessToken: accessToken
        )

        // 2. 取得每封郵件的詳細內容
        var messages: [GmailMessage] = []

        for messageId in messageIds {
            do {
                let message = try await fetchMessage(id: messageId, accessToken: accessToken)
                messages.append(message)
            } catch {
                // 單封郵件失敗不影響其他郵件
                print("Failed to fetch message \(messageId): \(error)")
                continue
            }
        }

        return messages
    }

    /// 使用自訂 query 搜尋郵件
    func searchEmails(query: String, maxResults: Int = 20) async throws -> [GmailMessage] {
        let accessToken = try await authManager.getValidAccessToken()

        let messageIds = try await searchMessages(
            query: query,
            maxResults: maxResults,
            accessToken: accessToken
        )

        var messages: [GmailMessage] = []

        for messageId in messageIds {
            do {
                let message = try await fetchMessage(id: messageId, accessToken: accessToken)
                messages.append(message)
            } catch {
                continue
            }
        }

        return messages
    }

    /// 取得最近 N 天的郵件
    func fetchRecentEmails(days: Int = 7, maxResults: Int = 50) async throws -> [GmailMessage] {
        let query = "newer_than:\(days)d"
        return try await searchEmails(query: query, maxResults: maxResults)
    }

    // MARK: - Private Methods

    private func searchMessages(query: String, maxResults: Int, accessToken: String) async throws -> [String] {
        var urlComponents = URLComponents(string: "\(baseURL)/users/me/messages")!
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]

        guard let url = urlComponents.url else {
            throw GmailError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        try handleHTTPResponse(response)

        let listResponse = try JSONDecoder().decode(MessageListResponse.self, from: data)

        return listResponse.messages?.map { $0.id } ?? []
    }

    private func fetchMessage(id: String, accessToken: String) async throws -> GmailMessage {
        var urlComponents = URLComponents(string: "\(baseURL)/users/me/messages/\(id)")!
        urlComponents.queryItems = [
            URLQueryItem(name: "format", value: "full")
        ]

        guard let url = urlComponents.url else {
            throw GmailError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        try handleHTTPResponse(response)

        let messageResponse = try JSONDecoder().decode(MessageResponse.self, from: data)

        return parseMessageResponse(messageResponse)
    }

    private func handleHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw GmailError.tokenRefreshFailed
        case 429:
            throw GmailError.rateLimited
        default:
            throw GmailError.networkError(underlying: NSError(
                domain: "GmailService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
            ))
        }
    }

    private func parseMessageResponse(_ response: MessageResponse) -> GmailMessage {
        let headers = response.payload?.headers ?? []

        // 提取郵件標頭
        let subject = headers.first { $0.name.lowercased() == "subject" }?.value ?? ""
        let from = headers.first { $0.name.lowercased() == "from" }?.value ?? ""
        let dateString = headers.first { $0.name.lowercased() == "date" }?.value ?? ""

        // 解析日期
        let receivedDate = parseEmailDate(dateString) ?? Date()

        // 提取郵件內容
        let body = extractBody(from: response.payload)

        return GmailMessage(
            id: response.id,
            threadId: response.threadId,
            subject: subject,
            sender: from,
            receivedDate: receivedDate,
            snippet: response.snippet ?? "",
            body: body
        )
    }

    private func extractBody(from payload: MessagePayload?) -> String {
        guard let payload = payload else { return "" }

        // 嘗試從 body.data 直接取得
        if let bodyData = payload.body?.data,
           let decoded = contentProcessor.decodeBase64Content(bodyData) {
            return decoded
        }

        // 從 parts 中尋找文字內容
        if let parts = payload.parts {
            for part in parts {
                let mimeType = part.mimeType ?? ""

                // 優先取得 text/html
                if mimeType == "text/html",
                   let bodyData = part.body?.data,
                   let decoded = contentProcessor.decodeBase64Content(bodyData) {
                    return decoded
                }

                // 其次取得 text/plain
                if mimeType == "text/plain",
                   let bodyData = part.body?.data,
                   let decoded = contentProcessor.decodeBase64Content(bodyData) {
                    return decoded
                }

                // 遞迴處理巢狀 parts
                if let nestedParts = part.parts {
                    for nestedPart in nestedParts {
                        if let bodyData = nestedPart.body?.data,
                           let decoded = contentProcessor.decodeBase64Content(bodyData) {
                            return decoded
                        }
                    }
                }
            }
        }

        return ""
    }

    private func parseEmailDate(_ dateString: String) -> Date? {
        // 嘗試常見的郵件日期格式
        let dateFormatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "dd MMM yyyy HH:mm:ss Z"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss ZZZZ"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }()
        ]

        for formatter in dateFormatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        // 嘗試 ISO8601 格式
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }

        // 嘗試不帶毫秒的 ISO8601
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }

        return nil
    }
}

// MARK: - Response Models

private struct MessageListResponse: Decodable {
    let messages: [MessageReference]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

private struct MessageReference: Decodable {
    let id: String
    let threadId: String
}

private struct MessageResponse: Decodable {
    let id: String
    let threadId: String
    let snippet: String?
    let payload: MessagePayload?
}

private struct MessagePayload: Decodable {
    let mimeType: String?
    let headers: [MessageHeader]?
    let body: MessageBody?
    let parts: [MessagePart]?
}

private struct MessageHeader: Decodable {
    let name: String
    let value: String
}

private struct MessageBody: Decodable {
    let size: Int?
    let data: String?
}

private struct MessagePart: Decodable {
    let mimeType: String?
    let body: MessageBody?
    let parts: [MessagePart]?
}
