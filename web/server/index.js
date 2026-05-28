import cookieParser from "cookie-parser";
import express from "express";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createSessionToken, getConfiguredCredentials, getSessionExpiry, shouldReturnBearerToken, verifyCredentials } from "./lib/auth.js";
import { exportCsv, parseCsv } from "./lib/csv.js";
import { ClipDatabase } from "./lib/database.js";
import { getSecurityHeaders, parseAllowedOrigins, shouldRejectCrossOriginRequest } from "./lib/security.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(__dirname, "..");
const projectRoot = resolve(webRoot, "..");
const databasePath = process.env.CLIPBASE_DB_PATH || resolve(webRoot, "data/clipbase.sqlite");
const port = Number(process.env.PORT || 4174);
const app = express();
const store = new ClipDatabase(databasePath);
const configuredCredentials = getConfiguredCredentials();
const allowedOrigins = parseAllowedOrigins(process.env.CLIPBASE_ALLOWED_ORIGINS);
const securityHeaders = getSecurityHeaders(process.env);
const loginAttempts = new Map();

seedDatabaseIfNeeded(store);

app.use(applySecurityHeaders);
app.use(express.json({ limit: "5mb" }));
app.use(cookieParser());
app.use(rejectCrossOriginUnsafeRequests);

app.post("/api/login", (request, response) => {
  if (isLoginRateLimited(request)) {
    response.status(429).json({ error: "登入嘗試過多，請稍後再試" });
    return;
  }

  if (!verifyCredentials(request.body, configuredCredentials)) {
    recordFailedLogin(request);
    response.status(401).json({ error: "帳號或密碼不正確" });
    return;
  }

  clearFailedLogins(request);
  const token = createSessionToken();
  store.createSession(token, configuredCredentials.username, getSessionExpiry());
  response.cookie("clipbase_session", token, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    maxAge: 1000 * 60 * 60 * 12
  });
  response.json({
    username: configuredCredentials.username,
    ...(shouldReturnBearerToken(request.body) ? { token } : {})
  });
});

app.post("/api/logout", (request, response) => {
  const token = request.cookies.clipbase_session;
  if (token) {
    store.deleteSession(token);
  }
  response.clearCookie("clipbase_session");
  response.json({ ok: true });
});

app.get("/api/session", (request, response) => {
  const session = store.getSession(request.cookies.clipbase_session);
  response.json({ authenticated: Boolean(session), username: session?.username || null });
});

app.use("/api", requireAuth);

app.get("/api/state", (_request, response) => {
  response.json(store.getState());
});

app.get("/api/sync", (request, response) => {
  const since = Number(request.query.since || 0);
  response.json({
    serverTime: Date.now(),
    changes: store.getSyncChanges(since)
  });
});

app.post("/api/sync", (request, response, next) => {
  try {
    const since = Number(request.body.since || 0);
    store.applySyncChanges(request.body.changes || {});
    response.json({
      serverTime: Date.now(),
      changes: store.getSyncChanges(since)
    });
  } catch (error) {
    next(error);
  }
});

app.post("/api/sections", (request, response, next) => {
  try {
    response.status(201).json(store.createSection(request.body.title || ""));
  } catch (error) {
    next(error);
  }
});

app.patch("/api/sections/:id", (request, response, next) => {
  try {
    response.json(store.updateSection(request.params.id, request.body.title || ""));
  } catch (error) {
    next(error);
  }
});

app.delete("/api/sections/:id", (request, response, next) => {
  try {
    response.json(store.deleteSection(request.params.id));
  } catch (error) {
    next(error);
  }
});

app.post("/api/items", (request, response, next) => {
  try {
    response.status(201).json(store.createItem(request.body.sectionId, request.body.name || "", request.body.content || ""));
  } catch (error) {
    next(error);
  }
});

app.patch("/api/items/:id", (request, response, next) => {
  try {
    response.json(store.updateItem(request.params.id, request.body.name || "", request.body.content || "", request.body.sectionId || null));
  } catch (error) {
    next(error);
  }
});

