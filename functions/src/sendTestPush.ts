/**
 * sendTestPush.ts
 *
 * Callable function：發送測試推播給呼叫者本人的所有裝置。
 * 用於開發者驗證推播鏈路（不限訂閱層級，但會記到 notification log）。
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {sendPushToAllDevices, extractAllTokens} from "./services/pushNotification";
import {logNotification} from "./services/notificationLogger";

export const sendTestPush = onCall(
  {region: "asia-east1"},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const db = getFirestore();
    const userDoc = await db.collection("users").doc(uid).get();
    const userData = userDoc.data();

    if (!userData) {
      throw new HttpsError("not-found", "User document not found");
    }

    // 不依 notificationType 過濾，強制送到所有裝置（測試用）
    const {tokens, deviceIds} = extractAllTokens(userData);
    if (tokens.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "No FCM token registered for this account"
      );
    }

    const now = new Date();
    const timeStr = now.toLocaleString("zh-TW", {
      timeZone: "Asia/Taipei",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });

    const failedDeviceIds = await sendPushToAllDevices(userData, {
      title: "🧪 測試推播",
      body: `${timeStr} 收到表示鏈路正常`,
      data: {
        type: "test",
        sentAt: now.toISOString(),
      },
      collapseId: `test-${now.getTime()}`,
    });

    await logNotification({
      userId: uid,
      type: "test",
      title: "🧪 測試推播",
      body: `${timeStr} 收到表示鏈路正常`,
      targetDeviceCount: tokens.length,
      failedDeviceIds,
      success: failedDeviceIds.length < tokens.length,
      metadata: {trigger: "manual"},
    });

    logger.info(
      `[TestPush] uid=${uid} devices=${tokens.length} failed=${failedDeviceIds.length}`
    );

    return {
      sentToDevices: tokens.length,
      failedDevices: failedDeviceIds.length,
      deviceIds,
    };
  }
);
