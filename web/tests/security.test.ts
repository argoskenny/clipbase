import { describe, expect, test } from "vitest";
import { getSecurityHeaders, shouldRejectCrossOriginRequest } from "../server/lib/security.js";

describe("security origin checks", () => {
  test("allows safe methods without origin checks", () => {
    expect(
      shouldRejectCrossOriginRequest({
        method: "GET",
        origin: "https://evil.example",
        host: "clipbase.example"
      })
    ).toBe(false);
  });

  test("allows same-origin unsafe requests", () => {
    expect(
      shouldRejectCrossOriginRequest({
        method: "POST",
        origin: "https://clipbase.example",
        host: "clipbase.example"
      })
    ).toBe(false);
  });

  test("allows configured origins for unsafe requests", () => {
    expect(
      shouldRejectCrossOriginRequest({
        method: "DELETE",
        origin: "https://admin.example",
        host: "clipbase.example",
        allowedOrigins: ["https://admin.example"]
      })
    ).toBe(false);
  });

  test("rejects cross-origin unsafe requests", () => {
    expect(
      shouldRejectCrossOriginRequest({
        method: "PATCH",
        origin: "https://evil.example",
        host: "clipbase.example"
      })
    ).toBe(true);
  });

  test("allows unsafe requests without origin for native clients and curl", () => {
    expect(
      shouldRejectCrossOriginRequest({
        method: "POST",
        origin: undefined,
        host: "clipbase.example"
      })
    ).toBe(false);
  });
});

describe("security headers", () => {
  test("sets browser hardening headers", () => {
    expect(getSecurityHeaders({ NODE_ENV: "development" })).toMatchObject({
      "Content-Security-Policy": expect.stringContaining("default-src 'self'"),
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "strict-origin-when-cross-origin",
      "X-Frame-Options": "DENY"
    });
    expect(getSecurityHeaders({ NODE_ENV: "development" })).not.toHaveProperty("Strict-Transport-Security");
  });

  test("sets HSTS in production", () => {
    expect(getSecurityHeaders({ NODE_ENV: "production" })).toMatchObject({
      "Strict-Transport-Security": "max-age=31536000; includeSubDomains"
    });
  });
});
