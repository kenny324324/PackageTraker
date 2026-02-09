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
