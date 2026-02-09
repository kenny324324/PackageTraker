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
