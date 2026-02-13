/**
 * triggers.ts
 *
 * Firestore Trigger：監聽包裹狀態變化，
 * 當狀態變為 shipped、inTransit 或 arrivedAtStore 時發送多語系 FCM 推播通知。
 * 
 * 特殊處理：pending -> inTransit 的狀態變化會以「已出貨」通知發送，
 * 解決某些物流直接跳過 shipped 狀態的問題。
 */

import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {
  sendPushToAllDevices,
  extractAllTokens,
  NotificationType,
} from "./services/pushNotification";
import {getNotificationText, normalizeLang} from "./i18n/notifications";
import {getCarrierDisplayName} from "./utils/carrierNames";

/** 需要推播的狀態清單 */
const NOTIFIABLE_STATUSES = ["shipped", "inTransit", "arrivedAtStore"];

export const onPackageStatusChange = onDocumentUpdated(
  {
    document: "users/{userId}/packages/{packageId}",
    region: "asia-east1",
  },
  async (event) => {
    if (!event.data) return;

    const before = event.data.before.data();
    const after = event.data.after.data();
    const {userId, packageId} = event.params;

    // 狀態未變化，跳過
    if (before.status === after.status) {
      return;
    }

    logger.info(
      `[Trigger] Status changed: ${after.trackingNumber} ` +
      `(${before.status} -> ${after.status})`
    );

    // 只在指定狀態推播
    if (!NOTIFIABLE_STATUSES.includes(after.status)) {
      return;
    }

    // 避免重複推播
    if (after.lastNotifiedStatus === after.status) {
      logger.info("[Trigger] Already notified for this status, skipping");
      return;
    }

    // 取得用戶資料
    const db = getFirestore();
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();

    // 先確認有任何裝置 token 存在
    const {tokens} = extractAllTokens(userData || {});
    if (!userData || tokens.length === 0) {
      logger.info("[Trigger] No FCM token, skipping");
      return;
    }

    // 決定通知類型（per-device 過濾會在 sendPushToAllDevices 中處理）
    let notificationType: NotificationType | undefined;
    if (after.status === "arrivedAtStore") {
      notificationType = "arrival";
    } else if (after.status === "shipped" || after.status === "inTransit") {
      notificationType = "shipped";
    }

    // 取得用戶語系
    const lang = normalizeLang(userData.language);

    // 組裝推播內容
    const packageName = after.customName || after.trackingNumber;

    // 優先使用具體門市名稱，否則使用 carrier 的中文顯示名稱
    let location =
      after.pickupLocation ||
      after.userPickupLocation ||
      after.storeName ||
      "";

    // 如果 location 為空或只是英文 carrier rawValue，使用中文顯示名稱
    if (!location || location === after.carrier) {
      location = getCarrierDisplayName(after.carrier, lang);
    }

    // 特殊處理：pending -> inTransit 視為出貨通知
    let notificationStatus = after.status;
    if (after.status === "inTransit" && before.status === "pending") {
      notificationStatus = "shipped";
      logger.info("[Trigger] Treating pending->inTransit as shipped notification");
    }

    const text = getNotificationText(notificationStatus, lang, {
      name: packageName,
      location: location,
    });

    if (!text) {
      logger.warn(`[Trigger] No template for status: ${after.status}`);
      return;
    }

    const failedDeviceIds = await sendPushToAllDevices(userData, {
      title: text.title,
      body: text.body,
      data: {
        packageId: packageId,
        trackingNumber: after.trackingNumber || "",
        status: after.status,
      },
    }, notificationType);

    // 清理失效的 token
    if (failedDeviceIds.length > 0) {
      const updates: Record<string, FieldValue> = {};
      for (const id of failedDeviceIds) {
        if (id !== "legacy") {
          updates[`fcmTokens.${id}`] = FieldValue.delete();
        } else {
          updates["fcmToken"] = FieldValue.delete();
        }
      }
      if (Object.keys(updates).length > 0) {
        await db.collection("users").doc(userId).update(updates);
        logger.info(`[Trigger] Cleaned ${failedDeviceIds.length} invalid tokens`);
      }
    }

    // 更新 lastNotifiedStatus 防止重複推播
    await event.data.after.ref.update({
      lastNotifiedStatus: after.status,
    });
    logger.info(`[Trigger] Push sent to user ${userId} (${after.status}, ${lang})`);
  }
);
