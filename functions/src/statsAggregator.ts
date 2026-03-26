/**
 * statsAggregator.ts
 *
 * 每小時聚合 App 整體統計數據（使用者數、包裹數、送達數），
 * 寫入 /stats/app 供客戶端讀取顯示。
 *
 * - 使用者數：從 Firebase Authentication 計算（非 Firestore）
 * - 包裹數：所有包裹（含軟刪除）
 * - 送達數：status == "delivered" 的包裹
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {logger} from "firebase-functions/v2";

/**
 * 從 Firebase Auth 計算總使用者數
 * 使用 listUsers 分頁遍歷所有用戶
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

export const updateAppStats = onSchedule(
  {
    schedule: "0 * * * *",
    timeZone: "Asia/Taipei",
    region: "asia-east1",
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async () => {
    logger.info("[Stats] Starting app stats aggregation...");

    const db = getFirestore();

    try {
      // 從 Firebase Authentication 計算使用者總數
      const totalUsers = await countAuthUsers();

      // 逐一統計每個使用者的包裹（含軟刪除）
      const usersSnapshot = await db.collection("users").get();
      let totalPackages = 0;
      let totalDelivered = 0;

      for (const userDoc of usersSnapshot.docs) {
        const packagesRef = userDoc.ref.collection("packages");

        const allCount = await packagesRef.count().get();
        totalPackages += allCount.data().count;

        const deliveredCount = await packagesRef
          .where("status", "==", "delivered")
          .count()
          .get();
        totalDelivered += deliveredCount.data().count;
      }

      // 寫入 /stats/app
      await db.doc("stats/app").set({
        totalUsers,
        totalPackages,
        totalDelivered,
        updatedAt: FieldValue.serverTimestamp(),
      });

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
