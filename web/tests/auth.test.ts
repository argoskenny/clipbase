import { describe, expect, test } from "vitest";
import { getConfiguredCredentials, getSessionExpiry, shouldReturnBearerToken, verifyCredentials } from "../server/lib/auth.js";

describe("auth", () => {
  test("accepts server-side configured credentials", () => {
    expect(
      verifyCredentials(
        { username: "operator", password: "secret" },
        { username: "operator", password: "secret" }
      )
    ).toBe(true);
  });

  test("rejects wrong credentials", () => {
    expect(
      verifyCredentials(
        { username: "operator", password: "wrong" },
        { username: "operator", password: "secret" }
      )
    ).toBe(false);
  });

  test("requires explicit configured credentials", () => {
    expect(() => getConfiguredCredentials({})).toThrow(/CLIPBASE_USERNAME/);
    expect(
      getConfiguredCredentials({
        CLIPBASE_USERNAME: "operator",
        CLIPBASE_PASSWORD: "secret"
      })
    ).toEqual({ username: "operator", password: "secret" });
  });

  test("only returns bearer tokens when explicitly requested", () => {
    expect(shouldReturnBearerToken({})).toBe(false);
    expect(shouldReturnBearerToken({ tokenMode: "bearer" })).toBe(true);
    expect(shouldReturnBearerToken({ client: "native" })).toBe(true);
  });

  test("sets session expiry six months after login", () => {
    expect(getSessionExpiry(0)).toBe(1000 * 60 * 60 * 24 * 30 * 6);
  });
});
