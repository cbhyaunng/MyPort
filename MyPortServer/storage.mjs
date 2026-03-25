import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import pg from "pg";

const { Pool } = pg;

export async function createStorage({
  dataDirectory,
  uploadsDirectory,
  snapshotsFile,
  uploadSessionsFile,
  analysisJobsFile,
  databaseURL,
  seedSnapshots = []
}) {
  if (typeof databaseURL === "string" && databaseURL.length > 0) {
    return createPostgresStorage({
      databaseURL,
      uploadsDirectory,
      seedSnapshots
    });
  }

  return createFileStorage({
    dataDirectory,
    uploadsDirectory,
    snapshotsFile,
    uploadSessionsFile,
    analysisJobsFile,
    seedSnapshots
  });
}

async function createFileStorage({
  dataDirectory,
  uploadsDirectory,
  snapshotsFile,
  uploadSessionsFile,
  analysisJobsFile,
  seedSnapshots
}) {
  await mkdir(dataDirectory, { recursive: true });
  await mkdir(uploadsDirectory, { recursive: true });

  let snapshots = await readArrayFile(snapshotsFile, []);
  let uploadSessions = await readArrayFile(uploadSessionsFile, []);
  let analysisJobs = await readArrayFile(analysisJobsFile, []);

  if (snapshots.length === 0 && seedSnapshots.length > 0) {
    snapshots = seedSnapshots;
  }

  await writeJSONFile(snapshotsFile, snapshots);
  await writeJSONFile(uploadSessionsFile, uploadSessions);
  await writeJSONFile(analysisJobsFile, analysisJobs);

  return {
    mode: "file-json",
    metadata: {
      dataDirectory,
      uploadsDirectory
    },
    async listSnapshots() {
      return sortSnapshots(snapshots);
    },
    async getSnapshot(snapshotId) {
      const normalizedSnapshotId = normalizeIdentifier(snapshotId);
      return snapshots.find((item) => normalizeIdentifier(item.id) === normalizedSnapshotId) ?? null;
    },
    async saveSnapshot(snapshot) {
      snapshots = upsertById(snapshots, snapshot);
      await writeJSONFile(snapshotsFile, snapshots);
      return snapshot;
    },
    async deleteSnapshot(snapshotId) {
      const normalizedSnapshotId = normalizeIdentifier(snapshotId);
      snapshots = snapshots.filter((item) => normalizeIdentifier(item.id) !== normalizedSnapshotId);
      await writeJSONFile(snapshotsFile, snapshots);
    },
    async getUploadSession(uploadSessionId) {
      const normalizedUploadSessionId = normalizeIdentifier(uploadSessionId);
      return uploadSessions.find((item) => {
        return normalizeIdentifier(item.uploadSessionId) === normalizedUploadSessionId
          || normalizeIdentifier(item.id) === normalizedUploadSessionId;
      }) ?? null;
    },
    async saveUploadSession(session) {
      uploadSessions = upsertById(uploadSessions, session);
      await writeJSONFile(uploadSessionsFile, uploadSessions);
      return session;
    },
    async getAnalysisJob(jobId) {
      const normalizedJobId = normalizeIdentifier(jobId);
      return analysisJobs.find((item) => {
        return normalizeIdentifier(item.jobId) === normalizedJobId
          || normalizeIdentifier(item.id) === normalizedJobId;
      }) ?? null;
    },
    async saveAnalysisJob(job) {
      analysisJobs = upsertById(analysisJobs, job);
      await writeJSONFile(analysisJobsFile, analysisJobs);
      return job;
    },
    async close() {
      // 파일 저장소는 종료할 연결이 없다.
    }
  };
}

