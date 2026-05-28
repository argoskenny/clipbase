const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);
const CONTENT_SECURITY_POLICY = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' https://fonts.googleapis.com",
  "font-src 'self' https://fonts.gstatic.com",
  "img-src 'self' data: blob:",
  "connect-src 'self'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  "object-src 'none'"
].join("; ");

/**
 * @param {NodeJS.ProcessEnv | Record<string, string | undefined>} env
 * @returns {Record<string, string>}
 */
export function getSecurityHeaders(env = process.env) {
  return {
    "Content-Security-Policy": CONTENT_SECURITY_POLICY,
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "X-Frame-Options": "DENY",
    "Cross-Origin-Opener-Policy": "same-origin",
    ...(env.NODE_ENV === "production"
      ? { "Strict-Transport-Security": "max-age=31536000; includeSubDomains" }
      : {})
  };
}

/**
 * @param {{ method?: string, origin?: string, host?: string, allowedOrigins?: string[] }} input
 */
export function shouldRejectCrossOriginRequest({ method, origin, host, allowedOrigins = [] }) {
  if (SAFE_METHODS.has(String(method || "").toUpperCase())) {
    return false;
  }
  if (!origin) {
    return false;
  }

  const normalizedOrigin = normalizeOrigin(origin);
  if (!normalizedOrigin) {
    return true;
  }

  if (allowedOrigins.map(normalizeOrigin).includes(normalizedOrigin)) {
    return false;
  }

  const originHost = new URL(normalizedOrigin).host;
  return originHost !== host;
}

/**
 * @param {string | undefined} value
 * @returns {string[]}
 */
export function parseAllowedOrigins(value = "") {
  return String(value)
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
}

function normalizeOrigin(origin) {
  try {
    const parsed = new URL(origin);
    return `${parsed.protocol}//${parsed.host}`;
  } catch {
    return null;
  }
}
