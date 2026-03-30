/**
 * adminNotificationLogs.ts
 *
 * 開發者用 Cloud Function：查詢通知發送記錄。
 * 支援依類型、用戶、成功/失敗篩選。
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";

export const getNotificationLogs = onCall(
  {
    region: "asia-east1",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Login required");
    }

    const {type, userId, success, limit: queryLimit} = request.data ?? {};
    const resultLimit = Math.min(queryLimit ?? 100, 500);

    const db = getFirestore();
    let query: FirebaseFirestore.Query = db
      .collection("notificationLogs")
      .orderBy("createdAt", "desc")
      .limit(resultLimit);

    if (type) query = query.where("type", "==", type);
    if (userId) query = query.where("userId", "==", userId);
    if (success !== undefined && success !== null) {
      query = query.where("success", "==", success);
    }

    try {
      const snapshot = await query.get();
      const logs = snapshot.docs.map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          userId: data.userId ?? "",
          type: data.type ?? "",
          title: data.title ?? "",
          body: data.body ?? "",
          targetDeviceCount: data.targetDeviceCount ?? 0,
          failedDeviceIds: data.failedDeviceIds ?? [],
          success: data.success ?? false,
          errorDetails: data.errorDetails ?? null,
          metadata: data.metadata ?? {},
          createdAt: data.createdAt?.toDate?.()?.toISOString() ?? null,
        };
      });

      logger.info(`[NotificationLogs] Returned ${logs.length} logs`);
      return {logs, count: logs.length};
    } catch (error) {
      logger.error("[NotificationLogs] Query failed:", error);
      throw new HttpsError("internal", "Failed to fetch notification logs");
    }
  }
);
