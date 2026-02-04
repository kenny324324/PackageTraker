import Foundation
import CryptoKit

/// 蝦皮店到店追蹤服務
/// 參考：https://github.com/NCNU-OpenSource/parcel-tracker
final class ShopeeTracker: TrackingServiceProtocol {

    var supportedCarriers: [Carrier] {
        [.shopee]
    }

    private let baseURL = "https://spx.tw/api/v2/fleet_order/tracking/search"

    // Salt for signature (base64 decoded: "0ebfffe63d2a481cf57fe7d5ebdc9fd6")
    private let salt = "0ebfffe63d2a481cf57fe7d5ebdc9fd6"

    func track(number: String, carrier: Carrier) async throws -> TrackingResult {
        guard carrier == .shopee else {
            throw TrackingError.unsupportedCarrier(carrier)
        }

        // Debug: 印出輸入的單號
        print("=== Shopee Tracking Debug ===")
        print("輸入單號: \(number)")
        print("單號長度: \(number.count)")

        // 計算簽名
        let timestamp = Int(Date().timeIntervalSince1970)
        let signature = calculateSignature(orderID: number, timestamp: timestamp)

        // 組合參數: orderID|timestamp|signature
        let trackingParam = "\(number)|\(timestamp)|\(signature)"

        print("Timestamp: \(timestamp)")
        print("Signature: \(signature)")
        print("完整參數: \(trackingParam)")

        // 建立 URL
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "sls_tracking_number", value: trackingParam)
        ]

        guard let url = components.url else {
            throw TrackingError.invalidTrackingNumber
        }

        print("完整 URL: \(url.absoluteString)")

        // 建立 request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("fms_language=tw", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("https://spx.tw", forHTTPHeaderField: "Referer")

        // 發送請求
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TrackingError.invalidResponse
        }

        // 解析回應
        let rawString = String(data: data, encoding: .utf8) ?? ""
        return try parseResponse(data, trackingNumber: number, raw: rawString)
    }

    // MARK: - Private

    private func calculateSignature(orderID: String, timestamp: Int) -> String {
        let input = "\(orderID)\(timestamp)\(salt)"
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func parseResponse(_ data: Data, trackingNumber: String, raw: String) throws -> TrackingResult {
        // Debug: 印出原始回應
        print("=== Shopee API Response ===")
        print(raw)
        print("===========================")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ 無法解析 JSON")
            throw TrackingError.parsingError(message: "無法解析蝦皮回應")
        }

        print("JSON 結構: \(json.keys)")

        guard let responseData = json["data"] as? [String: Any] else {
            // 可能 data 是空的或者結構不同
            print("❌ 找不到 data 欄位，完整 JSON: \(json)")
            throw TrackingError.parsingError(message: "無法解析蝦皮回應")
        }

        print("Data 結構: \(responseData.keys)")

        // 檢查是否找到包裹
        guard let trackingList = responseData["tracking_list"] as? [[String: Any]],
              !trackingList.isEmpty else {
            print("❌ tracking_list 為空或不存在")
            throw TrackingError.trackingNumberNotFound
        }

        // 取得最新狀態 (第一個)
        let latestTracking = trackingList[0]
        let statusCode = latestTracking["status"] as? String ?? ""
        let message = latestTracking["message"] as? String ?? ""
        let timestampValue = latestTracking["timestamp"] as? Int

        // 映射狀態
        let status = mapStatus(statusCode: statusCode, message: message)

        // 建立事件列表
        var events: [TrackingEventDTO] = []
        for tracking in trackingList {
            if let ts = tracking["timestamp"] as? Int,
               let msg = tracking["message"] as? String {
                let date = Date(timeIntervalSince1970: TimeInterval(ts))
                let code = tracking["status"] as? String ?? ""
                events.append(TrackingEventDTO(
                    timestamp: date,
                    status: mapStatus(statusCode: code, message: msg),
                    description: msg,
                    location: nil
                ))
            }
        }

        return TrackingResult(
            trackingNumber: trackingNumber,
            carrier: .shopee,
            currentStatus: status,
            events: events,
            rawResponse: raw
        )
    }

    private func mapStatus(statusCode: String, message: String) -> TrackingStatus {
        // 蝦皮狀態碼對照
        switch statusCode {
        case "SP_Ready_Collection":
            return .arrivedAtStore
        case "SP_Collection_Collected":
            return .delivered
        case "SP_In_Transit", "SP_Sorting", "SP_Out_for_Delivery":
            return .inTransit
        case "SP_Picked_Up", "SP_Info_Received":
            return .shipped
        default:
            // 從訊息內容判斷
            if message.contains("到店") || message.contains("待取") {
                return .arrivedAtStore
            } else if message.contains("取件") && message.contains("完成") {
                return .delivered
            } else if message.contains("配送中") || message.contains("運送中") || message.contains("轉運") {
                return .inTransit
            }
            return .pending
        }
    }
}
