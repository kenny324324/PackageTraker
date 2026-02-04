import Foundation

/// Track.TW 網頁解析追蹤服務
/// 用於沒有直接 API 的物流商（如 7-11）
/// 網站：https://track.tw
final class TrackTwScraper: TrackingServiceProtocol {

    var supportedCarriers: [Carrier] {
        // 支援所有有 trackTwUUID 的物流商
        Carrier.allCases.filter { $0.trackTwUUID != nil }
    }

    private let baseURL = "https://track.tw/carrier"

    func track(number: String, carrier: Carrier) async throws -> TrackingResult {
        guard let uuid = carrier.trackTwUUID else {
            throw TrackingError.unsupportedCarrier(carrier)
        }

        // 建立 URL: https://track.tw/carrier/{uuid}/{trackingNumber}
        let urlString = "\(baseURL)/\(uuid)/\(number)"
        guard let url = URL(string: urlString) else {
            throw TrackingError.invalidTrackingNumber
        }

        print("=== Track.TW Request ===")
        print("URL: \(urlString)")

        // 建立 request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-TW,zh;q=0.9", forHTTPHeaderField: "Accept-Language")

        // 發送請求
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TrackingError.invalidResponse
        }

        print("HTTP Status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TrackingError.invalidResponse
        }

        // 解析 HTML
        let html = String(data: data, encoding: .utf8) ?? ""
        return try parseHTML(html, trackingNumber: number, carrier: carrier)
    }

    // MARK: - HTML 解析

    private func parseHTML(_ html: String, trackingNumber: String, carrier: Carrier) throws -> TrackingResult {
        print("=== Track.TW Response ===")
        print("HTML 長度: \(html.count)")

        // 檢查是否找到包裹
        if html.contains("找不到此包裹") || html.contains("查無資料") || html.contains("No tracking") {
            print("❌ 找不到包裹")
            throw TrackingError.trackingNumberNotFound
        }

        // 解析狀態和事件
        var events: [TrackingEventDTO] = []
        var currentStatus: TrackingStatus = .pending
        var latestMessage: String?

        // 嘗試解析追蹤事件列表
        // Track.TW 的 HTML 結構中，事件通常在 <div class="tracking-item"> 或類似結構中
        let eventBlocks = extractEventBlocks(from: html)

        print("找到 \(eventBlocks.count) 個事件區塊")

        for block in eventBlocks {
            if let event = parseEventBlock(block) {
                events.append(event)
                if latestMessage == nil {
                    latestMessage = event.description
                    currentStatus = event.status
                }
            }
        }

        // 如果沒有解析到事件，嘗試從頁面取得基本狀態
        if events.isEmpty {
            if let status = extractBasicStatus(from: html) {
                currentStatus = status.0
                latestMessage = status.1
                events.append(TrackingEventDTO(
                    timestamp: Date(),
                    status: currentStatus,
                    description: latestMessage ?? "狀態更新",
                    location: nil
                ))
            }
        }

        print("解析完成: 狀態=\(currentStatus.displayName), 事件數=\(events.count)")

        return TrackingResult(
            trackingNumber: trackingNumber,
            carrier: carrier,
            currentStatus: currentStatus,
            events: events,
            rawResponse: html
        )
    }

    /// 從 HTML 提取事件區塊
    private func extractEventBlocks(from html: String) -> [String] {
        var blocks: [String] = []

        // 方法 1: 尋找 tracking-item 類別的 div
        let patterns = [
            #"<div[^>]*class="[^"]*tracking[^"]*"[^>]*>[\s\S]*?</div>"#,
            #"<li[^>]*class="[^"]*timeline[^"]*"[^>]*>[\s\S]*?</li>"#,
            #"<tr[^>]*>[\s\S]*?</tr>"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(html.startIndex..., in: html)
                let matches = regex.matches(in: html, options: [], range: range)

                for match in matches {
                    if let matchRange = Range(match.range, in: html) {
                        blocks.append(String(html[matchRange]))
                    }
                }

                if !blocks.isEmpty {
                    break
                }
            }
        }

        return blocks
    }

    /// 解析單一事件區塊
    private func parseEventBlock(_ block: String) -> TrackingEventDTO? {
        // 提取時間
        let date = extractDate(from: block) ?? Date()

        // 提取狀態描述
        guard let description = extractText(from: block) else {
            return nil
        }

        // 判斷狀態
        let status = mapDescriptionToStatus(description)

        // 提取地點（如果有）
        let location = extractLocation(from: block)

        return TrackingEventDTO(
            timestamp: date,
            status: status,
            description: description,
            location: location
        )
    }

    /// 從 HTML 提取基本狀態
    private func extractBasicStatus(from html: String) -> (TrackingStatus, String)? {
        // 尋找常見的狀態關鍵字
        let statusPatterns: [(String, TrackingStatus)] = [
            ("已取件", .delivered),
            ("已領取", .delivered),
            ("已送達", .delivered),
            ("可取貨", .arrivedAtStore),
            ("已到店", .arrivedAtStore),
            ("待取件", .arrivedAtStore),
            ("配送中", .inTransit),
            ("運送中", .inTransit),
            ("已出貨", .shipped),
            ("已寄出", .shipped),
            ("已收件", .shipped)
        ]

        for (keyword, status) in statusPatterns {
            if html.contains(keyword) {
                return (status, keyword)
            }
        }

        return nil
    }

    /// 從文字提取日期
    private func extractDate(from text: String) -> Date? {
        // 嘗試匹配常見日期格式
        let patterns = [
            #"(\d{4})[/-](\d{1,2})[/-](\d{1,2})\s*(\d{1,2}):(\d{2})"#,  // 2024-01-15 14:30
            #"(\d{1,2})[/-](\d{1,2})\s*(\d{1,2}):(\d{2})"#               // 01-15 14:30
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {

                var components = DateComponents()
                let calendar = Calendar.current

                if match.numberOfRanges == 6 {
                    // 完整日期格式
                    components.year = Int(text[Range(match.range(at: 1), in: text)!])
                    components.month = Int(text[Range(match.range(at: 2), in: text)!])
                    components.day = Int(text[Range(match.range(at: 3), in: text)!])
                    components.hour = Int(text[Range(match.range(at: 4), in: text)!])
                    components.minute = Int(text[Range(match.range(at: 5), in: text)!])
                } else if match.numberOfRanges == 5 {
                    // 短日期格式（假設是今年）
                    components.year = calendar.component(.year, from: Date())
                    components.month = Int(text[Range(match.range(at: 1), in: text)!])
                    components.day = Int(text[Range(match.range(at: 2), in: text)!])
                    components.hour = Int(text[Range(match.range(at: 3), in: text)!])
                    components.minute = Int(text[Range(match.range(at: 4), in: text)!])
                }

                return calendar.date(from: components)
            }
        }

        return nil
    }

    /// 從 HTML 提取純文字
    private func extractText(from html: String) -> String? {
        // 移除 HTML 標籤
        var text = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        // 清理空白
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? nil : text
    }

    /// 從文字提取地點
    private func extractLocation(from text: String) -> String? {
        // 尋找店名模式
        let patterns = [
            #"(\S+店)"#,           // XX店
            #"(\S+門市)"#,         // XX門市
            #"(\S+營業所)"#        // XX營業所
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        }

        return nil
    }

    /// 將描述文字映射到狀態
    private func mapDescriptionToStatus(_ description: String) -> TrackingStatus {
        let desc = description.lowercased()

        if desc.contains("已取件") || desc.contains("已領取") || desc.contains("完成取貨") {
            return .delivered
        } else if desc.contains("到店") || desc.contains("可取貨") || desc.contains("待取") {
            return .arrivedAtStore
        } else if desc.contains("配送中") || desc.contains("外出配送") || 
                  desc.contains("運送中") || desc.contains("轉運") || desc.contains("抵達") {
            return .inTransit
        } else if desc.contains("已寄出") || desc.contains("已收件") || desc.contains("已攬收") {
            return .shipped
        }

        return .pending
    }
}
