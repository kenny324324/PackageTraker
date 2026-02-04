import Foundation

/// parcel-tw 後端 API 服務
final class ParcelTwService: TrackingServiceProtocol {

    var supportedCarriers: [Carrier] {
        [.sevenEleven, .familyMart, .okMart, .shopee]
    }

    // API URL
    #if DEBUG
    private let baseURL = "https://ptapi-production-5c65.up.railway.app"  // 開發也用正式 API
    #else
    private let baseURL = "https://ptapi-production-5c65.up.railway.app"
    #endif

    func track(number: String, carrier: Carrier) async throws -> TrackingResult {
        guard let platform = carrier.parcelTwPlatform else {
            throw TrackingError.unsupportedCarrier(carrier)
        }

        // 建立 URL
        var components = URLComponents(string: "\(baseURL)/api/track")!
        components.queryItems = [
            URLQueryItem(name: "order_id", value: number),
            URLQueryItem(name: "platform", value: platform)
        ]

        guard let url = components.url else {
            throw TrackingError.invalidTrackingNumber
        }

        // 發送請求
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30  // 7-11 OCR 可能需要較長時間

        print("🔄 開始刷新包裹: \(number)")
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("❌ 網路請求失敗: \(number)")
            print("   錯誤: \(error.localizedDescription)")
            throw TrackingError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TrackingError.invalidResponse
        }
        
