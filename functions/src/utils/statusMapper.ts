/**
 * statusMapper.ts
 *
 * 將 Track.TW 的 checkpoint_status + 狀態描述映射到 App 的 TrackingStatus。
 * 必須與 iOS 端 TrackingStatus.fromTrackTw() 完全一致。
 *
 * @see PackageTraker/Models/TrackingStatus.swift
 */

export type TrackingStatus =
  | "pending"
  | "shipped"
  | "inTransit"
  | "arrivedAtStore"
  | "delivered"
  | "returned";

/**
 * 從 Track.TW 的 checkpoint_status 和中文狀態描述對應到 TrackingStatus。
 */
export function fromTrackTw(
  checkpointStatus: string,
  statusDescription: string
): TrackingStatus {
  switch (checkpointStatus) {
    case "delivered":
      return "delivered";

    case "exception":
      return "returned";

    case "pending":
      return "pending";

    case "transit":
      return mapTransitSubStatus(statusDescription);

    default:
      return "pending";
  }
}

/**
 * 根據中文描述細分 transit 狀態。
 * 順序很重要，必須與 iOS 端 mapTransitSubStatus() 完全一致。
 */
function mapTransitSubStatus(description: string): TrackingStatus {
  // 1. 尚未出貨（優先排除）
  if (
    description.includes("將於") ||
    description.includes("等待出貨") ||
    description.includes("等待寄件") ||
    description.includes("準備出貨") ||
    description.includes("訂單成立") ||
    description.includes("訂單處理")
  ) {
    return "pending";
  }

  // 2. 已到門市/到店（待取件）
  if (
    description.includes("到店") ||
    description.includes("到門市") ||
    description.includes("待取") ||
    description.includes("可取貨") ||
    description.includes("配達") ||
    description.includes("已到達") ||
    description.includes("已送達")
  ) {
    return "arrivedAtStore";
  }

  // 3. 物流運送中
  if (
    description.includes("配送中") ||
    description.includes("運送中") ||
    description.includes("轉運") ||
    description.includes("理貨") ||
    description.includes("抵達") ||
    description.includes("派送") ||
    description.includes("投遞")
  ) {
    return "inTransit";
  }

  // 4. 已出貨/已寄件（注意：前面已排除「將於...出貨」）
  if (
    description.includes("寄件") ||
    description.includes("出貨") ||
    description.includes("已收件") ||
    description.includes("已攬收")
  ) {
    return "shipped";
  }

  // 5. 無法判斷，預設配送中
  return "inTransit";
}

/** 是否為已完成狀態（不需要再追蹤） */
export function isCompletedStatus(status: string): boolean {
  return status === "delivered" || status === "returned";
}
