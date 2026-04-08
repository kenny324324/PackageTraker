/**
 * geminiProxy.ts
 *
 * Cloud Function 代理 Gemini API 呼叫。
 * - 驗證 Firebase Auth
 * - 檢查 Pro 訂閱
 * - 每日用量限制 (20 次/天)
 * - 伺服器端呼叫 Gemini，API Key 不暴露給 client
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import axios from "axios";

const geminiApiKey = defineSecret("GEMINI_API_KEY");
const geminiApiKeyDebug = defineSecret("GEMINI_API_KEY_DEBUG");

const db = getFirestore();

/** 每日 AI 掃描上限 */
const DAILY_LIMIT = 20;

/** Gemini 模型 */
const MODEL_NAME = "gemini-2.5-flash";

/** System prompt（從 AIVisionService.swift 搬移） */
const SYSTEM_PROMPT = `You are a package tracking information extractor for Taiwan logistics.
Analyze the screenshot and extract the following fields. Return ONLY valid JSON, no markdown.

Required JSON format:
{
  "trackingNumber": "the tracking/order number",
  "carrier": "carrier/logistics company name in Chinese or English",
  "pickupLocation": "pickup store name or address",
  "pickupCode": "pickup verification code if visible",
  "packageName": "product/package name if visible",
  "estimatedDelivery": "estimated delivery date if visible",
  "purchasePlatform": "e-commerce platform name (Shopee/蝦皮/淘寶/PChome/Momo/Yahoo etc.)",
  "amount": "order amount as number string (e.g. 199, 1280.50)",
  "confidence": 0.95
}

Rules:
- For fields not found in the image, use null
- confidence is 0.0 to 1.0, how confident you are about trackingNumber
- Common Taiwan carriers: 蝦皮店到店, 7-ELEVEN交貨便, 7-ELEVEN賣貨便, 全家店到店, OK超商, 萊爾富, 黑貓宅急便, 新竹物流, 宅配通, 中華郵政, 順豐速運, PChome, momo
- Tracking number formats vary widely. Do NOT rely on tracking number format alone to determine carrier. Use the app UI, logos, and text in the screenshot as the primary signal
- Known formats: TW/SPX prefix (蝦皮店到店), J prefix (7-ELEVEN交貨便), N prefix (7-ELEVEN賣貨便), SF prefix (順豐), 12+10digits (PChome), 300+9digits (momo). Pure digit numbers (11 digits) can be 全家/萊爾富/嘉里/新竹 — determine from screenshot context
- 蝦皮購物 orders can use different logistics: 蝦皮店到店 (Shopee's own), or 7-ELEVEN交貨便/全家店到店 etc. Identify the actual carrier from the screenshot, and put "蝦皮購物" in purchasePlatform
- If screenshot shows "賣貨便" text, carrier is "7-ELEVEN賣貨便"
- If screenshot shows "交貨便" text, carrier is "7-ELEVEN交貨便"
- For purchasePlatform, identify the e-commerce platform from logos, text, or app UI
- For amount, extract the total price/amount, return digits only (no currency symbol)
- For packageName: if the product name exceeds 10 characters, summarize it to a concise name (max 10 characters in the language of the original name). Examples: "Apple AirPods Pro 第二代 USB-C MagSafe" → "AirPods Pro", "韓國進口香蕉牛奶 200ml x 6入" → "香蕉牛奶6入", "日本MUJI無印良品收納盒" → "無印收納盒"
- Return ONLY the JSON object, nothing else`;

/**
 * 取得台灣時區的日期字串 (YYYY-MM-DD)
 */
function getTaiwanDateString(): string {
  return new Date().toLocaleDateString("sv-SE", {timeZone: "Asia/Taipei"});
}

/**
 * 取得台灣時區下一個午夜的 ISO 時間
 */
function getNextMidnightTaiwanISO(): string {
  const now = new Date();
  const taiwanOffset = 8 * 60; // UTC+8 in minutes
  const utcMinutes = now.getUTCHours() * 60 + now.getUTCMinutes();
  const taiwanMinutes = utcMinutes + taiwanOffset;

  const midnight = new Date(now);
  if (taiwanMinutes >= 0) {
    // 已過午夜，設定為明天午夜
    midnight.setUTCHours(24 - 8, 0, 0, 0);
    if (taiwanMinutes < 24 * 60) {
      midnight.setUTCDate(midnight.getUTCDate() + 1);
    }
  }

  // 簡化：直接計算明天的 00:00 台灣時間 = 前一天 16:00 UTC
  const todayTaiwan = getTaiwanDateString();
  const tomorrowDate = new Date(todayTaiwan + "T00:00:00+08:00");
  tomorrowDate.setDate(tomorrowDate.getDate() + 1);
  return tomorrowDate.toISOString();
}

/**
 * 呼叫 Gemini API
 */
