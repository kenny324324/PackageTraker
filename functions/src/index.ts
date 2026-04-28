/**
 * index.ts
 *
 * Cloud Functions 入口。
 * 初始化 Firebase Admin SDK 並匯出所有 functions。
 */

import {initializeApp} from "firebase-admin/app";

initializeApp();

export {packageTrackingScheduler} from "./scheduler";
export {onPackageStatusChange} from "./triggers";
export {dailyPickupReminder} from "./dailyReminder";
export {onSystemAlertCreated} from "./alertEmail";
export {analyzePackageImage, getAIUsage} from "./geminiProxy";
export {updateAppStats, updatePercentiles} from "./statsAggregator";
export {getAdminStats} from "./adminStats";
export {getNotificationLogs} from "./adminNotificationLogs";
export {getUserDetail} from "./adminUserDetail";
export {inactiveUserReminder} from "./inactiveUserReminder";
export {referralTrialReminder} from "./referralTrialReminder";
export {sendTestPush} from "./sendTestPush";
