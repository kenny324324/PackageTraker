/**
 * scheduler.ts
 *
 * 每 15 分鐘定時輪詢所有用戶的活躍包裹，
 * 透過 Track.TW API 檢查狀態變化並更新 Firestore。
 *
 * 當 Firestore 中的 status 欄位被更新時，
 * triggers.ts 的 onPackageStatusChange 會自動偵測並發送推播。
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineSecret} from "firebase-functions/params";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {TrackTwAPI} from "./services/trackTwApi";
import {fromTrackTw, isCompletedStatus} from "./utils/statusMapper";

const trackwToken = defineSecret("TRACKW_TOKEN");

/** 每個 API 請求之間的間隔（ms），避免 rate limit */
const API_DELAY_MS = 100;

/** 延遲工具函數 */
const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export const packageTrackingScheduler = onSchedule(
  {
    schedule: "*/15 * * * *",
    timeZone: "Asia/Taipei",
    region: "asia-east1",
    timeoutSeconds: 540,
    memory: "512MiB",
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

    // 1. 取得所有用戶
    const usersSnapshot = await db.collection("users").get();
    logger.info(`[Scheduler] Found ${usersSnapshot.size} users`);

    let totalProcessed = 0;
    let totalUpdated = 0;
    let totalSkipped = 0;
    let totalErrors = 0;

    // 2. 逐用戶處理
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;

      // 取得該用戶未封存的包裹
      const packagesSnapshot = await db
        .collection(`users/${userId}/packages`)
        .where("isArchived", "==", false)
        .get();

      // 程式碼過濾：排除已刪除、已完成、無 relationId 的包裹
      const activePackages = packagesSnapshot.docs.filter((doc) => {
        const data = doc.data();
        if (data.isDeleted === true) return false;
        if (isCompletedStatus(data.status)) return false;
        if (!data.trackTwRelationId) return false;
        return true;
      });

      if (activePackages.length === 0) continue;

      logger.info(
        `[Scheduler] User ${userId}: ${activePackages.length} active packages`
      );

      // 3. 逐包裹追蹤
      for (const packageDoc of activePackages) {
        const pkg = packageDoc.data();
        const relationId = pkg.trackTwRelationId as string;

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

          // 4. 狀態有變化時更新 Firestore
          if (newStatus !== oldStatus) {
            logger.info(
              `[Scheduler] ${pkg.trackingNumber}: ${oldStatus} -> ${newStatus}`
            );

            const updateData: Record<string, unknown> = {
              status: newStatus,
              lastUpdated: FieldValue.serverTimestamp(),
            };

            // 從最新 checkpoint 提取門市名稱
            const storeName = extractStoreName(latestCheckpoint.status);
            if (storeName) {
              updateData.storeName = storeName;
            }

            await packageDoc.ref.update(updateData);
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
