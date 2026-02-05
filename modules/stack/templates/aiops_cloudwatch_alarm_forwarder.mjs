import crypto from "crypto";
import https from "https";
import { URL } from "url";

function envJson(name, fallback) {
  const raw = process.env[name];
  if (!raw) return fallback;
  try {
    return JSON.parse(raw);
  } catch (error) {
    return fallback;
  }
}

function envBool(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === null || raw === "") return fallback;
  return ["1", "true", "yes", "y", "on"].includes(String(raw).toLowerCase());
}

function envNumber(name, fallback) {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function httpGetText(url, timeoutMs) {
  return new Promise((resolve, reject) => {
    const req = https.get(
      url,
      {
        timeout: timeoutMs
      },
      (res) => {
        let data = "";
        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          data += chunk;
        });
        res.on("end", () => {
          if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
            resolve(data);
          } else {
            reject(new Error(`GET ${url} failed: ${res.statusCode} ${data.slice(0, 200)}`));
          }
        });
      }
    );
    req.on("error", reject);
    req.on("timeout", () => req.destroy(new Error(`GET ${url} timeout`)));
  });
}

function httpPostJson(url, body, headers, timeoutMs) {
  const payload = Buffer.from(JSON.stringify(body), "utf8");
  const u = new URL(url);
  if (u.protocol !== "https:") {
    throw new Error(`only https endpoints are allowed: ${url}`);
  }
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        method: "POST",
        protocol: u.protocol,
        hostname: u.hostname,
        port: u.port ? Number(u.port) : 443,
        path: u.pathname + u.search,
        headers: {
          "content-type": "application/json",
          "content-length": payload.length,
          ...headers
        },
        timeout: timeoutMs
      },
      (res) => {
        let data = "";
        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          data += chunk;
        });
        res.on("end", () => {
          if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
            resolve({ statusCode: res.statusCode, body: data });
          } else {
            reject(new Error(`POST ${url} failed: ${res.statusCode} ${data.slice(0, 200)}`));
          }
        });
      }
    );
    req.on("error", reject);
    req.on("timeout", () => req.destroy(new Error(`POST ${url} timeout`)));
    req.write(payload);
    req.end();
  });
}

function isValidSnsCertUrl(rawUrl) {
  try {
    const normalized = String(rawUrl || "").trim();
    const url = new URL(normalized);
    if (url.protocol !== "https:") return false;
    // Per AWS SNS docs, SigningCertURL is an SNS endpoint under amazonaws.com.
    // Example: https://sns.ap-northeast-1.amazonaws.com/SimpleNotificationService-....pem
    const hostname = String(url.hostname || "").toLowerCase();
    if (!hostname.startsWith("sns.")) return false;
    if (!hostname.endsWith(".amazonaws.com")) return false;
    const pathname = String(url.pathname || "");
    if (!pathname.startsWith("/SimpleNotificationService-")) return false;
    if (!pathname.endsWith(".pem")) return false;
    return true;
  } catch (error) {
    return false;
  }
}

function stringToSignForSns(message) {
  const type = message.Type;
  const parts = [];
  function add(key) {
    const value = message[key];
    if (value === undefined || value === null || value === "") return;
    parts.push(`${key}\n${value}\n`);
  }

  if (type === "Notification") {
    add("Message");
    add("MessageId");
    add("Subject");
    add("Timestamp");
    add("TopicArn");
    add("Type");
    return parts.join("");
  }

  if (type === "SubscriptionConfirmation" || type === "UnsubscribeConfirmation") {
    add("Message");
    add("MessageId");
    add("SubscribeURL");
    add("Timestamp");
    add("Token");
    add("TopicArn");
    add("Type");
    return parts.join("");
  }

  throw new Error(`unsupported SNS Type: ${type}`);
}

async function verifySnsSignature(message, timeoutMs) {
  const signature = message.Signature;
  const signatureVersion = String(message.SignatureVersion || "1");
  const signingCertUrl = message.SigningCertUrl || message.SigningCertURL;
  if (!signature) throw new Error("missing Signature");
  if (!signingCertUrl) throw new Error("missing SigningCertURL");
  if (!isValidSnsCertUrl(signingCertUrl)) throw new Error(`invalid SigningCertURL: ${signingCertUrl}`);

  const certPem = await httpGetText(signingCertUrl, timeoutMs);
  const data = stringToSignForSns(message);
  const algorithm = signatureVersion === "2" ? "RSA-SHA256" : "RSA-SHA1";
  const verifier = crypto.createVerify(algorithm);
  verifier.update(data, "utf8");
  verifier.end();
  const ok = verifier.verify(certPem, signature, "base64");
  if (!ok) throw new Error("SNS signature verification failed");
}

function tryParseJson(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) return null;
  try {
    return JSON.parse(trimmed);
  } catch (error) {
    return null;
  }
}

