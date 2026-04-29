/**
 * dailyReminder.ts
 *
 * 每日取貨提醒：每天台北時間 10:00
 * 用 collectionGroup 直接查 arrivedAtStore 包裹，再反查對應用戶，
 * 避免逐用戶掃描，大幅減少 Firestore reads。
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {sendPushToAllDevices, extractAllTokens} from "./services/pushNotification";
import {logNotification} from "./services/notificationLogger";
import {getDailyReminderText, normalizeLang} from "./i18n/notifications";

/**
 * 包裹停在 arrivedAtStore 超過此天數就停止發每日提醒。
 * 多數超商取件期限為 7 天；若仍停留在到店未取，多半是物流商系統未推送「已取件」事件，
 * 用戶實際上已取貨。繼續每天推播會被視為打擾。
 */
const STALE_PICKUP_THRESHOLD_DAYS = 7;

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

    // 用 collectionGroup 直接撈所有待取件包裹，不需逐用戶掃描
    const packagesSnapshot = await db.collectionGroup("packages")
      .where("status", "==", "arrivedAtStore")
      .where("isArchived", "==", false)
      .get();

    // 過濾已刪除與過期未更新，並按 userId 分組
    const userPackageMap = new Map<string, Array<{name: string; location: string}>>();
    const staleCutoff = Timestamp.fromMillis(
      Date.now() - STALE_PICKUP_THRESHOLD_DAYS * 24 * 60 * 60 * 1000
    );
    let staleSkipped = 0;

    for (const doc of packagesSnapshot.docs) {
      const data = doc.data();
      if (data.isDeleted === true) continue;

      // 跳過 arrivedAtStore 已超過閾值天數的包裹（極可能用戶已取貨但物流商未推事件）
      const lastUpdated = data.lastUpdated as Timestamp | undefined;
      if (lastUpdated && lastUpdated.toMillis() < staleCutoff.toMillis()) {
        staleSkipped++;
        continue;
      }

      const userId = doc.ref.parent.parent?.id;
      if (!userId) continue;

      if (!userPackageMap.has(userId)) {
        userPackageMap.set(userId, []);
      }
      userPackageMap.get(userId)!.push({
        name: data.customName || data.trackingNumber || "",
        location: data.pickupLocation || data.userPickupLocation || data.storeName || "",
      });
    }

    logger.info(
      `[DailyReminder] Found ${packagesSnapshot.size} pending packages ` +
      `across ${userPackageMap.size} users ` +
      `(skipped ${staleSkipped} stale > ${STALE_PICKUP_THRESHOLD_DAYS} days)`
    );

    let totalSent = 0;

    for (const [userId, packageInfos] of userPackageMap) {
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data();
      if (!userData) continue;

      const {tokens} = extractAllTokens(userData);
      if (tokens.length === 0) continue;

      const lang = normalizeLang(userData.language);
      const text = getDailyReminderText(lang, packageInfos);

      const failedDeviceIds = await sendPushToAllDevices(userData, {
        title: text.title,
        body: text.body,
        data: {
          type: "dailyReminder",
          count: String(packageInfos.length),
        },
        collapseId: `daily-reminder-${userId}`,
        threadId: "daily-reminder",
      }, "pickupReminder");

      await logNotification({
        userId,
        type: "dailyReminder",
        title: text.title,
        body: text.body,
        targetDeviceCount: tokens.length,
        failedDeviceIds,
        success: tokens.length > 0 && failedDeviceIds.length < tokens.length,
        metadata: {
          reminderPackageCount: packageInfos.length,
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
        }
      }

      totalSent++;
      logger.info(`[DailyReminder] Sent to user ${userId}: ${packageInfos.length} packages (${lang})`);
    }

    logger.info(`[DailyReminder] Completed: ${totalSent} sent`);
  }
);
