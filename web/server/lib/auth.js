import { createHash, randomUUID, timingSafeEqual } from "node:crypto";

const SESSION_TTL_MS = 1000 * 60 * 60 * 12;

export function getConfiguredCredentials(env = process.env) {
  if (!env.CLIPBASE_USERNAME || !env.CLIPBASE_PASSWORD) {
    throw new Error("CLIPBASE_USERNAME and CLIPBASE_PASSWORD are required");
  }

  return {
    username: env.CLIPBASE_USERNAME,
    password: env.CLIPBASE_PASSWORD
  };
}

export function verifyCredentials(input, expected = getConfiguredCredentials()) {
  if (!input?.username || !input?.password) {
    return false;
  }

  return safeEqual(input.username, expected.username) && safeEqual(input.password, expected.password);
}

export function createSessionToken() {
  return randomUUID();
}

export function getSessionExpiry(now = Date.now()) {
  return now + SESSION_TTL_MS;
}

export function shouldReturnBearerToken(input) {
  return input?.tokenMode === "bearer" || input?.client === "native";
}

function safeEqual(left, right) {
  const leftHash = createHash("sha256").update(String(left)).digest();
  const rightHash = createHash("sha256").update(String(right)).digest();
  return timingSafeEqual(leftHash, rightHash);
}
