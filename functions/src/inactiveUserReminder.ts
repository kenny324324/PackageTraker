/**
 * inactiveUserReminder.ts
 *
 * 久未登入用戶召回推播：每天台北時間 14:00 執行，
 * 對超過 14 天未上線的用戶發送一則 FCM 推播提醒。
 * 每位用戶最多每 30 天推送一次，避免騷擾。
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {sendPushToAllDevices, extractAllTokens} from "./services/pushNotification";
import {logNotification} from "./services/notificationLogger";
import {normalizeLang, Lang} from "./i18n/notifications";

/** 幾天未登入算「久未上線」 */
const INACTIVE_DAYS = 14;

/** 同一用戶至少間隔幾天才再次推送 */
const COOLDOWN_DAYS = 30;

// ============================================================
// 多語系模板
// ============================================================

const inactiveTemplates: Record<Lang, {title: string; body: string}> = {
  "zh-Hant": {
    title: "好久不見 👋",
    body: "你的包裹可能有新動態，回來看看吧",
  },
  "zh-Hans": {
    title: "好久不见 👋",
    body: "你的包裹可能有新动态，回来看看吧",
  },
  en: {
    title: "We miss you 👋",
    body: "Your packages may have updates. Come back and check!",
  },
};

// ============================================================
// Scheduled Function
// ============================================================

export const inactiveUserReminder = onSchedule(
  {
    schedule: "0 14 * * *", // 台北時間 14:00
    timeZone: "Asia/Taipei",
    region: "asia-east1",
    timeoutSeconds: 300,
    memory: "256MiB",
  },
  async () => {
    logger.info("[InactiveReminder] Starting inactive user reminder...");

    const db = getFirestore();
    const now = Date.now();
    const inactiveThreshold = Timestamp.fromMillis(
      now - INACTIVE_DAYS * 24 * 60 * 60 * 1000
    );
    const cooldownThreshold = Timestamp.fromMillis(
      now - COOLDOWN_DAYS * 24 * 60 * 60 * 1000
    );

    // 查詢超過 INACTIVE_DAYS 天未活躍的用戶
    const usersSnapshot = await db
      .collection("users")
      .where("lastActive", "<", inactiveThreshold)
      .get();

    logger.info(
      `[InactiveReminder] Found ${usersSnapshot.size} inactive users (>${INACTIVE_DAYS} days)`
    );

    let totalSent = 0;
    let totalSkipped = 0;

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();

      // 檢查 FCM Token
      const {tokens} = extractAllTokens(userData);
      if (tokens.length === 0) {
        totalSkipped++;
        continue;
      }

      // 冷卻期：避免重複推送
      const lastInactiveReminder = userData.lastInactiveReminderAt as Timestamp | undefined;
      if (lastInactiveReminder && lastInactiveReminder > cooldownThreshold) {
        totalSkipped++;
        continue;
      }

      // 取得用戶語系
      const lang = normalizeLang(userData.language);
      const template = inactiveTemplates[lang];

      const failedDeviceIds = await sendPushToAllDevices(userData, {
        title: template.title,
        body: template.body,
        data: {
          type: "inactiveReminder",
        },
        collapseId: `inactive-reminder-${userId}`,
        threadId: "inactive-reminder",
      });

      // 記錄最後推送時間（冷卻期用）
      await db.collection("users").doc(userId).update({
        lastInactiveReminderAt: FieldValue.serverTimestamp(),
      });

      // 寫入通知日誌
      await logNotification({
        userId,
        type: "inactiveReminder",
        title: template.title,
        body: template.body,
        targetDeviceCount: tokens.length,
        failedDeviceIds,
        success: tokens.length > 0 && failedDeviceIds.length < tokens.length,
      });

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
          logger.info(
            `[InactiveReminder] Cleaned ${failedDeviceIds.length} invalid tokens`
          );
        }
      }

      totalSent++;
      logger.info(`[InactiveReminder] Sent to user ${userId} (${lang})`);
    }

    logger.info(
      `[InactiveReminder] Completed: ${totalSent} sent, ${totalSkipped} skipped`
    );
  }
);
