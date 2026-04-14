/**
 * referralTrialReminder.ts
 *
 * 邀請試用到期提醒：每天台北時間 09:00 執行，
 * 對 referralTrialEndDate 在未來 24 小時內到期的用戶發送 FCM 推播提醒。
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {sendPushToAllDevices, extractAllTokens} from "./services/pushNotification";
import {logNotification} from "./services/notificationLogger";
import {normalizeLang, Lang} from "./i18n/notifications";

// ============================================================
// 多語系模板
// ============================================================

const trialReminderTemplates: Record<Lang, {title: string; body: string}> = {
  "zh-Hant": {
    title: "Pro 體驗即將到期",
    body: "你的免費 Pro 體驗明天就結束了，立即升級繼續享受完整功能",
  },
  "zh-Hans": {
    title: "Pro 体验即将到期",
    body: "你的免费 Pro 体验明天就结束了，立即升级继续享受完整功能",
  },
  en: {
    title: "Pro Trial Expiring Soon",
    body: "Your free Pro trial ends tomorrow. Upgrade now to keep all features",
  },
};

// ============================================================
// Scheduled Function
// ============================================================

export const referralTrialReminder = onSchedule(
  {
    schedule: "0 9 * * *", // 台北時間 09:00
    timeZone: "Asia/Taipei",
    region: "asia-east1",
    timeoutSeconds: 300,
    memory: "256MiB",
  },
  async () => {
    logger.info("[ReferralTrialReminder] Starting referral trial reminder...");

    const db = getFirestore();
    const now = Date.now();
    const in24Hours = Timestamp.fromMillis(now + 24 * 60 * 60 * 1000);
    const nowTimestamp = Timestamp.fromMillis(now);

    // 查詢 referralTrialEndDate 在未來 24 小時內到期的用戶
    const usersSnapshot = await db
      .collection("users")
      .where("referralTrialEndDate", ">", nowTimestamp)
      .where("referralTrialEndDate", "<=", in24Hours)
      .get();

    logger.info(
      `[ReferralTrialReminder] Found ${usersSnapshot.size} users with trial expiring within 24h`
    );

    let totalSent = 0;
    let totalSkipped = 0;

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();

      // 跳過已付費的用戶
      if (userData.subscriptionTier === "pro") {
        totalSkipped++;
        continue;
      }

      // 檢查 FCM Token
      const {tokens} = extractAllTokens(userData);
      if (tokens.length === 0) {
        totalSkipped++;
        continue;
      }

      // 取得用戶語系
      const lang = normalizeLang(userData.language);
      const template = trialReminderTemplates[lang];

      const failedDeviceIds = await sendPushToAllDevices(userData, {
        title: template.title,
        body: template.body,
        data: {
          type: "referralTrialReminder",
        },
        collapseId: `referral-trial-reminder-${userId}`,
        threadId: "referral-trial-reminder",
      });

      // 寫入通知日誌
      await logNotification({
        userId,
        type: "referralTrialReminder",
        title: template.title,
        body: template.body,
        targetDeviceCount: tokens.length,
        failedDeviceIds,
        success: tokens.length > 0 && failedDeviceIds.length < tokens.length,
      });

      totalSent++;
      logger.info(`[ReferralTrialReminder] Sent to user ${userId} (${lang})`);
    }

    logger.info(
      `[ReferralTrialReminder] Completed: ${totalSent} sent, ${totalSkipped} skipped`
    );
  }
);
