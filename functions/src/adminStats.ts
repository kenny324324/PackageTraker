/**
 * adminStats.ts
 *
 * 開發者用 Cloud Function：分頁回傳使用者列表 + 全域統計。
 * - summary：總用戶數 / 訂閱統計 / 版本分布（一次掃全部 users，不查 packages 子集合）
 * - users：分頁，每頁預設 50 筆，附帶 packageCount
 * - nextCursor：下一頁起點（最後一筆 uid），無更多時為 null
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {
  writeDailyStatsSnapshot,
  taipeiDateString,
  taipeiStartOfDay,
} from "./statsAggregator";

const db = getFirestore();

// Admin uid allowlist：因為 iOS Firebase Auth getIDToken 在某些環境會 hang，
// 改用 uid allowlist 驗證 admin 身份（client 同步取 currentUser.uid 送上來）
const ADMIN_UIDS = new Set([
  "HkpZ0QZS6QcfWxlzZZvhJNMGHg83",
]);

function assertAdmin(request: {auth?: {uid?: string}; data?: {adminUid?: unknown}}): string {
  const authedUid = request.auth?.uid;
  const claimedUid = typeof request.data?.adminUid === "string" ? request.data.adminUid : undefined;
  const uid = authedUid ?? claimedUid;
  if (!uid || !ADMIN_UIDS.has(uid)) {
    throw new HttpsError("permission-denied", "Admin only");
  }
  return uid;
}

interface AdminUser {
  uid: string;
  email: string | null;
  subscriptionTier: string | null;
  subscriptionProductID: string | null;
  packageCount: number;
  lastActive: string | null;
  createdAt: string | null;
  language: string | null;
  appVersion: string | null;
  iosVersion: string | null;
}

const DEFAULT_PAGE_SIZE = 50;
const MAX_PAGE_SIZE = 200;

export const getAdminStats = onCall(
  {
    region: "asia-east1",
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    assertAdmin(request);

    const rawLimit = Number(request.data?.limit ?? DEFAULT_PAGE_SIZE);
    const limit = Math.max(1, Math.min(MAX_PAGE_SIZE, Math.floor(rawLimit) || DEFAULT_PAGE_SIZE));
    const cursor = typeof request.data?.cursor === "string" && request.data.cursor.length > 0
      ? request.data.cursor as string
      : null;

    logger.info(`[AdminStats] limit=${limit} cursor=${cursor ?? "(none)"}`);

    try {
      // 一次抓全部 user 文件（不查 package 子集合）
      const usersSnapshot = await db.collection("users").get();
      const allDocs = usersSnapshot.docs;

      // 統計 summary（不需要 packageCount）
      let subscribedUsers = 0;
      let monthly = 0;
      let yearly = 0;
      let lifetime = 0;
      const appVersionCounts: Record<string, number> = {};
      const iosVersionCounts: Record<string, number> = {};

      // Referral 統計（順便算，user loop 內零成本）
      let referralsSent = 0; // 邀請發送總數（被輸入過的次數）
      let referralsCompleted = 0; // 完成的邀請數
      let referredUsersCount = 0; // 自己被邀請來的用戶數

      for (const doc of allDocs) {
        const data = doc.data();
        const tier = data.subscriptionTier as string | undefined;
        const productID = data.subscriptionProductID as string | undefined;

        if (tier === "pro") {
          subscribedUsers++;
          if (productID?.includes("monthly")) {
            monthly++;
          } else if (productID?.includes("yearly")) {
            yearly++;
          } else if (productID?.includes("lifetime")) {
            lifetime++;
          }
        }

        const av = (data.appVersion as string | undefined) ?? "未知";
        const iv = (data.iosVersion as string | undefined) ?? "未知";
        appVersionCounts[av] = (appVersionCounts[av] ?? 0) + 1;
        iosVersionCounts[iv] = (iosVersionCounts[iv] ?? 0) + 1;

        // Referral 累加
        const rc = data.referralCount;
        const rsc = data.referralSuccessCount;
        if (typeof rc === "number") referralsSent += rc;
        if (typeof rsc === "number") referralsCompleted += rsc;
        const referredBy = data.referredBy;
        if (typeof referredBy === "string" && referredBy.length > 0) {
          referredUsersCount++;
        }
      }

      // 排序：lastActive desc（無值放最後）
      const sortedDocs = [...allDocs].sort((a, b) => {
        const aT = a.data().lastActive?.toMillis?.() ?? 0;
        const bT = b.data().lastActive?.toMillis?.() ?? 0;
        return bT - aT;
      });

      // 找 cursor 起始位置
      let startIndex = 0;
      if (cursor) {
        const idx = sortedDocs.findIndex((d) => d.id === cursor);
        if (idx >= 0) {
          startIndex = idx + 1;
        }
      }

      const pageDocs = sortedDocs.slice(startIndex, startIndex + limit);

      // 只查當前 page 的 packageCount
      const packageCounts = await Promise.all(
        pageDocs.map((doc) => doc.ref.collection("packages").count().get())
      );

      const users: AdminUser[] = pageDocs.map((doc, idx) => {
        const data = doc.data();
        const lastActive = data.lastActive?.toDate?.()
          ? data.lastActive.toDate().toISOString()
          : null;
        const createdAt = data.createdAt?.toDate?.()
          ? data.createdAt.toDate().toISOString()
          : null;
        return {
          uid: doc.id,
          email: data.email ?? null,
          subscriptionTier: data.subscriptionTier ?? null,
          subscriptionProductID: data.subscriptionProductID ?? null,
          packageCount: packageCounts[idx].data().count,
          lastActive,
          createdAt,
          language: data.language ?? null,
          appVersion: data.appVersion ?? null,
          iosVersion: data.iosVersion ?? null,
        };
      });

      const hasMore = startIndex + limit < sortedDocs.length;
      const nextCursor = hasMore && pageDocs.length > 0
        ? pageDocs[pageDocs.length - 1].id
        : null;

      logger.info(
        `[AdminStats] Done: ${allDocs.length} total, page=${users.length}, nextCursor=${nextCursor ?? "(end)"}`
      );

      return {
        summary: {
          totalUsers: allDocs.length,
          subscribedUsers,
          monthly,
          yearly,
          lifetime,
          appVersionDistribution: appVersionCounts,
          iosVersionDistribution: iosVersionCounts,
          referralsSent,
          referralsCompleted,
          referredUsersCount,
        },
        users,
        nextCursor,
      };
    } catch (error) {
      logger.error("[AdminStats] Failed:", error);
      throw new HttpsError("internal", "Failed to fetch admin stats");
    }
  }
);

/**
 * 讀最近 N 天的 dailyStats 快照（由 updateDailyStats cron 每天 00:05 寫入）
 *
 * 入參: { days?: number }，預設 30 天，最多 90 天
 * 回傳: { items: [{date, dau, newUsers, newPackages, proUsers, totalUsers}, ...] }
 *       items 依日期由舊到新排序，缺漏的日期不補（前端負責處理）
 */