app.patch("/api/items/:id/move", (request, response, next) => {
  try {
    store.moveItem(request.params.id, request.body.sectionId);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

app.delete("/api/items/:id", (request, response) => {
  store.deleteItem(request.params.id);
  response.json({ ok: true });
});

app.post("/api/optimizers", (request, response, next) => {
  try {
    response.status(201).json(store.createOptimizer(request.body.title || "", request.body.placement || "prefix", request.body.affixText || ""));
  } catch (error) {
    next(error);
  }
});

app.patch("/api/optimizers/:id", (request, response, next) => {
  try {
    response.json(store.updateOptimizer(request.params.id, request.body.title || "", request.body.placement || "prefix", request.body.affixText || ""));
  } catch (error) {
    next(error);
  }
});

app.delete("/api/optimizers/:id", (request, response) => {
  store.deleteOptimizer(request.params.id);
  response.json({ ok: true });
});

app.post("/api/memo-documents", (request, response, next) => {
  try {
    response.status(201).json(store.createMemoDocument(request.body.title || "", request.body.content || "", request.body.copyableRanges || []));
  } catch (error) {
    next(error);
  }
});

app.patch("/api/memo-documents/:id", (request, response, next) => {
  try {
    response.json(store.updateMemoDocument(request.params.id, request.body.title || "", request.body.content || "", request.body.copyableRanges || []));
  } catch (error) {
    next(error);
  }
});

app.delete("/api/memo-documents/:id", (request, response) => {
  store.deleteMemoDocument(request.params.id);
  response.json({ ok: true });
});

app.post("/api/import", (request, response, next) => {
  try {
    const rows = parseCsv(request.body.csv || "");
    store.importRows(rows);
    response.json(store.getState());
  } catch (error) {
    next(error);
  }
});

app.get("/api/export", (_request, response) => {
  const csv = exportCsv(store.exportRows());
  response.setHeader("Content-Type", "text/csv; charset=utf-8");
  response.setHeader("Content-Disposition", "attachment; filename=\"clipbase-export.csv\"");
  response.send(csv);
});

app.get("/api/backup", (_request, response) => {
  response.setHeader("Content-Type", "application/json; charset=utf-8");
  response.setHeader("Content-Disposition", "attachment; filename=\"clipbase-backup.json\"");
  response.send(JSON.stringify(store.exportBackup(), null, 2));
});

app.post("/api/backup/restore", (request, response, next) => {
  try {
    store.restoreBackup(request.body);
    response.json(store.getState());
  } catch (error) {
    next(error);
  }
});

const distPath = resolve(webRoot, "dist");
if (existsSync(distPath)) {
  app.use(express.static(distPath));
  app.get(/.*/, (_request, response) => {
    response.sendFile(resolve(distPath, "index.html"));
  });
}

app.use((error, _request, response, _next) => {
  const statusCode = error.statusCode || 500;
  response.status(statusCode).json({ error: error.message || "伺服器錯誤" });
});

app.listen(port, "127.0.0.1", () => {
  console.log(`ClipBase API running at http://127.0.0.1:${port}`);
});

function requireAuth(request, response, next) {
  const bearerToken = request.headers.authorization?.startsWith("Bearer ")
    ? request.headers.authorization.slice("Bearer ".length).trim()
    : null;
  const session = store.getSession(bearerToken || request.cookies.clipbase_session);
  if (!session) {
    response.status(401).json({ error: "請先登入" });
    return;
  }

  request.user = session;
  next();
}

function applySecurityHeaders(_request, response, next) {
  for (const [header, value] of Object.entries(securityHeaders)) {
    response.setHeader(header, value);
  }
  next();
}

function rejectCrossOriginUnsafeRequests(request, response, next) {
  if (shouldRejectCrossOriginRequest({
    method: request.method,
    origin: request.headers.origin,
    host: request.headers["x-forwarded-host"] || request.headers.host,
    allowedOrigins
  })) {
    response.status(403).json({ error: "不允許跨來源請求" });
    return;
  }

  next();
}

function seedDatabaseIfNeeded(database) {
  if (!database.isEmpty()) {
    return;
  }

  if (process.env.CLIPBASE_SEED_CSV !== "true" && !process.env.CLIPBASE_SEED_CSV_PATH) {
    return;
  }

  const candidates = process.env.CLIPBASE_SEED_CSV_PATH
    ? [resolve(projectRoot, process.env.CLIPBASE_SEED_CSV_PATH)]
    : [
        resolve(projectRoot, "macapp/Sources/ClipBaseApp/Resources/src.csv"),
        resolve(projectRoot, "macapp/src.csv"),
        resolve(projectRoot, "Sources/ClipBaseApp/Resources/src.csv"),
        resolve(projectRoot, "src.csv")
      ];
  const csvPath = candidates.find((candidate) => existsSync(candidate));
  if (!csvPath) {
    return;
  }

  database.importRows(parseCsv(readFileSync(csvPath, "utf8")));
}

function loginRateLimitKey(request) {
  return request.ip || request.socket.remoteAddress || "unknown";
}

function isLoginRateLimited(request, now = Date.now()) {
  const attempt = loginAttempts.get(loginRateLimitKey(request));
  if (!attempt || attempt.resetAt <= now) {
    return false;
  }

  return attempt.count >= 10;
}

function recordFailedLogin(request, now = Date.now()) {
  const key = loginRateLimitKey(request);
  const existing = loginAttempts.get(key);
  if (!existing || existing.resetAt <= now) {
    loginAttempts.set(key, { count: 1, resetAt: now + 1000 * 60 * 15 });
    return;
  }

  existing.count += 1;
}

function clearFailedLogins(request) {
  loginAttempts.delete(loginRateLimitKey(request));
}
