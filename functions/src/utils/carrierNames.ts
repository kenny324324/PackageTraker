/**
 * carrierNames.ts
 *
 * Carrier 中文顯示名稱映射（用於推播通知）
 * 與 iOS Carrier.swift 的 displayName 保持一致
 */

import {Lang} from "../i18n/notifications";

interface CarrierNames {
  "zh-Hant": string;
  "zh-Hans": string;
  en: string;
}

/**
 * Carrier 顯示名稱映射表
 */
const carrierDisplayNames: Record<string, CarrierNames> = {
  // 超商取貨
  sevenEleven: {
    "zh-Hant": "7-11 交貨便",
    "zh-Hans": "7-11 交货便",
    en: "7-11",
  },
  familyMart: {
    "zh-Hant": "全家店到店",
    "zh-Hans": "全家店到店",
    en: "FamilyMart",
  },
  hiLife: {
    "zh-Hant": "萊爾富",
    "zh-Hans": "莱尔富",
    en: "Hi-Life",
  },
  okMart: {
    "zh-Hant": "OK 超商",
    "zh-Hans": "OK 超商",
    en: "OK Mart",
  },
  shopee: {
    "zh-Hant": "蝦皮店到店",
    "zh-Hans": "虾皮店到店",
    en: "Shopee Store Pickup",
  },

  // 國內宅配
  tcat: {
    "zh-Hant": "黑貓宅急便",
    "zh-Hans": "黑猫宅急便",
    en: "T-Cat",
  },
  hct: {
    "zh-Hant": "新竹物流",
    "zh-Hans": "新竹物流",
    en: "HCT Logistics",
  },
  ecan: {
    "zh-Hant": "宅配通",
    "zh-Hans": "宅配通",
    en: "E-Can",
  },
  postTW: {
    "zh-Hant": "中華郵政",
    "zh-Hans": "中华邮政",
    en: "Taiwan Post",
  },

  // 電商物流
  pchome: {
    "zh-Hant": "PChome 網家速配",
    "zh-Hans": "PChome 网家速配",
    en: "PChome",
  },
  momo: {
    "zh-Hant": "momo 富昇物流",
    "zh-Hans": "momo 富升物流",
    en: "momo",
  },
  kerry: {
    "zh-Hant": "嘉里大榮物流",
    "zh-Hans": "嘉里大荣物流",
    en: "Kerry TJ Logistics",
  },
  taiwanExpress: {
    "zh-Hant": "台灣快遞",
    "zh-Hans": "台湾快递",
    en: "Taiwan Express",
  },

  // 國際快遞
  dhl: {
    "zh-Hant": "DHL Express",
    "zh-Hans": "DHL Express",
    en: "DHL Express",
  },
  fedex: {
    "zh-Hant": "FedEx",
    "zh-Hans": "FedEx",
    en: "FedEx",
  },
  ups: {
    "zh-Hant": "UPS",
    "zh-Hans": "UPS",
    en: "UPS",
  },
  sfExpress: {
    "zh-Hant": "順豐速運",
    "zh-Hans": "顺丰速运",
    en: "SF Express",
  },
  yanwen: {
    "zh-Hant": "Yanwen",
    "zh-Hans": "Yanwen",
    en: "Yanwen",
  },
  cainiao: {
    "zh-Hant": "菜鳥物流",
    "zh-Hans": "菜鸟物流",
    en: "Cainiao",
  },

  // 其他
  customs: {
    "zh-Hant": "關務署（海關）",
    "zh-Hans": "关务署（海关）",
    en: "Taiwan Customs",
  },
  other: {
    "zh-Hant": "其他物流",
    "zh-Hans": "其他物流",
    en: "Other",
  },
};

/**
 * 取得 carrier 的多語系顯示名稱
 * @param carrier - carrier rawValue (如 "shopee")
 * @param lang - 用戶語系
 * @returns 中文顯示名稱，如果找不到則返回原始 carrier 值
 */
export function getCarrierDisplayName(
  carrier: string,
  lang: Lang
): string {
  const names = carrierDisplayNames[carrier];
  if (!names) return carrier;
  return names[lang];
}