        // Debug: 印出 API 回應
        print("========== ParcelTw API Response ==========")
        print("📦 單號: \(number)")
        print("🚚 物流商: \(carrier.displayName)")
        print("🔗 URL: \(url.absoluteString)")
        print("📊 HTTP Status: \(httpResponse.statusCode)")
        if let jsonString = String(data: data, encoding: .utf8) {
            // 格式化 JSON 輸出
            if let jsonData = jsonString.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                print("📄 Response:\n\(prettyString)")
            } else {
                print("📄 Response: \(jsonString)")
            }
        }
        print("============================================")

        // 處理錯誤狀態碼
        if httpResponse.statusCode == 404 {
            throw TrackingError.trackingNumberNotFound
        } else if httpResponse.statusCode == 503 {
            throw TrackingError.parsingError(message: "驗證碼辨識失敗")
        } else if !(200...299).contains(httpResponse.statusCode) {
            throw TrackingError.invalidResponse
        }

        // 解析回應
        return try parseResponse(data, trackingNumber: number, carrier: carrier)
    }

    private func parseResponse(_ data: Data, trackingNumber: String, carrier: Carrier) throws -> TrackingResult {
        // 使用 JSONSerialization 來解析，因為 raw_data 結構較複雜
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? Bool, success,
              let responseData = json["data"] as? [String: Any] else {
            throw TrackingError.parsingError(message: "API 回應格式錯誤")
        }
        
        let statusString = responseData["status"] as? String ?? ""
        let isDelivered = responseData["is_delivered"] as? Bool ?? false
        let platform = responseData["platform"] as? String ?? ""
        
        // 映射狀態
        let status = mapStatus(statusString, isDelivered: isDelivered)
        
        // 額外資訊
        var storeName: String?
        var serviceType: String?
        var pickupDeadline: String?
        
        // 解析完整物流歷程
        var events: [TrackingEventDTO] = []
        
        if let rawData = responseData["raw_data"] as? [String: Any] {
            // 7-11 格式
            if platform == "seven_eleven",
               let result = rawData["result"] as? [String: Any],
               let shipping = result["shipping"] as? [String] {
                events = parseSevenElevenShipping(shipping)
                
                // 取得額外資訊
                if let info = result["info"] as? [String: Any] {
                    storeName = info["store_name"] as? String
                    serviceType = info["servicetype"] as? String
                    pickupDeadline = info["deadline"] as? String
                    
                    // 為到店事件添加門市資訊
                    if let store = storeName, !events.isEmpty {
                        for i in 0..<events.count {
                            if events[i].description.contains("配達") || events[i].description.contains("到店") {
                                events[i] = TrackingEventDTO(
                                    timestamp: events[i].timestamp,
                                    status: events[i].status,
                                    description: events[i].description,
                                    location: store
                                )
                            }
                        }
                    }
                }
            }
            // 全家格式
            else if platform == "family_mart",
                    let list = rawData["List"] as? [[String: Any]] {
                events = parseFamilyMartList(list)
                
                // 取得額外資訊（從第一筆資料）
                if let firstItem = list.first {
                    storeName = firstItem["RCV_STORE_NAME"] as? String
                    pickupDeadline = firstItem["ORDER_DATE_RTN"] as? String
                }
            }
            // 蝦皮格式
            else if platform == "shopee",
                    let trackingList = rawData["tracking_list"] as? [[String: Any]] {
                events = parseShopeeTrackingList(trackingList)
            }
            // OK 超商格式
            else if platform == "okmart" {
                if let trackingList = rawData["tracking_list"] as? [[String: Any]] {
                    events = parseTrackingList(trackingList)
                }
            }
        }
        
        // 如果沒有解析到歷程，使用基本狀態
        if events.isEmpty {
            var eventTime = Date()
            if let timeString = responseData["time"] as? String {
                eventTime = parseDateTime(timeString) ?? Date()
            }
            events = [
                TrackingEventDTO(
                    timestamp: eventTime,
                    status: status,
                    description: statusString,
                    location: nil
                )
            ]
        }
        
        return TrackingResult(
            trackingNumber: trackingNumber,
            carrier: carrier,
            currentStatus: status,
            events: events,
            rawResponse: String(data: data, encoding: .utf8),
            storeName: storeName,
            serviceType: serviceType,
            pickupDeadline: pickupDeadline
        )
    }
    
    // MARK: - 解析 7-11 物流歷程
    
    private func parseSevenElevenShipping(_ shipping: [String]) -> [TrackingEventDTO] {
        var events: [TrackingEventDTO] = []
        
        // 格式: "已完成包裹成功取件2026/01/30 12:06"
        let datePattern = #"(\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2})"#
        let regex = try? NSRegularExpression(pattern: datePattern)
        
        for item in shipping {
            var description = item
            var timestamp = Date()
            
            // 提取日期時間
            if let regex = regex,
               let match = regex.firstMatch(in: item, range: NSRange(item.startIndex..., in: item)),
               let range = Range(match.range(at: 1), in: item) {
                let dateString = String(item[range])
                description = item.replacingOccurrences(of: dateString, with: "").trimmingCharacters(in: .whitespaces)
                
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy/MM/dd HH:mm"
                timestamp = formatter.date(from: dateString) ?? Date()
            }
            
            let status = mapStatus(description, isDelivered: description.contains("取件成功") || description.contains("成功取件"))
            
            events.append(TrackingEventDTO(
                timestamp: timestamp,
                status: status,
                description: description,
                location: nil
            ))
        }
        
        return events
    }
    
    // MARK: - 解析全家物流歷程
    
    private func parseFamilyMartList(_ list: [[String: Any]]) -> [TrackingEventDTO] {
        var events: [TrackingEventDTO] = []
        
        for item in list {
            let statusDesc = item["STATUS_D"] as? String ?? ""
            let dateTimeString = item["ORDER_DATE_R"] as? String ?? ""
            let storeName = item["RCV_STORE_NAME"] as? String
            
            var timestamp = Date()
            if !dateTimeString.isEmpty {
                timestamp = parseDateTime(dateTimeString) ?? Date()
            }
            
            let status = mapStatus(statusDesc, isDelivered: statusDesc.contains("完成取件"))
            
            events.append(TrackingEventDTO(
                timestamp: timestamp,
                status: status,
                description: statusDesc,
                location: statusDesc.contains("配達") || statusDesc.contains("到店") ? storeName : nil
            ))
        }
        
        return events
    }
    
    // MARK: - 解析蝦皮物流歷程
    
    private func parseShopeeTrackingList(_ trackingList: [[String: Any]]) -> [TrackingEventDTO] {
        var events: [TrackingEventDTO] = []
        
        for item in trackingList {
            let message = item["message"] as? String ?? ""
            let statusCode = item["status"] as? String ?? ""
            let timestampValue = item["timestamp"] as? Int
            
            var timestamp = Date()
            if let ts = timestampValue {
                timestamp = Date(timeIntervalSince1970: TimeInterval(ts))
            }
            
            let status = mapShopeeStatus(statusCode: statusCode, message: message)
            
            events.append(TrackingEventDTO(
                timestamp: timestamp,
                status: status,
                description: message,
                location: nil
            ))
        }
        
        return events
    }
    
    // MARK: - 通用解析
    
    private func parseTrackingList(_ trackingList: [[String: Any]]) -> [TrackingEventDTO] {
        var events: [TrackingEventDTO] = []
        
        for item in trackingList {
            let message = item["message"] as? String ?? item["status"] as? String ?? ""
            let timestampValue = item["timestamp"] as? Int ?? item["time"] as? Int
            
            var timestamp = Date()
            if let ts = timestampValue {
                timestamp = Date(timeIntervalSince1970: TimeInterval(ts))
            } else if let timeString = item["time"] as? String {
                timestamp = parseDateTime(timeString) ?? Date()
            }
            
            let status = mapStatus(message, isDelivered: message.contains("取件") && message.contains("成功"))
            
            events.append(TrackingEventDTO(
                timestamp: timestamp,
                status: status,
                description: message,
                location: nil
            ))
        }
        
        return events
    }
    
    // MARK: - 時間解析
    
    private func parseDateTime(_ dateString: String) -> Date? {
        let formatters: [String] = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }
    
    // MARK: - 蝦皮狀態映射
    
    private func mapShopeeStatus(statusCode: String, message: String) -> TrackingStatus {
        switch statusCode {
        case "SP_Ready_Collection":
            return .arrivedAtStore
        case "SP_Collection_Collected":
            return .delivered
        case "SP_In_Transit", "SP_Sorting", "SP_Out_for_Delivery", "SOC_Received":
            return .inTransit
        case "SP_Picked_Up", "SP_Info_Received", "Created":
            return .shipped
        case "SP_Returned", "SP_Return", "Returned", "Return":
            return .returned
        default:
            return mapStatus(message, isDelivered: false)
        }
    }

    private func mapStatus(_ status: String, isDelivered: Bool) -> TrackingStatus {
        if isDelivered {
            return .delivered
        }

        let statusLower = status.lowercased()

        // 已退回（到期未取、退貨、退回）
        if statusLower.contains("退回") || statusLower.contains("退貨") ||
           statusLower.contains("逾期") || statusLower.contains("到期未取") ||
           statusLower.contains("未取退") || statusLower.contains("返回") ||
           statusLower.contains("return") {
            return .returned
        }
        // 已到貨（到店待取件）
        else if statusLower.contains("到店") || statusLower.contains("待取") || 
           statusLower.contains("可取貨") || statusLower.contains("配達") ||
           statusLower.contains("已到貨") {
            return .arrivedAtStore
        }
        // 配送中
        else if statusLower.contains("配送中") || statusLower.contains("運送中") || 
                statusLower.contains("轉運") || statusLower.contains("理貨") ||
                statusLower.contains("物流中心") || statusLower.contains("前往") {
            return .inTransit
        }
        // 已出貨
        else if statusLower.contains("已寄出") || statusLower.contains("已收件") ||
                statusLower.contains("寄件") || statusLower.contains("出貨") ||
                statusLower.contains("訂單成立") || statusLower.contains("賣家") {
            return .shipped
        }

        return .pending
    }
}
