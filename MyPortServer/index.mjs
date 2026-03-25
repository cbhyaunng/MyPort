import { createServer } from "node:http";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import { analyzeUploadSession, getAnalysisRuntimeInfo } from "./analysis.mjs";
import { createStorage } from "./storage.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const isRailwayEnvironment = Boolean(process.env.RAILWAY_ENVIRONMENT_NAME);
const host = process.env.MYPORT_HOST ?? "0.0.0.0";
const port = Number.parseInt(process.env.MYPORT_PORT ?? process.env.PORT ?? "8787", 10);
const railwayVolumeMountPath = process.env.RAILWAY_VOLUME_MOUNT_PATH ?? "";
const defaultDataDirectory = railwayVolumeMountPath.length > 0
  ? path.join(railwayVolumeMountPath, "myport")
  : path.join(__dirname, "data");
const dataDirectory = process.env.MYPORT_DATA_DIR ?? defaultDataDirectory;
const uploadsDirectory = path.join(dataDirectory, "uploads");
const snapshotsFile = path.join(dataDirectory, "snapshots.json");
const uploadSessionsFile = path.join(dataDirectory, "upload-sessions.json");
const analysisJobsFile = path.join(dataDirectory, "analysis-jobs.json");
const databaseURL = process.env.MYPORT_DATABASE_URL ?? process.env.DATABASE_URL ?? "";
const expectedBearerToken = process.env.MYPORT_BEARER_TOKEN ?? "";
const railwayPublicDomain = process.env.RAILWAY_PUBLIC_DOMAIN ?? "";
const publicBaseURL = process.env.MYPORT_PUBLIC_BASE_URL
  ?? (railwayPublicDomain.length > 0 ? `https://${railwayPublicDomain}` : `http://127.0.0.1:${port}`);
const shouldSeedSampleData = String(
  process.env.MYPORT_SEED_SAMPLE_DATA ?? (isRailwayEnvironment ? "false" : "true")
).toLowerCase() === "true";