function buildCloudWatchEventBridgeLike(payload, snsMeta) {
  if (payload && typeof payload === "object" && payload["detail-type"] && payload.detail) {
    const id = payload.id || snsMeta.messageId || crypto.randomUUID();
    return { ...payload, id };
  }

  const region =
    payload?.Region ||
    snsMeta.topicRegion ||
    process.env.AWS_REGION ||
    null;
  const account =
    payload?.AWSAccountId ||
    snsMeta.topicAccountId ||
    null;

  const alarmName = payload?.AlarmName || payload?.alarmName || null;
  const time = payload?.StateChangeTime || snsMeta.timestamp || new Date().toISOString();
  const id = snsMeta.messageId || crypto.randomUUID();

  return {
    version: "0",
    id,
    "detail-type": "CloudWatch Alarm State Change",
    source: "aws.cloudwatch",
    account,
    time,
    region,
    resources: payload?.AlarmArn ? [payload.AlarmArn] : [],
    detail: {
      alarmName,
      state: {
        value: payload?.NewStateValue || null,
        reason: payload?.NewStateReason || null
      },
      raw: payload
    }
  };
}

export async function handler(event) {
  const targetsByRealm = envJson("TARGET_WEBHOOK_URLS_BY_REALM", {});
  const tokensByRealm = envJson("WEBHOOK_TOKENS_BY_REALM", {});
  const maxTargets = envNumber("MAX_TARGETS", 50);
  const requestTimeoutMs = envNumber("REQUEST_TIMEOUT_MS", 8000);
  const verifySignature = envBool("VERIFY_SNS_SIGNATURE", true);

  const realms = Object.keys(targetsByRealm || {}).slice(0, Math.max(0, maxTargets));
  if (realms.length === 0) {
    console.log("no TARGET_WEBHOOK_URLS_BY_REALM configured; skip");
    return { ok: true, forwarded: 0 };
  }

  const records = Array.isArray(event?.Records) ? event.Records : [];
  const results = [];

  for (const record of records) {
    const sns = record?.Sns ?? record?.SNS ?? null;
    if (!sns) continue;

    const message = {
      Type: sns.Type,
      MessageId: sns.MessageId,
      TopicArn: sns.TopicArn,
      Subject: sns.Subject,
      Message: sns.Message,
      Timestamp: sns.Timestamp,
      SignatureVersion: sns.SignatureVersion,
      Signature: sns.Signature,
      SigningCertURL: sns.SigningCertUrl || sns.SigningCertURL,
      SubscribeURL: sns.SubscribeURL,
      Token: sns.Token
    };

    const topicArn = String(message.TopicArn || "");
    const topicParts = topicArn.split(":");
    const topicRegion = topicParts.length >= 4 ? topicParts[3] : null;
    const topicAccountId = topicParts.length >= 5 ? topicParts[4] : null;
    const snsMeta = {
      messageId: message.MessageId || null,
      timestamp: message.Timestamp || null,
      topicRegion,
      topicAccountId
    };

    if (verifySignature) {
      await verifySnsSignature(message, requestTimeoutMs);
    }

    if (message.Type === "SubscriptionConfirmation" && message.SubscribeURL) {
      await httpGetText(message.SubscribeURL, requestTimeoutMs);
      results.push({ kind: "subscription_confirmed", message_id: message.MessageId });
      continue;
    }

    if (message.Type !== "Notification") continue;

    const parsed = tryParseJson(message.Message);
    const eventBody = buildCloudWatchEventBridgeLike(parsed ?? { message: message.Message }, snsMeta);

    const traceId = crypto.randomUUID();
    const forwardErrors = [];
    await Promise.all(
      realms.map(async (realm) => {
        const url = targetsByRealm[realm];
        if (!url) return;
        const token = tokensByRealm?.[realm] ?? tokensByRealm?.default ?? null;
        try {
          await httpPostJson(
            url,
            eventBody,
            {
              "x-aiops-trace-id": traceId,
              "x-aiops-realm": realm,
              "x-aiops-sns-verified": verifySignature ? "true" : "false",
              ...(token ? { "x-aiops-webhook-token": String(token) } : {})
            },
            requestTimeoutMs
          );
        } catch (error) {
          forwardErrors.push({ realm, error: String(error?.message || error) });
        }
      })
    );

    if (forwardErrors.length > 0) {
      console.log(JSON.stringify({ tag: "aiops_cloudwatch_forward_errors", message_id: message.MessageId, forwardErrors }));
      results.push({ kind: "notification_forwarded_with_errors", message_id: message.MessageId, errors: forwardErrors });
    } else {
      results.push({ kind: "notification_forwarded", message_id: message.MessageId, forwarded: realms.length });
    }
  }

  return { ok: true, results };
}
