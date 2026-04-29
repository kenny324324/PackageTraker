/**
 * adminUserDetail.ts
 *
 * 開發者用 Cloud Function：回傳指定使用者的完整資料與所有包裹。
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";

const db = getFirestore();

const ADMIN_UIDS = new Set([
  "HkpZ0QZS6QcfWxlzZZvhJNMGHg83",
]);

/**
 * 遞迴序列化 Firestore 資料，將 Timestamp 轉為 ISO string。
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function serializeFirestoreData(data: Record<string, any>): Record<string, any> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const result: Record<string, any> = {};
  for (const [key, value] of Object.entries(data)) {
    if (value === null || value === undefined) {
      result[key] = null;
    } else if (typeof value?.toDate === "function") {
      result[key] = value.toDate().toISOString();
    } else if (typeof value === "object" && !Array.isArray(value)) {
      result[key] = serializeFirestoreData(value);
    } else {
      result[key] = value;
    }
  }
  return result;
}

export const getUserDetail = onCall(
  {
    region: "asia-east1",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request) => {
    const authedUid = request.auth?.uid;
    const claimedUid = typeof request.data?.adminUid === "string" ? request.data.adminUid as string : undefined;
    const callerUid = authedUid ?? claimedUid;
    if (!callerUid || !ADMIN_UIDS.has(callerUid)) {
      throw new HttpsError("permission-denied", "Admin only");
    }

    const targetUid = request.data?.uid as string | undefined;
    if (!targetUid) {
      throw new HttpsError("invalid-argument", "uid is required");
    }

    logger.info(`[AdminUserDetail] Fetching user: ${targetUid}`);

    try {
      const userDoc = await db.collection("users").doc(targetUid).get();
      if (!userDoc.exists) {
        throw new HttpsError("not-found", "User not found");
      }

      const userData = userDoc.data()!;

      // 取得所有包裹
      const packagesSnapshot = await userDoc.ref
        .collection("packages")
        .orderBy("lastUpdated", "desc")
        .get();

      // 並行取得每個包裹的 events
      const packages = await Promise.all(
        packagesSnapshot.docs.map(async (doc) => {
          const d = doc.data();

          const eventsSnapshot = await doc.ref
            .collection("events")
            .orderBy("timestamp", "desc")
            .get();

          const events = eventsSnapshot.docs.map((eDoc) => {
            const e = eDoc.data();
            return {
              id: eDoc.id,
              timestamp: e.timestamp?.toDate?.()?.toISOString() ?? null,
              status: e.status ?? "",
              description: e.description ?? "",
              location: e.location ?? null,
            };
          });

          return {
            id: doc.id,
            trackingNumber: d.trackingNumber ?? "",
            carrier: d.carrier ?? "",
            status: d.status ?? "",
            customName: d.customName ?? null,
            pickupCode: d.pickupCode ?? null,
            pickupLocation: d.pickupLocation ?? null,
            storeName: d.storeName ?? null,
            latestDescription: d.latestDescription ?? null,
            isArchived: d.isArchived ?? false,
            isDeleted: d.isDeleted ?? false,
            amount: d.amount ?? null,
            purchasePlatform: d.purchasePlatform ?? null,
            lastUpdated: d.lastUpdated?.toDate?.()?.toISOString() ?? null,
            createdAt: d.createdAt?.toDate?.()?.toISOString() ?? null,
            events,
          };
        })
      );

      // 用戶基本資料
      const user = {
        uid: targetUid,
        email: userData.email ?? null,
        appleId: userData.appleId ?? null,
        subscriptionTier: userData.subscriptionTier ?? null,
        subscriptionProductID: userData.subscriptionProductID ?? null,
        language: userData.language ?? null,
        fcmToken: userData.fcmToken ?? null,
        lastActive: userData.lastActive?.toDate?.()?.toISOString() ?? null,
        createdAt: userData.createdAt?.toDate?.()?.toISOString() ?? null,
        notificationSettings: userData.notificationSettings ?? null,
      };

      // 原始 Firestore 文件（Timestamp → ISO string）
      const rawFields = serializeFirestoreData(userData);
      rawFields["uid"] = targetUid;

      return {user, packages, rawFields};
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      logger.error("[AdminUserDetail] Failed:", error);
      throw new HttpsError("internal", "Failed to fetch user detail");
    }
  }
);
