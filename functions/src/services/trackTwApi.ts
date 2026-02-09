/**
 * trackTwApi.ts
 *
 * Track.TW API HTTP 客戶端。
 * 鏡像 iOS 端 TrackTwAPIClient.swift 的行為。
 *
 * @see PackageTraker/Services/TrackTw/TrackTwAPIClient.swift
 * @see File/TrackTW-API-Spec.md
 */

import axios, {AxiosInstance} from "axios";

const BASE_URL = "https://track.tw/api/v1";

/** Track.TW 追蹤歷史記錄 */
export interface TrackTwHistoryEntry {
  package_id: string;
  time: number; // Unix timestamp（秒）
  status: string; // 中文描述，如 "[中和福美 - 智取店] 買家取件成功"
  checkpoint_status: string; // "transit" | "delivered" | "pending" | "exception"
  created_at: string;
}

/** Track.TW 追蹤回應 */
export interface TrackTwTrackingResponse {
  id: string;
  tracking_number: string;
  carrier_id: string;
  package_history: TrackTwHistoryEntry[];
  carrier: {
    id: string;
    name: string;
  };
}

export class TrackTwAPI {
  private client: AxiosInstance;

  constructor(token: string) {
    this.client = axios.create({
      baseURL: BASE_URL,
      headers: {
        "Authorization": `Bearer ${token}`,
        "Accept": "application/json",
        "Content-Type": "application/json",
      },
      timeout: 10000,
    });
  }

  /**
   * 查詢包裹追蹤詳情
   * GET /package/tracking/{relationId}
   */
  async getTracking(relationId: string): Promise<TrackTwTrackingResponse> {
    const response = await this.client.get<TrackTwTrackingResponse>(
      `/package/tracking/${relationId}`
    );
    return response.data;
  }
}