const storage = await createStorage({
  dataDirectory,
  uploadsDirectory,
  snapshotsFile,
  uploadSessionsFile,
  analysisJobsFile,
  databaseURL,
  seedSnapshots: shouldSeedSampleData ? makeSeedSnapshots() : []
});
const analysisRuntimeInfo = getAnalysisRuntimeInfo();

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? "/", publicBaseURL);
    const method = request.method ?? "GET";

    if (method === "OPTIONS") {
      return sendNoContent(response, 204);
    }

    if (url.pathname === "/healthz" && method === "GET") {
      return sendJSON(response, 200, {
        status: "ok",
        mode: storage.mode,
        serverTime: new Date().toISOString(),
        baseURL: publicBaseURL,
        dataDirectory,
        uploadsDirectory,
        analysisProvider: analysisRuntimeInfo.provider,
        analysisModel: analysisRuntimeInfo.model,
        openAIConfigured: analysisRuntimeInfo.openAIConfigured,
        databaseConfigured: databaseURL.length > 0
      });
    }

    if (url.pathname.startsWith("/v1/")) {
      if (isAuthorized(request) === false) {
        return sendJSON(response, 401, {
          error: "unauthorized",
          message: "Bearer 토큰이 올바르지 않습니다."
        });
      }
    }

    if (url.pathname === "/v1/snapshots" && method === "GET") {
      const items = await storage.listSnapshots();
      return sendJSON(response, 200, { items });
    }

    if (url.pathname === "/v1/snapshots" && method === "POST") {
      const snapshot = await parseJSONBody(request);
      const stored = normalizeSnapshot(snapshot);
      stored.lastSyncedAt = new Date().toISOString();
      await storage.saveSnapshot(stored);
      return sendJSON(response, 201, stored);
    }

    const snapshotMatch = url.pathname.match(/^\/v1\/snapshots\/([^/]+)$/);
    if (snapshotMatch && method === "GET") {
      const snapshotId = normalizeIdentifier(snapshotMatch[1]);
      const snapshot = await storage.getSnapshot(snapshotId);

      if (snapshot == null) {
        return sendJSON(response, 404, {
          error: "snapshot_not_found",
          message: "스냅샷을 찾을 수 없습니다."
        });
      }

      return sendJSON(response, 200, snapshot);
    }

    if (snapshotMatch && method === "PUT") {
      const snapshotId = normalizeIdentifier(snapshotMatch[1]);
      const existing = await storage.getSnapshot(snapshotId);

      if (existing == null) {
        return sendJSON(response, 404, {
          error: "snapshot_not_found",
          message: "수정할 스냅샷을 찾을 수 없습니다."
        });
      }

      const snapshot = await parseJSONBody(request);
      const stored = normalizeSnapshot({
        ...existing,
        ...snapshot,
        id: snapshotId,
        createdAt: existing.createdAt
      });
      stored.lastSyncedAt = new Date().toISOString();

      await storage.saveSnapshot(stored);
      return sendJSON(response, 200, stored);
    }

    if (snapshotMatch && method === "DELETE") {
      const snapshotId = normalizeIdentifier(snapshotMatch[1]);
      await storage.deleteSnapshot(snapshotId);
      return sendNoContent(response, 204);
    }

    if (url.pathname === "/v1/uploads" && method === "POST") {
      const body = await parseJSONBody(request);
      const fileCount = Number.parseInt(String(body.fileCount ?? 0), 10);
      const capturedAt = coerceISOString(body.capturedAt) ?? new Date().toISOString();

      if (Number.isFinite(fileCount) === false || fileCount <= 0) {
        return sendJSON(response, 400, {
          error: "invalid_file_count",
          message: "fileCount는 1 이상이어야 합니다."
        });
      }

      const uploadSessionId = randomUUID();
      const files = Array.from({ length: fileCount }, () => {
        const uploadId = randomUUID();
        return {
          uploadId,
          uploadURL: `${publicBaseURL}/upload-targets/${uploadSessionId}/${uploadId}`
        };
      });

      const session = {
        id: uploadSessionId,
        uploadSessionId,
        capturedAt,
        createdAt: new Date().toISOString(),
        files: files.map((file) => ({
          uploadId: file.uploadId,
          uploadURL: file.uploadURL,
          filePath: path.join(uploadsDirectory, uploadSessionId, `${file.uploadId}.bin`),
          uploadedAt: null,
          mimeType: null,
          size: 0
        }))
      };
      await storage.saveUploadSession(session);

      return sendJSON(response, 201, {
        uploadSessionId,
        files
      });
    }

    const uploadTargetMatch = url.pathname.match(/^\/upload-targets\/([^/]+)\/([^/]+)$/);
    if (uploadTargetMatch && method === "PUT") {
      const uploadSessionId = normalizeIdentifier(uploadTargetMatch[1]);
      const uploadId = normalizeIdentifier(uploadTargetMatch[2]);
      const session = await storage.getUploadSession(uploadSessionId);

      if (session == null) {
        return sendJSON(response, 404, {
          error: "upload_session_not_found",
          message: "업로드 세션을 찾을 수 없습니다."
        });
      }

      const file = session.files.find((item) => item.uploadId === uploadId);
      if (file == null) {
        return sendJSON(response, 404, {
          error: "upload_target_not_found",
          message: "업로드 타겟을 찾을 수 없습니다."
        });
      }

      const buffer = await readRawBody(request);
      await mkdir(path.dirname(file.filePath), { recursive: true });
      await writeFile(file.filePath, buffer);

      file.size = buffer.length;
      file.uploadedAt = new Date().toISOString();
      file.mimeType = normalizeUploadMimeType(request.headers["content-type"]);
      await storage.saveUploadSession(session);

      return sendNoContent(response, 200);
    }

    if (url.pathname === "/v1/analysis-jobs" && method === "POST") {
      const body = await parseJSONBody(request);
      const uploadSessionId = normalizeIdentifier(body.uploadSessionId);
      const session = await storage.getUploadSession(uploadSessionId);

      if (session == null) {
        return sendJSON(response, 404, {
          error: "upload_session_not_found",
          message: "분석할 업로드 세션을 찾을 수 없습니다."
        });
      }

      const job = {
        id: randomUUID(),
        jobId: randomUUID(),
        uploadSessionId,
        status: "processing",
        snapshotId: null,
        createdAt: new Date().toISOString(),
        completedAt: null
      };

      job.id = job.jobId;
      await storage.saveAnalysisJob(job);

      return sendJSON(response, 201, {
        jobId: job.jobId,
        status: job.status,
        snapshotId: job.snapshotId
      });
    }

    const analysisJobMatch = url.pathname.match(/^\/v1\/analysis-jobs\/([^/]+)$/);
    if (analysisJobMatch && method === "GET") {
      const jobId = normalizeIdentifier(analysisJobMatch[1]);
      const job = await storage.getAnalysisJob(jobId);

      if (job == null) {
        return sendJSON(response, 404, {
          error: "analysis_job_not_found",
          message: "분석 작업을 찾을 수 없습니다."
        });
      }

      await advanceAnalysisJob(job);
      return sendJSON(response, 200, {
        jobId: job.jobId,
        status: job.status,
        snapshotId: job.snapshotId
      });
    }

    return sendJSON(response, 404, {
      error: "not_found",
      message: "요청한 경로를 찾을 수 없습니다."
    });
  } catch (error) {
    console.error(error);
    return sendJSON(response, 500, {
      error: "internal_server_error",
      message: error instanceof Error ? error.message : "알 수 없는 서버 오류"
    });
  }
});

