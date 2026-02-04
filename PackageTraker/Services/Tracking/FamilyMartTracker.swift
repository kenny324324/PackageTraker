import Foundation

/// 全家便利商店追蹤服務
/// 參考：https://github.com/NCNU-OpenSource/parcel-tracker
final class FamilyMartTracker: TrackingServiceProtocol {

    var supportedCarriers: [Carrier] {
        [.familyMart]
    }

    private let apiURL = URL(string: "https://ecfme.fme.com.tw/FMEDCFPWebV2_II/list.aspx/GetOrderDetail")!

    func track(number: String, carrier: Carrier) async throws -> TrackingResult {
        guard carrier == .familyMart else {
            throw TrackingError.unsupportedCarrier(carrier)
        }

        // 建立 request
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "EC_ORDER_NO": number,
            "ORDER_NO": number,
            "RCV_USER_NAME": ""
        ]
        request.httpBody = try JSONEncoder().encode(payload)

        // 發送請求
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TrackingError.invalidResponse
        }

        // 解析回應
        let rawString = String(data: data, encoding: .utf8) ?? ""
        return try parseResponse(rawString, trackingNumber: number)
    }

    // MARK: - Private

    private func parseResponse(_ raw: String, trackingNumber: String) throws -> TrackingResult {
        // FamilyMart API 回傳格式特殊，需要清理
        // 移除反斜線並提取 JSON
        var cleaned = raw.replacingOccurrences(of: "\\", with: "")

        // 回應格式: {"d":"[{...}]"}
        // 需要提取內部的 JSON array
        guard let jsonData = cleaned.data(using: .utf8),
              let wrapper = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let dValue = wrapper["d"] as? String else {
            throw TrackingError.parsingError(message: "無法解析全家回應")
        }

        // 解析內部的 array
        guard let listData = dValue.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: listData) as? [[String: Any]],
              let firstItem = list.first else {
            throw TrackingError.trackingNumberNotFound
        }

        // 提取狀態資訊
        let statusMsg = firstItem["ProcessStatusName"] as? String ?? ""
        let orderDateTime = firstItem["OrderDateTime"] as? String ?? ""
        let storeName = firstItem["StName"] as? String

        // 映射狀態
        let status = mapStatus(statusMsg)

        // 建立事件
        var events: [TrackingEventDTO] = []
        if let date = parseDate(orderDateTime) {
            events.append(TrackingEventDTO(
                timestamp: date,
                status: status,
                description: statusMsg,
                location: storeName
            ))
        }

        return TrackingResult(
            trackingNumber: trackingNumber,
            carrier: .familyMart,
            currentStatus: status,
            events: events,
            rawResponse: raw
        )
    }

    private func mapStatus(_ statusMsg: String) -> TrackingStatus {
        if statusMsg.contains("貨件配達取件店舖") || statusMsg.contains("到店") {
            return .arrivedAtStore
        } else if statusMsg.contains("已完成取件") || statusMsg.contains("取件完成") {
            return .delivered
        } else if statusMsg.contains("配送中") || statusMsg.contains("配達中") ||
                  statusMsg.contains("運送中") || statusMsg.contains("轉運") {
            return .inTransit
        } else if statusMsg.contains("已收件") || statusMsg.contains("寄件") {
            return .shipped
        }
        return .pending
    }

    private func parseDate(_ dateString: String) -> Date? {
        // 格式可能是 "2024/01/15 14:30:00" 或類似格式
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")

        let formats = [
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "yyyy-MM-dd HH:mm"
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        return nil
    }
}
