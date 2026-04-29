/**
 * statsAggregator.ts
 *
 * 三個排程 function：
 * 1. updateAppStats — 每 6 小時聚合全局統計（使用者數、包裹數、送達數）
 * 2. updatePercentiles — 每月初 00:00 計算百分位門檻
 * 3. updateDailyStats — 每天 00:05 寫一筆昨日快照到 /dailyStats/{YYYY-MM-DD}，
 *    供 AdminAnalyticsView 畫趨勢折線圖
 *
 * 使用 collectionGroup count + 帶 where 的 count 查詢，每次只算單一數字，
 * 不掃整個集合。
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
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
    schedule: "0 0 1 * *",
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

/**
 * 把 Date 轉成 Asia/Taipei 時區的 YYYY-MM-DD 字串
 */
function taipeiDateString(date: Date): string {
  // en-CA locale 的 short date 格式就是 YYYY-MM-DD
  return date.toLocaleDateString("en-CA", {timeZone: "Asia/Taipei"});
}

/**
 * 取得指定 Asia/Taipei 日期的 00:00 (作為 UTC Date 物件)
 */
function taipeiStartOfDay(yyyymmdd: string): Date {
  // Asia/Taipei = UTC+8，沒有 DST，可以直接 hardcode
  return new Date(`${yyyymmdd}T00:00:00+08:00`);
}

/**
 * 計算 [start, end) 區間的 daily snapshot 並寫到 /dailyStats/{dateStr}
 *
 * 共用給：
 * - updateDailyStats cron（每天 00:05 抓昨日完整資料）
 * - runDailyStatsManually callable（debug 用，可抓今日 partial 資料）
 */
export async function writeDailyStatsSnapshot(
  dateStr: string,
  start: Date,
  end: Date,
): Promise<{
  date: string;
  dau: number;
  newUsers: number;
  newPackages: number;
  proUsers: number;
  totalUsers: number;
}> {
  const db = getFirestore();
  const sTs = Timestamp.fromDate(start);
  const eTs = Timestamp.fromDate(end);

  // 用 helper 把每個 query 包起來，失敗時記下是哪個 query 並回傳 -1，
  // 讓單一 query 失敗（例如缺 collectionGroup index）不要把整個 snapshot 拖垮，
  // 也方便看 log 找出有問題的查詢。
  async function safeCount(name: string, q: () => Promise<{data: () => {count: number}}>): Promise<number> {
    try {
      const res = await q();
      return res.data().count;
    } catch (e) {
      logger.error(`[DailyStats] count(${name}) failed:`, e);
      return -1;
    }
  }

  const [dau, newUsers, newPackages, proUsers, totalUsers] = await Promise.all([
    safeCount("dau", () => db.collection("users")
      .where("lastActive", ">=", sTs)
      .where("lastActive", "<", eTs)
      .count().get()),
    safeCount("newUsers", () => db.collection("users")
      .where("createdAt", ">=", sTs)
      .where("createdAt", "<", eTs)
      .count().get()),
    safeCount("newPackages", () => db.collectionGroup("packages")
      .where("createdAt", ">=", sTs)
      .where("createdAt", "<", eTs)
      .count().get()),
    safeCount("proUsers", () => db.collection("users")
      .where("subscriptionTier", "==", "pro")
      .count().get()),
    safeCount("totalUsers", () => db.collection("users").count().get()),
  ]);

  const snapshot = {
    date: dateStr,
    dau,
    newUsers,
    newPackages,
    proUsers,
    totalUsers,
    createdAt: FieldValue.serverTimestamp(),
  };

  await db.doc(`dailyStats/${dateStr}`).set(snapshot);
  return snapshot;
}

/** 給外部模組用的時區 helpers */
export {taipeiDateString, taipeiStartOfDay};

/**
 * 每天 00:05 Asia/Taipei：寫一筆「昨日」快照到 /dailyStats/{YYYY-MM-DD}
 *
 * 為什麼是 00:05 跑昨日：
 * - lastActive 只記最新值，所以 DAU 必須在隔天還沒人重新覆寫前計算
 * - 跑 00:05（剛過午夜 5 分鐘），抓昨日 [00:00, 24:00) 的活躍使用者
 *
 * 用 count() 查詢，每個指標只算單一數字，幾乎不消耗 quota。
 */
export const updateDailyStats = onSchedule(
  {
    schedule: "5 0 * * *",
    timeZone: "Asia/Taipei",
    region: "asia-east1",
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async () => {
    const todayStr = taipeiDateString(new Date());
    const todayStart = taipeiStartOfDay(todayStr);
    const yesterdayStart = new Date(todayStart.getTime() - 24 * 60 * 60 * 1000);
    const yesterdayStr = taipeiDateString(yesterdayStart);

    logger.info(`[DailyStats] Snapshot for ${yesterdayStr}...`);

    try {
      const snapshot = await writeDailyStatsSnapshot(
        yesterdayStr,
        yesterdayStart,
        todayStart,
      );
      logger.info(
        `[DailyStats] ${yesterdayStr} done: ` +
        `dau=${snapshot.dau}, newUsers=${snapshot.newUsers}, ` +
        `newPackages=${snapshot.newPackages}, pro=${snapshot.proUsers}, ` +
        `total=${snapshot.totalUsers}`
      );
    } catch (error) {
      logger.error("[DailyStats] Failed:", error);
      throw error;
    }
  }
);
