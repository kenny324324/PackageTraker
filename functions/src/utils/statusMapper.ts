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
 *
 * 以 API 的 4 種 checkpoint_status 為主，僅在 transit / delivered 內用描述細分：
 * - transit   → "shipped"（剛出貨）或 "inTransit"（預設）
 * - delivered → "delivered"（已取件/簽收）或 "arrivedAtStore"（預設，到店待取）
 */
export function fromTrackTw(
  checkpointStatus: string,
  statusDescription: string
): TrackingStatus {
  switch (checkpointStatus) {
    case "delivered":
      return mapDeliveredSubStatus(statusDescription);

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
 * 細分 transit：區分「剛出貨」vs「到店待取」vs「配送中」
 *
 * 判斷順序很重要：shipped → arrivedAtStore → inTransit（預設）
 */
function mapTransitSubStatus(description: string): TrackingStatus {
  // 0. 描述含「尚未」表示物流動作尚未發生（如「尚未至門市寄件」），視為待出貨
  if (description.includes("尚未")) {
    return "pending";
  }

  // 1. 已出貨/已寄件（最先判斷，避免「寄件門市已收件」被後續門市規則誤判）
  if (
    description.includes("寄件") ||
    description.includes("出貨") ||
    description.includes("已收件") ||
    description.includes("已攬收") ||
    description.includes("訂單成立") ||
    description.includes("訂單處理")
  ) {
    return "shipped";
  }

  // 2. 到店待取：描述含「門市」但排除移動中的事件
  //    ✅ "包裹配達取件門市" → arrivedAtStore
  //    ❌ "前往取件門市" → inTransit（含「前往」）
  //    ❌ "離開寄件門市" → inTransit（含「離開」）
  //    ❌ "送達物流中心" → inTransit（不含「門市」）
  if (
    description.includes("到店") ||
    description.includes("可取件") ||
    description.includes("門市到貨")
  ) {
    return "arrivedAtStore";
  }
  if (
    description.includes("門市") &&
    !description.includes("前往") &&
    !description.includes("離開") &&
    !description.includes("物流中心") &&
    !description.includes("轉運")
  ) {
    return "arrivedAtStore";
  }

  // 3. 其餘一律配送中
  return "inTransit";
}

/**
 * 細分 delivered：區分「已取件/簽收」vs「到店待取」
 *
 * 注意：「取件門市」包含「取件」二字，必須先排除，避免誤判為已取貨
 */
function mapDeliveredSubStatus(description: string): TrackingStatus {
  // 明確已取件/簽收 → 已完成
  // 先排除「取件門市」（門市名稱，不是已取件動作）
  const cleaned = description.split("取件門市").join("");
  if (
    cleaned.includes("簽收") ||
    cleaned.includes("取件") ||
    cleaned.includes("領取") ||
    cleaned.includes("取貨完成") ||
    cleaned.includes("已領") ||
    cleaned.includes("已取")
  ) {
    return "delivered";
  }

  // 其餘（到店、送達門市等）→ 到店待取件
  return "arrivedAtStore";
}

/** 是否為已完成狀態（不需要再追蹤） */
export function isCompletedStatus(status: string): boolean {
  return status === "delivered" || status === "returned";
}
