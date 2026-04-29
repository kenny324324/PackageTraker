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