async function callGemini(
  imageBase64: string,
  mimeType: string,
  apiKey: string
): Promise<Record<string, unknown>> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL_NAME}:generateContent?key=${apiKey}`;

  const requestBody = {
    system_instruction: {
      parts: [{text: SYSTEM_PROMPT}],
    },
    contents: [
      {
        parts: [
          {text: "Please analyze this package screenshot and extract tracking information."},
          {
            inline_data: {
              mime_type: mimeType,
              data: imageBase64,
            },
          },
        ],
      },
    ],
    generationConfig: {
      temperature: 0.1,
      maxOutputTokens: 2048,
      responseMimeType: "application/json",
      thinkingConfig: {
        thinkingBudget: 0,
      },
    },
  };

  const response = await axios.post(url, requestBody, {
    headers: {"Content-Type": "application/json"},
    timeout: 30000,
  });

  // 解析 Gemini 回應
  const candidates = response.data?.candidates;
  if (!candidates || candidates.length === 0) {
    throw new HttpsError("internal", "No candidates in Gemini response");
  }

  const text = candidates[0]?.content?.parts?.[0]?.text;
  if (!text) {
    throw new HttpsError("internal", "No text in Gemini response");
  }

  // 清理 markdown code block
  const cleaned = text
    .replace(/```json/g, "")
    .replace(/```/g, "")
    .trim();

  try {
    return JSON.parse(cleaned);
  } catch {
    logger.error("[GeminiProxy] Failed to parse Gemini response", {text: cleaned});
    throw new HttpsError("internal", "Failed to parse AI response");
  }
}

// ─── Callable Functions ───────────────────────────────────────

/**
 * analyzePackageImage — AI 截圖辨識（含訂閱檢查 + 每日限額）
 */
export const analyzePackageImage = onCall(
  {
    region: "asia-east1",
    memory: "512MiB",
    timeoutSeconds: 60,
    secrets: [geminiApiKey, geminiApiKeyDebug],
  },
  async (request) => {
    // 1. 驗證登入
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Login required");
    }

    // 2. 檢查訂閱層級
    const userDoc = await db.doc(`users/${uid}`).get();
    const userData = userDoc.data();
    const tier = userData?.subscriptionTier;
    if (tier !== "pro") {
      throw new HttpsError("permission-denied", "Pro subscription required");
    }

    // 3. 檢查每日用量（終身方案不限次數）
    const productID = userData?.subscriptionProductID as string | undefined;
    const isLifetime = productID?.includes("lifetime") === true;
    const today = getTaiwanDateString();
    const usageRef = db.doc(`users/${uid}/aiUsage/${today}`);
    const usageDoc = await usageRef.get();
    const currentCount = (usageDoc.data()?.count as number) || 0;

    if (!isLifetime && currentCount >= DAILY_LIMIT) {
      throw new HttpsError(
        "resource-exhausted",
        `Daily AI scan limit reached (${DAILY_LIMIT}/day)`
      );
    }

    // 4. 驗證 request 資料
    const {imageBase64, mimeType} = request.data;
    if (!imageBase64 || typeof imageBase64 !== "string") {
      throw new HttpsError("invalid-argument", "imageBase64 is required");
    }

    const resolvedMimeType = mimeType || "image/jpeg";

    // 5. 呼叫 Gemini API（debug 模式使用獨立 API Key，避免佔用正式配額）
    const isDebug = request.data.debug === true;
    const debugKey = geminiApiKeyDebug.value()?.trim();
    const prodKey = geminiApiKey.value()?.trim();
    const apiKey = (isDebug && debugKey) ? debugKey : prodKey;

    if (!apiKey) {
      logger.error("[GeminiProxy] GEMINI_API_KEY not configured");
      throw new HttpsError("internal", "AI service not configured");
    }

    if (isDebug) {
      logger.info("[GeminiProxy] Using DEBUG API key", {uid});
    }

    let result: Record<string, unknown>;
    try {
      result = await callGemini(imageBase64, resolvedMimeType, apiKey);
    } catch (error) {
      // 檢查是否為 quota 錯誤
      if (axios.isAxiosError(error)) {
        const status = error.response?.status;
        const body = JSON.stringify(error.response?.data || "");

        if (
          status === 429 ||
          body.toLowerCase().includes("quota") ||
          body.toLowerCase().includes("rate limit")
        ) {
          logger.warn("[GeminiProxy] Gemini quota exceeded", {uid, status});
          throw new HttpsError("resource-exhausted", "AI service quota exceeded");
        }

        logger.error("[GeminiProxy] Gemini API error", {uid, status, body: body.substring(0, 500)});
        throw new HttpsError("internal", `AI service error (${status})`);
      }

      // 重新拋出 HttpsError
      if (error instanceof HttpsError) throw error;

      logger.error("[GeminiProxy] Unexpected error", {uid, error: String(error)});
      throw new HttpsError("internal", "AI service error");
    }

    // 6. 遞增用量計數器
    await usageRef.set(
      {
        count: FieldValue.increment(1),
        lastUsedAt: FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    logger.info(`[GeminiProxy] uid=${uid} scan #${currentCount + 1}`, {
      carrier: result.carrier || "unknown",
      hasTrackingNumber: !!result.trackingNumber,
    });

    return result;
  }
);

/**
 * getAIUsage — 查詢今日 AI 用量
 */
export const getAIUsage = onCall(
  {
    region: "asia-east1",
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Login required");
    }

    const today = getTaiwanDateString();
    const usageDoc = await db.doc(`users/${uid}/aiUsage/${today}`).get();
    const used = (usageDoc.data()?.count as number) || 0;

    return {
      used,
      limit: DAILY_LIMIT,
      resetsAt: getNextMidnightTaiwanISO(),
    };
  }
);