async function createPostgresStorage({
  databaseURL,
  uploadsDirectory,
  seedSnapshots
}) {
  await mkdir(uploadsDirectory, { recursive: true });

  const pool = new Pool({
    connectionString: databaseURL,
    max: 4
  });

  await initializePostgresSchema(pool);

  if (seedSnapshots.length > 0) {
    const result = await pool.query("SELECT 1 FROM snapshots LIMIT 1");
    if (result.rowCount === 0) {
      for (const snapshot of seedSnapshots) {
        await upsertSnapshot(pool, snapshot);
      }
    }
  }

  return {
    mode: "postgres",
    metadata: {
      uploadsDirectory
    },
    async listSnapshots() {
      const result = await pool.query(
        "SELECT payload FROM snapshots ORDER BY captured_at DESC"
      );
      return result.rows.map((row) => parsePayload(row.payload));
    },
    async getSnapshot(snapshotId) {
      const normalizedSnapshotId = normalizeIdentifier(snapshotId);
      const result = await pool.query(
        "SELECT payload FROM snapshots WHERE id = $1 LIMIT 1",
        [normalizedSnapshotId]
      );
      return result.rows.length > 0 ? parsePayload(result.rows[0].payload) : null;
    },
    async saveSnapshot(snapshot) {
      await upsertSnapshot(pool, snapshot);
      return snapshot;
    },
    async deleteSnapshot(snapshotId) {
      await pool.query("DELETE FROM snapshots WHERE id = $1", [normalizeIdentifier(snapshotId)]);
    },
    async getUploadSession(uploadSessionId) {
      const normalizedUploadSessionId = normalizeIdentifier(uploadSessionId);
      const result = await pool.query(
        "SELECT payload FROM upload_sessions WHERE id = $1 LIMIT 1",
        [normalizedUploadSessionId]
      );
      return result.rows.length > 0 ? parsePayload(result.rows[0].payload) : null;
    },
    async saveUploadSession(session) {
      await upsertGenericRecord(pool, {
        tableName: "upload_sessions",
        id: session.id ?? session.uploadSessionId,
        timestampColumn: "created_at",
        timestampValue: session.createdAt,
        payload: session
      });
      return session;
    },
    async getAnalysisJob(jobId) {
      const normalizedJobId = normalizeIdentifier(jobId);
      const result = await pool.query(
        "SELECT payload FROM analysis_jobs WHERE id = $1 LIMIT 1",
        [normalizedJobId]
      );
      return result.rows.length > 0 ? parsePayload(result.rows[0].payload) : null;
    },
    async saveAnalysisJob(job) {
      await upsertGenericRecord(pool, {
        tableName: "analysis_jobs",
        id: job.id ?? job.jobId,
        timestampColumn: "created_at",
        timestampValue: job.createdAt,
        payload: job
      });
      return job;
    },
    async close() {
      await pool.end();
    }
  };
}

async function initializePostgresSchema(pool) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS snapshots (
      id TEXT PRIMARY KEY,
      captured_at TIMESTAMPTZ NOT NULL,
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS upload_sessions (
      id TEXT PRIMARY KEY,
      created_at TIMESTAMPTZ NOT NULL,
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS analysis_jobs (
      id TEXT PRIMARY KEY,
      created_at TIMESTAMPTZ NOT NULL,
      payload JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS snapshots_captured_at_idx
    ON snapshots (captured_at DESC)
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS upload_sessions_created_at_idx
    ON upload_sessions (created_at DESC)
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS analysis_jobs_created_at_idx
    ON analysis_jobs (created_at DESC)
  `);
}

async function upsertSnapshot(pool, snapshot) {
  await upsertGenericRecord(pool, {
    tableName: "snapshots",
    id: snapshot.id,
    timestampColumn: "captured_at",
    timestampValue: snapshot.capturedAt,
    payload: snapshot
  });
}

async function upsertGenericRecord(pool, {
  tableName,
  id,
  timestampColumn,
  timestampValue,
  payload
}) {
  const safeTimestamp = coerceTimestamp(timestampValue);
  const safeId = normalizeIdentifier(id);

  const query = `
    INSERT INTO ${tableName} (id, ${timestampColumn}, payload, updated_at)
    VALUES ($1, $2, $3::jsonb, NOW())
    ON CONFLICT (id)
    DO UPDATE SET
      ${timestampColumn} = EXCLUDED.${timestampColumn},
      payload = EXCLUDED.payload,
      updated_at = NOW()
  `;

  await pool.query(query, [
    safeId,
    safeTimestamp,
    JSON.stringify(payload)
  ]);
}

async function readArrayFile(filePath, fallbackValue) {
  try {
    const contents = await readFile(filePath, "utf8");
    const parsed = JSON.parse(contents);
    return Array.isArray(parsed) ? parsed : fallbackValue;
  } catch {
    return fallbackValue;
  }
}

async function writeJSONFile(filePath, value) {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function sortSnapshots(snapshots) {
  return [...snapshots].sort((left, right) => {
    return new Date(right.capturedAt).getTime() - new Date(left.capturedAt).getTime();
  });
}

function upsertById(items, nextItem) {
  const nextId = normalizeIdentifier(nextItem.id);
  const remaining = items.filter((item) => normalizeIdentifier(item.id) !== nextId);
  return [...remaining, nextItem];
}

function parsePayload(value) {
  if (value == null) {
    return null;
  }

  if (typeof value === "string") {
    return JSON.parse(value);
  }

  return value;
}

function coerceTimestamp(value) {
  const fallback = new Date().toISOString();
  if (typeof value !== "string" || value.length === 0) {
    return fallback;
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? fallback : parsed.toISOString();
}

function normalizeIdentifier(value) {
  return String(value ?? "").trim().toLowerCase();
}