export const getAdminTrends = onCall(
  {
    region: "asia-east1",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request) => {
    assertAdmin(request);

    const rawDays = Number(request.data?.days ?? 30);
    const days = Math.max(1, Math.min(90, Math.floor(rawDays) || 30));

    try {
      // 用 documentId() 排序拿最後 N 個（YYYY-MM-DD lexical sort = 時間順序）
      const snap = await db.collection("dailyStats")
        .orderBy("__name__", "desc")
        .limit(days)
        .get();

      const items = snap.docs
        .map((d) => {
          const data = d.data();
          return {
            date: data.date as string,
            dau: data.dau as number,
            newUsers: data.newUsers as number,
            newPackages: data.newPackages as number,
            proUsers: data.proUsers as number,
            totalUsers: data.totalUsers as number,
          };
        })
        .sort((a, b) => a.date.localeCompare(b.date)); // 由舊到新

      logger.info(`[AdminTrends] Returned ${items.length} days`);
      return {items};
    } catch (error) {
      logger.error("[AdminTrends] Failed:", error);
      throw new HttpsError("internal", "Failed to fetch trends");
    }
  }
);

/**
 * Top N 邀請人 leaderboard（依 referralSuccessCount desc）
 *
 * 入參: { limit?: number } 預設 10，最多 50
 * 回傳: { users: [{uid, email, referralCount, referralSuccessCount}, ...] }
 */
export const getReferralLeaderboard = onCall(
  {
    region: "asia-east1",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request) => {
    assertAdmin(request);

    const rawLimit = Number(request.data?.limit ?? 10);
    const limit = Math.max(1, Math.min(50, Math.floor(rawLimit) || 10));

    try {
      const snap = await db.collection("users")
        .where("referralSuccessCount", ">", 0)
        .orderBy("referralSuccessCount", "desc")
        .limit(limit)
        .get();

      const users = snap.docs.map((doc) => {
        const data = doc.data();
        return {
          uid: doc.id,
          email: (data.email as string | undefined) ?? null,
          referralCode: (data.referralCode as string | undefined) ?? null,
          referralCount: (data.referralCount as number | undefined) ?? 0,
          referralSuccessCount: (data.referralSuccessCount as number | undefined) ?? 0,
        };
      });

      logger.info(`[ReferralLeaderboard] Returned top ${users.length}`);
      return {users};
    } catch (error) {
      logger.error("[ReferralLeaderboard] Failed:", error);
      throw new HttpsError("internal", "Failed to fetch leaderboard");
    }
  }
);

/**
 * 手動觸發 daily snapshot（DEBUG 用，admin only）
 *
 * 預設抓「今日 [00:00, 現在)」partial 資料，讓 admin 不必等到明天 00:05
 * 才看到第一筆數字。隔天 cron 會把這筆覆寫成完整一天。
 *
 * 如果丟 `date: "YYYY-MM-DD"` 參數，會抓那天 [00:00, 24:00) 完整資料。
 * 注意：補抓過去日期的 DAU 會偏低（lastActive 已被後續活動覆寫）。
 */
export const runDailyStatsManually = onCall(
  {
    region: "asia-east1",
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  async (request) => {
    assertAdmin(request);

    const customDate = typeof request.data?.date === "string"
      ? request.data.date as string
      : null;

    let dateStr: string;
    let start: Date;
    let end: Date;

    if (customDate && /^\d{4}-\d{2}-\d{2}$/.test(customDate)) {
      // 補抓指定日期完整一天
      dateStr = customDate;
      start = taipeiStartOfDay(customDate);
      end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
    } else {
      // 預設：今日 partial 資料 [今日 00:00, 現在)
      dateStr = taipeiDateString(new Date());
      start = taipeiStartOfDay(dateStr);
      end = new Date();
    }

    logger.info(`[ManualDailyStats] Snapshot ${dateStr} [${start.toISOString()} ~ ${end.toISOString()})`);

    try {
      const snapshot = await writeDailyStatsSnapshot(dateStr, start, end);
      return {
        ok: true,
        date: snapshot.date,
        dau: snapshot.dau,
        newUsers: snapshot.newUsers,
        newPackages: snapshot.newPackages,
        proUsers: snapshot.proUsers,
        totalUsers: snapshot.totalUsers,
      };
    } catch (error) {
      logger.error("[ManualDailyStats] Failed:", error);
      throw new HttpsError("internal", "Failed to run daily stats");
    }
  }
);
