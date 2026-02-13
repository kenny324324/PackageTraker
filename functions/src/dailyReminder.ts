/**
 * dailyReminder.ts
 *
 * 每日取貨提醒：每天台北時間 10:00
 * 查詢所有用戶中狀態為 arrivedAtStore 且未取貨的包裹，
 * 彙整後發送一則 FCM 推播提醒。
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {sendPushToAllDevices, extractAllTokens} from "./services/pushNotification";
import {getDailyReminderText, normalizeLang} from "./i18n/notifications";

export const dailyPickupReminder = onSchedule(
  {
    schedule: "0 10 * * *", // 台北時間 10:00
    timeZone: "Asia/Taipei",
    region: "asia-east1",
    timeoutSeconds: 300,
    memory: "256MiB",
  },
  async () => {
    logger.info("[DailyReminder] Starting daily pickup reminder...");

    const db = getFirestore();

    // 取得所有用戶
    const usersSnapshot = await db.collection("users").get();
    logger.info(`[DailyReminder] Found ${usersSnapshot.size} users`);

    let totalSent = 0;
    let totalSkipped = 0;

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();

      // 檢查 FCM Token（支援新 map + 舊單一格式）
      const {tokens} = extractAllTokens(userData);
      if (tokens.length === 0) {
        continue;
      }

      // 檢查通知設定
      const settings = userData.notificationSettings;
      if (!settings?.enabled || !settings?.pickupReminder) {
        totalSkipped++;
        continue;
      }

      // 查詢該用戶的待取包裹
      const packagesSnapshot = await db
        .collection(`users/${userId}/packages`)
        .where("status", "==", "arrivedAtStore")
        .where("isArchived", "==", false)
        .get();

      // 過濾已刪除的包裹
      const pendingPackages = packagesSnapshot.docs.filter((doc) => {
        const data = doc.data();
        return data.isDeleted !== true;
      });

      if (pendingPackages.length === 0) {
        continue;
      }

      // 取得用戶語系
      const lang = normalizeLang(userData.language);

      // 組裝包裹資訊
      const packageInfos = pendingPackages.map((doc) => {
        const data = doc.data();
        return {
          name: data.customName || data.trackingNumber || "",
          location:
            data.pickupLocation ||
            data.userPickupLocation ||
            data.storeName ||
            "",
        };
      });

      // 取得推播文字
      const text = getDailyReminderText(lang, packageInfos);

      const failedDeviceIds = await sendPushToAllDevices(userData, {
        title: text.title,
        body: text.body,
        data: {
          type: "dailyReminder",
          count: String(pendingPackages.length),
        },
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
          logger.info(`[DailyReminder] Cleaned ${failedDeviceIds.length} invalid tokens`);
        }
      }

      totalSent++;
      logger.info(
        `[DailyReminder] Sent to user ${userId}: ` +
        `${pendingPackages.length} packages (${lang})`
      );
    }

    logger.info(
      `[DailyReminder] Completed: ${totalSent} sent, ${totalSkipped} skipped`
    );
  }
);
