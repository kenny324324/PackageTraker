/**
 * scheduler.ts
 *
 * 每 30 分鐘定時輪詢所有活躍包裹，
 * 透過 Track.TW API 檢查狀態變化並更新 Firestore。
 *
 * 使用 collectionGroup 直接查詢活躍包裹，避免逐用戶掃描。
 *
 * 當 Firestore 中的 status 欄位被更新時，
 * triggers.ts 的 onPackageStatusChange 會自動偵測並發送推播。
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineSecret} from "firebase-functions/params";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {createHash} from "crypto";
import {TrackTwAPI} from "./services/trackTwApi";
import {fromTrackTw} from "./utils/statusMapper";

const trackwToken = defineSecret("TRACKW_TOKEN");

/** 每個 API 請求之間的間隔（ms），避免 rate limit */
const API_DELAY_MS = 100;

/** 延遲工具函數 */
const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export const packageTrackingScheduler = onSchedule(
  {
    schedule: "0 * * * *",
    timeZone: "Asia/Taipei",
    region: "asia-east1",
    timeoutSeconds: 540,
    memory: "256MiB",
    secrets: [trackwToken],
  },
  async () => {
    logger.info("[Scheduler] Starting package tracking poll...");

    const token = trackwToken.value().trim();
    if (!token) {
      logger.error("[Scheduler] TRACKW_TOKEN not configured");
      return;
    }

    const db = getFirestore();
    const api = new TrackTwAPI(token);

    // 使用 collectionGroup 直接查詢所有活躍包裹，排除已完成狀態
    const packagesSnapshot = await db.collectionGroup("packages")
      .where("isArchived", "==", false)
      .where("status", "not-in", ["delivered", "returned"])
      .get();

    // code-side 過濾：排除已刪除、無 relationId 的包裹
    const activePackages = packagesSnapshot.docs.filter((doc) => {
      const data = doc.data();
      if (data.isDeleted === true) return false;
      if (!data.trackTwRelationId) return false;
      return true;
    });

    logger.info(
      `[Scheduler] Found ${activePackages.length} active packages ` +
      `(from ${packagesSnapshot.size} total non-archived)`
    );

    let totalProcessed = 0;
    let totalUpdated = 0;
    let totalSkipped = 0;
    let totalErrors = 0;

    // 逐包裹追蹤
    for (const packageDoc of activePackages) {
      const pkg = packageDoc.data();
      const relationId = pkg.trackTwRelationId as string;
      // 從 doc path 取得 userId: users/{userId}/packages/{packageId}
      const userId = packageDoc.ref.parent.parent?.id ?? "unknown";

      try {
        const tracking = await api.getTracking(relationId);

        if (
          !tracking.package_history ||
          tracking.package_history.length === 0
        ) {
          totalSkipped++;
          continue;
        }

        // 取得最新狀態
        const latestCheckpoint = tracking.package_history[0];
        const newStatus = fromTrackTw(
          latestCheckpoint.checkpoint_status,
          latestCheckpoint.status
        );
        const oldStatus = pkg.status as string;

        totalProcessed++;

        // 狀態有變化時更新 Firestore（含 events subcollection）
        if (newStatus !== oldStatus) {
          logger.info(
            `[Scheduler] ${pkg.trackingNumber} (user: ${userId}): ` +
            `${oldStatus} -> ${newStatus}`
          );

          const updateData: Record<string, unknown> = {
            status: newStatus,
            latestDescription: latestCheckpoint.status,
            lastUpdated: FieldValue.serverTimestamp(),
          };

          // 從最新 checkpoint 提取門市名稱
          const storeName = extractStoreName(latestCheckpoint.status);
          if (storeName) {
            updateData.storeName = storeName;
          }

          // 用 batch 同時更新 package + events（單次原子寫入）
          const batch = db.batch();
          batch.update(packageDoc.ref, updateData);

          // 寫入 events subcollection（確定性 ID 避免重複）
          for (const entry of tracking.package_history) {
            const eventStatus = fromTrackTw(
              entry.checkpoint_status,
              entry.status
            );
            const timestamp = new Date(entry.time * 1000);
            const eventId = deterministicEventId(
              pkg.trackingNumber as string,
              timestamp,
              entry.status
            );
            const eventRef = packageDoc.ref
              .collection("events")
              .doc(eventId);
            batch.set(eventRef, {
              timestamp: timestamp,
              status: eventStatus,
              description: entry.status,
            });
          }

          await batch.commit();
          totalUpdated++;
        }
      } catch (error: unknown) {
        const axiosError = error as {response?: {status?: number}};
        const statusCode = axiosError.response?.status;

        if (statusCode === 404) {
          logger.warn(
            `[Scheduler] Package not found: ${pkg.trackingNumber}`
          );
        } else if (statusCode === 429) {
          logger.warn("[Scheduler] Rate limited, stopping this cycle");
          return; // 遇到 rate limit 直接結束本次輪詢
        } else if (statusCode === 401) {
          logger.error("[Scheduler] Unauthorized - token may be expired");
          return; // Token 無效，結束輪詢
        } else {
          logger.error(
            `[Scheduler] Failed to track ${pkg.trackingNumber}:`,
            error
          );
        }
        totalErrors++;
      }

      // 避免 API rate limit
      await delay(API_DELAY_MS);
    }

    logger.info(
      `[Scheduler] Completed: ${totalProcessed} processed, ` +
      `${totalUpdated} updated, ${totalSkipped} skipped, ` +
      `${totalErrors} errors`
    );
  }
);

/**
 * 從狀態描述中提取門市名稱。
 * 格式範例: "[中和福美 - 智取店] 買家取件成功" → "中和福美 - 智取店"
 */
function extractStoreName(status: string): string | null {
  const match = status.match(/\[([^\]]+)\]/);
  return match ? match[1] : null;
}

/**
 * 產生確定性 event ID（與 iOS 端 TrackingEvent.deterministicId 一致）。
 * SHA256("{trackingNumber}|{unix_seconds}|{description}") → 前 16 bytes → UUID v5 format
 */
function deterministicEventId(
  trackingNumber: string,
  timestamp: Date,
  description: string
): string {
  const key = `${trackingNumber}|${Math.floor(timestamp.getTime() / 1000)}|${description}`;
  const hash = createHash("sha256").update(key, "utf8").digest();
  const bytes = Array.from(hash.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // UUID version 5
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
  const hex = bytes.map((b) => b.toString(16).padStart(2, "0")).join("");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32),
  ].join("-").toUpperCase();
}
