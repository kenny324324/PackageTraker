/**
 * statsAggregator.ts
 *
 * 兩個排程 function：
 * 1. updateAppStats — 每 6 小時聚合全局統計（使用者數、包裹數、送達數）
 * 2. updatePercentiles — 每天凌晨 00:00 計算百分位門檻
 *
 * 都寫入 /stats/app 供客戶端讀取。
 *
 * 使用 collectionGroup count 取代逐用戶迴圈，大幅降低 Firestore 讀取量。
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {logger} from "firebase-functions/v2";

/**
 * 從 Firebase Auth 計算總使用者數
 */
async function countAuthUsers(): Promise<number> {
  let count = 0;
  let nextPageToken: string | undefined;

  do {
    const result = await getAuth().listUsers(1000, nextPageToken);
    count += result.users.length;
    nextPageToken = result.pageToken;
  } while (nextPageToken);

  return count;
}

/**
 * 從排序後的數列取百分位值（nearest-rank method）
 */
function getPercentile(sorted: number[], p: number): number {
  if (sorted.length === 0) return 0;
  const index = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, Math.min(index, sorted.length - 1))];
}

/**
 * 每 6 小時：聚合全局統計數據
 * 使用 collectionGroup count 取代逐用戶 loop，從 ~2,400 reads 降至 ~3 reads
 */
export const updateAppStats = onSchedule(
  {
    schedule: "0 */6 * * *",
    timeZone: "Asia/Taipei",
    region: "asia-east1",
    timeoutSeconds: 540,
    memory: "256MiB",
  },
  async () => {
    logger.info("[Stats] Starting app stats aggregation...");

    const db = getFirestore();

    try {
      const totalUsers = await countAuthUsers();

      // 用 collectionGroup count 一次算完，不需逐用戶迴圈
      const totalPackagesResult = await db
        .collectionGroup("packages")
        .count()
        .get();
      const totalPackages = totalPackagesResult.data().count;

      const totalDeliveredResult = await db
        .collectionGroup("packages")
        .where("status", "==", "delivered")
        .count()
        .get();
      const totalDelivered = totalDeliveredResult.data().count;

      // merge 寫入，不覆蓋 percentiles
      await db.doc("stats/app").set({
        totalUsers,
        totalPackages,
        totalDelivered,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      logger.info(
        `[Stats] Aggregation complete: ${totalUsers} users, ` +
        `${totalPackages} packages, ${totalDelivered} delivered`
      );
    } catch (error) {
      logger.error("[Stats] Aggregation failed:", error);
      throw error;
    }
  }
);

/**
 * 每天凌晨 00:00：計算百分位門檻
 * 注意：此函數仍需逐用戶查詢（百分位需要每個用戶的包裹數分佈），
 * 但只執行一天一次，影響較小。
 */
export const updatePercentiles = onSchedule(
  {
    schedule: "0 0 * * *",
    timeZone: "Asia/Taipei",
    region: "asia-east1",
    timeoutSeconds: 540,
    memory: "256MiB",
  },
  async () => {
    logger.info("[Stats] Starting percentile calculation...");

    const db = getFirestore();

    try {
      const usersSnapshot = await db.collection("users").get();
      const userPackageCounts: number[] = [];

      for (const userDoc of usersSnapshot.docs) {
        const count = await userDoc.ref.collection("packages").count().get();
        userPackageCounts.push(count.data().count);
      }

      userPackageCounts.sort((a, b) => a - b);

      const percentiles: Record<string, number> = {
        p50: getPercentile(userPackageCounts, 50),
        p70: getPercentile(userPackageCounts, 70),
        p80: getPercentile(userPackageCounts, 80),
        p85: getPercentile(userPackageCounts, 85),
        p90: getPercentile(userPackageCounts, 90),
        p95: getPercentile(userPackageCounts, 95),
        p99: getPercentile(userPackageCounts, 99),
      };

      // merge 寫入，不覆蓋其他欄位
      await db.doc("stats/app").set({
        percentiles,
        percentilesUpdatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      logger.info(
        `[Stats] Percentiles complete: ${JSON.stringify(percentiles)}`
      );
    } catch (error) {
      logger.error("[Stats] Percentile calculation failed:", error);
      throw error;
    }
  }
);
