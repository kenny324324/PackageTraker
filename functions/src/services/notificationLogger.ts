/**
 * notificationLogger.ts
 *
 * 通知審計日誌：每次發送 FCM 推播時寫入 Firestore，
 * 記錄收件人、內容、裝置數、成功/失敗狀態等資訊。
 */

import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";

export type NotificationLogType = "statusChange" | "dailyReminder" | "inactiveReminder" | "referralTrialReminder" | "test";

export interface NotificationLogEntry {
  userId: string;
  type: NotificationLogType;
  title: string;
  body: string;
  targetDeviceCount: number;
  failedDeviceIds: string[];
  success: boolean;
  errorDetails?: string;
  metadata?: Record<string, string | number>;
}

/**
 * 寫入通知日誌到 Firestore notificationLogs collection。
 * Fire-and-forget：失敗不影響通知發送流程。
 */
export async function logNotification(entry: NotificationLogEntry): Promise<void> {
  try {
    const db = getFirestore();
    await db.collection("notificationLogs").add({
      ...entry,
      errorDetails: entry.errorDetails ?? null,
      metadata: entry.metadata ?? {},
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    logger.error("[NotificationLogger] Failed to write log:", error);
  }
}
