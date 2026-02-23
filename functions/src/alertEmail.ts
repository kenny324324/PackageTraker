/**
 * alertEmail.ts
 *
 * Firestore Trigger：當 systemAlerts 新增 aiQuotaExceeded 時寄送 Email 告警。
 */

import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {defineSecret} from "firebase-functions/params";
import {logger} from "firebase-functions/v2";
import nodemailer from "nodemailer";

const alertSmtpHost = defineSecret("ALERT_SMTP_HOST");
const alertSmtpPort = defineSecret("ALERT_SMTP_PORT");
const alertSmtpUser = defineSecret("ALERT_SMTP_USER");
const alertSmtpPass = defineSecret("ALERT_SMTP_PASS");
const alertEmailTo = defineSecret("ALERT_EMAIL_TO");

export const onSystemAlertCreated = onDocumentCreated(
  {
    document: "users/{userId}/systemAlerts/{alertId}",
    region: "asia-east1",
    timeoutSeconds: 60,
    memory: "256MiB",
    secrets: [
      alertSmtpHost,
      alertSmtpPort,
      alertSmtpUser,
      alertSmtpPass,
      alertEmailTo,
    ],
  },
  async (event) => {
    if (!event.data) return;

    const data = event.data.data() || {};
    const alertType = String(data.type || "");

    if (alertType !== "aiQuotaExceeded") {
      return;
    }

    const smtpHost = alertSmtpHost.value().trim();
    const smtpPortRaw = alertSmtpPort.value().trim();
    const smtpUser = alertSmtpUser.value().trim();
    const smtpPass = alertSmtpPass.value().trim();
    const recipient = alertEmailTo.value().trim();

    if (!smtpHost || !smtpPortRaw || !smtpUser || !smtpPass || !recipient) {
      logger.warn("[AlertEmail] SMTP config incomplete, skipping email send");
      return;
    }

    const smtpPort = Number(smtpPortRaw);
    if (Number.isNaN(smtpPort)) {
      logger.error("[AlertEmail] ALERT_SMTP_PORT is not a valid number");
      return;
    }

    const transporter = nodemailer.createTransport({
      host: smtpHost,
      port: smtpPort,
      secure: smtpPort === 465,
      auth: {
        user: smtpUser,
        pass: smtpPass,
      },
    });

    const statusCode = String(data.statusCode || "unknown");
    const model = String(data.model || "unknown");
    const userId = String(data.userId || event.params.userId || "unknown");
    const locale = String(data.locale || "unknown");
    const source = String(data.source || "unknown");
    const appVersion = String(data.appVersion || "unknown");
    const buildNumber = String(data.buildNumber || "unknown");
    const message = String(data.message || "").slice(0, 800);
    const createdAt = formatCreatedAt(data.createdAt);

    const subject = `[PackageTraker] AI quota exceeded (HTTP ${statusCode})`;
    const text = [
      "AI quota alert detected.",
      "",
      `Time: ${createdAt}`,
      `Status: ${statusCode}`,
      `Model: ${model}`,
      `Source: ${source}`,
      `User ID: ${userId}`,
      `Locale: ${locale}`,
      `App Version: ${appVersion} (${buildNumber})`,
      "",
      "Raw message (truncated):",
      message || "(empty)",
    ].join("\n");

    try {
      await transporter.sendMail({
        from: `PackageTraker Alert <${smtpUser}>`,
        to: recipient,
        subject,
        text,
      });

      await event.data.ref.set(
        {
          emailNotified: true,
          emailNotifiedAt: new Date(),
        },
        {merge: true}
      );

      logger.info(`[AlertEmail] AI quota alert email sent to ${recipient}`);
    } catch (error) {
      logger.error("[AlertEmail] Failed to send AI quota alert email", error);
    }
  }
);

function formatCreatedAt(value: unknown): string {
  if (typeof value === "string") {
    return value;
  }

  if (
    value &&
    typeof value === "object" &&
    "toDate" in value &&
    typeof (value as {toDate?: () => Date}).toDate === "function"
  ) {
    return (value as {toDate: () => Date}).toDate().toISOString();
  }

  return new Date().toISOString();
}
