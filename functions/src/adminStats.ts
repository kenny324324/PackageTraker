/**
 * adminStats.ts
 *
 * 開發者用 Cloud Function：回傳所有使用者的資料庫統計。
 * - 訂閱人數與帳號
 * - 每個使用者的包裹數、最後活躍時間等
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";

const db = getFirestore();

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

export const getAdminStats = onCall(
  {
    region: "asia-east1",
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Login required");
    }

    logger.info("[AdminStats] Fetching admin stats...");

    try {
      const usersSnapshot = await db.collection("users").get();

      // 並行查詢所有用戶的包裹數（每批 20 個避免過載）
      const BATCH_SIZE = 20;
      const docs = usersSnapshot.docs;
      const packageCounts: number[] = new Array(docs.length).fill(0);

      for (let i = 0; i < docs.length; i += BATCH_SIZE) {
        const batch = docs.slice(i, i + BATCH_SIZE);
        const counts = await Promise.all(
          batch.map((doc) => doc.ref.collection("packages").count().get())
        );
        counts.forEach((result, idx) => {
          packageCounts[i + idx] = result.data().count;
        });
      }

      const users: AdminUser[] = [];
      let subscribedUsers = 0;
      let monthly = 0;
      let yearly = 0;
      let lifetime = 0;

      for (let i = 0; i < docs.length; i++) {
        const data = docs[i].data();
        const packageCount = packageCounts[i];

        // 訂閱統計
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

        // Firestore Timestamp → ISO string
        const lastActive = data.lastActive?.toDate?.()
          ? data.lastActive.toDate().toISOString()
          : null;
        const createdAt = data.createdAt?.toDate?.()
          ? data.createdAt.toDate().toISOString()
          : null;

        users.push({
          uid: docs[i].id,
          email: data.email ?? null,
          subscriptionTier: tier ?? null,
          subscriptionProductID: productID ?? null,
          packageCount,
          lastActive,
          createdAt,
          language: data.language ?? null,
          appVersion: data.appVersion ?? null,
          iosVersion: data.iosVersion ?? null,
        });
      }

      // 按包裹數降序排列
      users.sort((a, b) => b.packageCount - a.packageCount);

      logger.info(
        `[AdminStats] Done: ${users.length} users, ${subscribedUsers} subscribed`
      );

      return {
        summary: {
          totalUsers: users.length,
          subscribedUsers,
          monthly,
          yearly,
          lifetime,
        },
        users,
      };
    } catch (error) {
      logger.error("[AdminStats] Failed:", error);
      throw new HttpsError("internal", "Failed to fetch admin stats");
    }
  }
);