server.listen(port, host, () => {
  console.log(`MyPort server listening on ${publicBaseURL}`);
  console.log(`Storage mode: ${storage.mode}`);
  console.log(`Data directory: ${dataDirectory}`);
  console.log(`Analysis provider: ${analysisRuntimeInfo.provider}${analysisRuntimeInfo.model ? ` (${analysisRuntimeInfo.model})` : ""}`);
});

registerShutdownHandlers();

function isAuthorized(request) {
  if (expectedBearerToken.length === 0) {
    return true;
  }

  const header = request.headers.authorization ?? "";
  return header === `Bearer ${expectedBearerToken}`;
}

async function parseJSONBody(request) {
  const rawBody = await readRawBody(request);

  if (rawBody.length === 0) {
    return {};
  }

  return JSON.parse(rawBody.toString("utf8"));
}

async function readRawBody(request) {
  const chunks = [];

  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }

  return Buffer.concat(chunks);
}

function sendJSON(response, statusCode, body) {
  response.writeHead(statusCode, {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    "Content-Type": "application/json; charset=utf-8"
  });
  response.end(`${JSON.stringify(body, null, 2)}\n`);
}

function sendNoContent(response, statusCode) {
  response.writeHead(statusCode, {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Authorization, Content-Type"
  });
  response.end();
}

function normalizeSnapshot(snapshot) {
  const now = new Date().toISOString();
  return {
    id: normalizeIdentifier(snapshot.id ?? randomUUID()),
    title: String(snapshot.title ?? "새 스냅샷"),
    capturedAt: coerceISOString(snapshot.capturedAt) ?? now,
    note: String(snapshot.note ?? ""),
    createdAt: coerceISOString(snapshot.createdAt) ?? now,
    baseCurrency: String(snapshot.baseCurrency ?? "KRW").toUpperCase(),
    holdings: Array.isArray(snapshot.holdings)
      ? snapshot.holdings.map((holding) => normalizeHolding(holding))
      : [],
    exchangeRates: Array.isArray(snapshot.exchangeRates)
      ? snapshot.exchangeRates.map((rate) => normalizeExchangeRate(rate))
      : [],
    lastSyncedAt: coerceISOString(snapshot.lastSyncedAt) ?? now
  };
}

function normalizeHolding(holding) {
  return {
    id: normalizeIdentifier(holding.id ?? randomUUID()),
    name: String(holding.name ?? "이름 없음"),
    symbol: String(holding.symbol ?? ""),
    institution: String(holding.institution ?? ""),
    assetClass: String(holding.assetClass ?? "unknown"),
    quantity: toNullableNumber(holding.quantity),
    unitPrice: toNullableNumber(holding.unitPrice),
    marketValue: toNullableNumber(holding.marketValue),
    currency: String(holding.currency ?? "KRW").toUpperCase(),
    country: String(holding.country ?? ""),
    memo: String(holding.memo ?? "")
  };
}

function normalizeExchangeRate(rate) {
  return {
    id: normalizeIdentifier(rate.id ?? randomUUID()),
    baseCurrency: String(rate.baseCurrency ?? "KRW").toUpperCase(),
    quoteCurrency: String(rate.quoteCurrency ?? "KRW").toUpperCase(),
    rateToQuote: Number(rate.rateToQuote ?? 1),
    source: String(rate.source ?? "server"),
    observedAt: coerceISOString(rate.observedAt) ?? new Date().toISOString()
  };
}

function toNullableNumber(value) {
  if (value == null || value === "") {
    return null;
  }

  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : null;
}

