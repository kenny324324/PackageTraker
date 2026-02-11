/**
 * notifications.ts
 *
 * 推播通知多語系模板。
 * 支援 zh-Hant（繁體中文）、zh-Hans（簡體中文）、en（英文）。
 *
 * 設計原則：簡潔俐落，不加語助詞，不催促，不顯示取貨碼。
 */

export type Lang = "zh-Hant" | "zh-Hans" | "en";

interface NotificationTemplate {
  title: string;
  body: (vars: Record<string, string>) => string;
}

// ============================================================
// 狀態變化推播模板
// ============================================================

const statusTemplates: Record<string, Record<Lang, NotificationTemplate>> = {
  shipped: {
    "zh-Hant": {
      title: "包裹已出貨",
      body: ({name}) => `${name} 已寄出`,
    },
    "zh-Hans": {
      title: "包裹已发货",
      body: ({name}) => `${name} 已寄出`,
    },
    en: {
      title: "Package Shipped",
      body: ({name}) => `${name} has been shipped`,
    },
  },
  arrivedAtStore: {
    "zh-Hant": {
      title: "包裹已到達，請盡快取貨",
      body: ({name, location}) =>
        location ? `${name} 已送達 ${location}，請記得取貨` : `${name} 已送達，請盡快取貨`,
    },
    "zh-Hans": {
      title: "包裹已到达，请尽快取货",
      body: ({name, location}) =>
        location ? `${name} 已送达 ${location}，请记得取货` : `${name} 已送达，请尽快取货`,
    },
    en: {
      title: "Package Arrived - Pick Up Now",
      body: ({name, location}) =>
        location ? `${name} is ready at ${location}. Please pick it up soon` : `${name} is ready for pickup`,
    },
  },
};

// ============================================================
// 每日取貨提醒模板
// ============================================================

interface DailyReminderTemplate {
  single: {
    title: string;
    body: (vars: Record<string, string>) => string;
  };
  multiple: {
    title: string;
    body: (count: number) => string;
  };
}

const dailyReminderTemplates: Record<Lang, DailyReminderTemplate> = {
  "zh-Hant": {
    single: {
      title: "別讓包裹等太久",
      body: ({name, location}) => `${name} 在 ${location} 等你取貨`,
    },
    multiple: {
      title: "別讓包裹等太久",
      body: (count) => `你有 ${count} 個包裹待取貨`,
    },
  },
  "zh-Hans": {
    single: {
      title: "别让包裹等太久",
      body: ({name, location}) => `${name} 在 ${location} 等你取货`,
    },
    multiple: {
      title: "别让包裹等太久",
      body: (count) => `你有 ${count} 个包裹待取货`,
    },
  },
  en: {
    single: {
      title: "Don't keep your package waiting",
      body: ({name, location}) => `${name} is waiting at ${location}`,
    },
    multiple: {
      title: "Don't keep your packages waiting",
      body: (count) => `You have ${count} packages to pick up`,
    },
  },
};

// ============================================================
// Public API
// ============================================================

/**
 * 取得狀態變化推播的 title/body。
 * @param status - 包裹狀態（shipped, arrivedAtStore）
 * @param lang - 用戶語系
 * @param vars - 模板變數（name, location）
 */
export function getNotificationText(
  status: string,
  lang: Lang,
  vars: Record<string, string>
): {title: string; body: string} | null {
  const template = statusTemplates[status]?.[lang];
  if (!template) return null;

  return {
    title: template.title,
    body: template.body(vars),
  };
}

/**
 * 取得每日取貨提醒的 title/body。
 * @param lang - 用戶語系
 * @param packages - 待取包裹資訊陣列
 */
export function getDailyReminderText(
  lang: Lang,
  packages: Array<{name: string; location: string}>
): {title: string; body: string} {
  const template = dailyReminderTemplates[lang];
  const count = packages.length;

  if (count === 1) {
    const pkg = packages[0];
    return {
      title: template.single.title,
      body: template.single.body({name: pkg.name, location: pkg.location}),
    };
  }

  return {
    title: template.multiple.title,
    body: template.multiple.body(count),
  };
}

/**
 * 將 Firestore 中的 language 欄位正規化為支援的語系。
 * 預設 fallback 為 zh-Hant。
 */
export function normalizeLang(language?: string): Lang {
  if (!language) return "zh-Hant";
  if (language.startsWith("zh-Hant")) return "zh-Hant";
  if (language.startsWith("zh-Hans")) return "zh-Hans";
  if (language.startsWith("zh")) return "zh-Hant"; // 中文 fallback 台灣
  if (language.startsWith("en")) return "en";
  return "zh-Hant";
}
