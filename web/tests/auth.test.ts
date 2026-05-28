import { describe, expect, test } from "vitest";
import { getConfiguredCredentials, shouldReturnBearerToken, verifyCredentials } from "../server/lib/auth.js";

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
});