function coerceISOString(value) {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

async function advanceAnalysisJob(job) {
  if (job.status === "completed" || job.status === "failed") {
    return;
  }

  const session = await storage.getUploadSession(job.uploadSessionId);
  if (session == null) {
    job.status = "failed";
    await storage.saveAnalysisJob(job);
    return;
  }

  const uploadedCount = session.files.filter((file) => file.uploadedAt != null).length;
  if (uploadedCount < session.files.length) {
    job.status = "processing";
    await storage.saveAnalysisJob(job);
    return;
  }

  const elapsedMilliseconds =
    Date.now() - new Date(job.createdAt).getTime();

  if (elapsedMilliseconds < 800) {
    job.status = "processing";
    await storage.saveAnalysisJob(job);
    return;
  }

  if (job.snapshotId == null) {
    try {
      const { snapshot } = await analyzeUploadSession(session);
      const normalizedSnapshot = normalizeSnapshot(snapshot);
      await storage.saveSnapshot(normalizedSnapshot);
      job.snapshotId = normalizedSnapshot.id;
    } catch (error) {
      job.status = "failed";
      job.completedAt = new Date().toISOString();
      await storage.saveAnalysisJob(job);
      throw error;
    }
  }

  job.status = "completed";
  job.completedAt = new Date().toISOString();
  await storage.saveAnalysisJob(job);
}

function makeSampleHoldings() {
  return [
    {
      id: randomUUID(),
      name: "삼성전자",
      symbol: "005930",
      institution: "키움증권",
      assetClass: "domesticStock",
      quantity: 42,
      unitPrice: null,
      marketValue: 3721200,
      currency: "KRW",
      country: "KR",
      memo: ""
    },
    {
      id: randomUUID(),
      name: "Apple",
      symbol: "AAPL",
      institution: "키움증권",
      assetClass: "foreignStock",
      quantity: 18,
      unitPrice: null,
      marketValue: 4860,
      currency: "USD",
      country: "US",
      memo: ""
    },
    {
      id: randomUUID(),
      name: "SCHD",
      symbol: "SCHD",
      institution: "키움증권",
      assetClass: "foreignStock",
      quantity: 25,
      unitPrice: null,
      marketValue: 2175,
      currency: "USD",
      country: "US",
      memo: ""
    },
    {
      id: randomUUID(),
      name: "원화 예수금",
      symbol: "",
      institution: "신한은행",
      assetClass: "cashEquivalent",
      quantity: null,
      unitPrice: null,
      marketValue: 5400000,
      currency: "KRW",
      country: "KR",
      memo: ""
    },
    {
      id: randomUUID(),
      name: "USDT 잔고",
      symbol: "USDT",
      institution: "OKX",
      assetClass: "cashEquivalent",
      quantity: 1250,
      unitPrice: null,
      marketValue: 1250,
      currency: "USDT",
      country: "SC",
      memo: ""
    },
    {
      id: randomUUID(),
      name: "Ethereum",
      symbol: "ETH",
      institution: "OKX",
      assetClass: "crypto",
      quantity: 2.8,
      unitPrice: null,
      marketValue: 8920,
      currency: "USDT",
      country: "SC",
      memo: ""
    },
    {
      id: randomUUID(),
      name: "국채 10년",
      symbol: "",
      institution: "메리츠증권",
      assetClass: "bond",
      quantity: 1,
      unitPrice: null,
      marketValue: 1200000,
      currency: "KRW",
      country: "KR",
      memo: ""
    }
  ];
}

function makeSampleExchangeRates(capturedAt, currencies) {
  const rates = [
    {
      id: randomUUID(),
      baseCurrency: "KRW",
      quoteCurrency: "KRW",
      rateToQuote: 1,
      source: "system",
      observedAt: capturedAt
    }
  ];

  if (currencies.has("USD")) {
    rates.push({
      id: randomUUID(),
      baseCurrency: "USD",
      quoteCurrency: "KRW",
      rateToQuote: 1472.3,
      source: "server-sample",
      observedAt: capturedAt
    });
  }

  if (currencies.has("USDT")) {
    rates.push({
      id: randomUUID(),
      baseCurrency: "USDT",
      quoteCurrency: "KRW",
      rateToQuote: 1471.8,
      source: "server-sample",
      observedAt: capturedAt
    });
  }

  return rates;
}

function makeSeedSnapshots() {
  const capturedAt = new Date().toISOString();

  return [
    normalizeSnapshot({
      id: randomUUID(),
      title: "2026년 3월 포트폴리오",
      capturedAt,
      note: "로컬 서버 초기 데이터",
      createdAt: capturedAt,
      baseCurrency: "KRW",
      holdings: makeSampleHoldings(),
      exchangeRates: makeSampleExchangeRates(
        capturedAt,
        new Set(["KRW", "USD", "USDT"])
      ),
      lastSyncedAt: capturedAt
    })
  ];
}

function normalizeUploadMimeType(value) {
  const normalized = String(value ?? "").trim().toLowerCase();
  return normalized.startsWith("image/") ? normalized : null;
}

function normalizeIdentifier(value) {
  return String(value ?? "").trim().toLowerCase();
}

function registerShutdownHandlers() {
  let shuttingDown = false;

  const shutdown = async (signal) => {
    if (shuttingDown) {
      return;
    }

    shuttingDown = true;
    console.log(`Received ${signal}, shutting down MyPort server...`);

    server.close(() => {
      void storage.close().finally(() => {
        process.exit(0);
      });
    });
  };

  process.on("SIGINT", () => {
    void shutdown("SIGINT");
  });

  process.on("SIGTERM", () => {
    void shutdown("SIGTERM");
  });
}
