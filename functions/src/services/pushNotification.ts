/**
 * pushNotification.ts
 *
 * FCM 推播通知服務。
 * 使用 firebase-admin 發送推播到 iOS 設備。
 */

import {getMessaging} from "firebase-admin/messaging";
import {logger} from "firebase-functions/v2";

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

/** 推播類型，對應裝置通知設定的開關 */
export type NotificationType = "arrival" | "shipped" | "pickupReminder";

/** 裝置通知設定 */
interface DeviceNotificationSettings {
  enabled?: boolean;
  arrivalNotification?: boolean;
  shippedNotification?: boolean;
  pickupReminder?: boolean;
}

/** Firestore 中 fcmTokens map 的型別（含裝置通知設定） */
export type FcmTokensMap = Record<string, {
  token: string;
  lastActive?: unknown;
  notificationSettings?: DeviceNotificationSettings;
}>;

/**
 * 發送 FCM 推播通知到指定設備。
 * @returns true 如果發送成功，false 如果 token 無效（應清除）
 */
export async function sendPushNotification(
  fcmToken: string,
  payload: PushPayload
): Promise<boolean> {
  const message = {
    token: fcmToken,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: payload.data || {},
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          sound: "default",
          badge: 1,
          "content-available": 1,
        },
      },
    },
  };

  try {
    const response = await getMessaging().send(message);
    logger.info(`Push sent: ${response}`);
    return true;
  } catch (error: unknown) {
    const errorCode = (error as {code?: string}).code;

    // Token 無效或已過期，呼叫方應清除此 token
    if (
      errorCode === "messaging/invalid-registration-token" ||
      errorCode === "messaging/registration-token-not-registered"
    ) {
      logger.warn(`Invalid FCM token, should be cleared: ${errorCode}`);
      return false;
    }

    logger.error("Failed to send push notification:", error);
    return false;
  }
}

/**
 * 從 userData 中提取所有 FCM tokens（支援新 map 格式 + 舊單一 token 格式）。
 * 若指定 notificationType，會根據各裝置的通知設定過濾。
 */
export function extractAllTokens(
  userData: Record<string, unknown>,
  notificationType?: NotificationType
): {tokens: string[]; deviceIds: string[]} {
  const fcmTokens = userData.fcmTokens as FcmTokensMap | undefined;
  const legacyToken = userData.fcmToken as string | undefined;

  if (fcmTokens && Object.keys(fcmTokens).length > 0) {
    const deviceIds: string[] = [];
    const tokens: string[] = [];

    for (const id of Object.keys(fcmTokens)) {
      const device = fcmTokens[id];
      // 如果裝置有通知設定且指定了通知類型，依設定過濾
      if (notificationType && device.notificationSettings) {
        const s = device.notificationSettings;
        if (s.enabled === false) continue;
        if (notificationType === "arrival" && s.arrivalNotification === false) continue;
        if (notificationType === "shipped" && s.shippedNotification === false) continue;
        if (notificationType === "pickupReminder" && s.pickupReminder === false) continue;
      }
      deviceIds.push(id);
      tokens.push(device.token);
    }

    return {tokens, deviceIds};
  }

  // 舊格式 legacy token：無法判斷裝置設定，一律發送
  if (legacyToken) {
    return {tokens: [legacyToken], deviceIds: ["legacy"]};
  }

  return {tokens: [], deviceIds: []};
}

/**
 * 發送推播到用戶的所有裝置（依 notificationType 過濾各裝置設定）。
 * @returns 失效的 deviceId 清單（caller 應清理這些 token）
 */
export async function sendPushToAllDevices(
  userData: Record<string, unknown>,
  payload: PushPayload,
  notificationType?: NotificationType
): Promise<string[]> {
  const {tokens, deviceIds} = extractAllTokens(userData, notificationType);

  if (tokens.length === 0) {
    return [];
  }

  // 只有一個 token 時用原本的單筆發送
  if (tokens.length === 1) {
    const success = await sendPushNotification(tokens[0], payload);
    return success ? [] : [deviceIds[0]];
  }

  // 多 token 用 multicast
  const message = {
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: payload.data || {},
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          sound: "default",
          badge: 1,
          "content-available": 1,
        },
      },
    },
    tokens,
  };

  try {
    const response = await getMessaging().sendEachForMulticast(message);
    logger.info(
      `[Push] Multicast: ${response.successCount} success, ` +
      `${response.failureCount} failures`
    );

    const failedDeviceIds: string[] = [];
    response.responses.forEach((resp, i) => {
      if (!resp.success) {
        const errorCode = (resp.error as {code?: string})?.code;
        if (
          errorCode === "messaging/invalid-registration-token" ||
          errorCode === "messaging/registration-token-not-registered"
        ) {
          failedDeviceIds.push(deviceIds[i]);
        }
      }
    });

    return failedDeviceIds;
  } catch (error) {
    logger.error("[Push] Multicast failed:", error);
    return [];
  }
}
