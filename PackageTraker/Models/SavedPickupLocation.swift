import Foundation
import SwiftData

/// 使用者儲存的常用取貨地點
@Model
final class SavedPickupLocation {
    var id: UUID
    var name: String
    var carrierRawValue: String
    var createdAt: Date

    var carrier: Carrier {
        get { Carrier(rawValue: carrierRawValue) ?? .other }
        set { carrierRawValue = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String, carrier: Carrier, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.carrierRawValue = carrier.rawValue
        self.createdAt = createdAt
    }
}
