import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";

describe("API auth and sync validation", () => {
  let dir = "";
  let server: ChildProcessWithoutNullStreams;
  let baseUrl = "";

  beforeEach(async () => {
    dir = mkdtempSync(join(tmpdir(), "clipbase-api-"));
    const port = 43000 + Math.floor(Math.random() * 1000);
    baseUrl = `http://127.0.0.1:${port}`;
    server = spawn("node", ["server/index.js"], {
      cwd: join(process.cwd()),
      env: {
        ...process.env,
        PORT: String(port),
        CLIPBASE_USERNAME: "operator",
        CLIPBASE_PASSWORD: "secret",
        CLIPBASE_DB_PATH: join(dir, "clipbase.sqlite")
      }
    });
    await waitForServer(baseUrl, server);
  });

  afterEach(() => {
    server.kill();
    rmSync(dir, { recursive: true, force: true });
  });

  test("logout revokes bearer tokens", async () => {
    const token = await loginForBearerToken(baseUrl);

    const logoutResponse = await fetch(`${baseUrl}/api/logout`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` }
    });
    expect(logoutResponse.status).toBe(200);

    const syncResponse = await fetch(`${baseUrl}/api/sync?since=0`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    expect(syncResponse.status).toBe(401);
  });

  test("sync rejects invalid request shapes with 400", async () => {
    const token = await loginForBearerToken(baseUrl);

    const missingChangesResponse = await fetch(`${baseUrl}/api/sync`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ since: 0 })
    });
    expect(missingChangesResponse.status).toBe(400);

    const wrongBucketTypeResponse = await fetch(`${baseUrl}/api/sync`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        since: 0,
        changes: {
          sections: {},
          items: [],
          optimizers: [],
          memoDocuments: []
        }
      })
    });
    expect(wrongBucketTypeResponse.status).toBe(400);
  });
});

async function loginForBearerToken(baseUrl: string) {
  const response = await fetch(`${baseUrl}/api/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      username: "operator",
      password: "secret",
      tokenMode: "bearer"
    })
  });
  const body = await response.json();
  return body.token;
}

async function waitForServer(baseUrl: string, server: ChildProcessWithoutNullStreams) {
  let output = "";
  server.stdout.on("data", (chunk) => {
    output += chunk.toString();
  });
  server.stderr.on("data", (chunk) => {
    output += chunk.toString();
  });

  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (server.exitCode !== null) {
      throw new Error(`Server exited before startup:\n${output}`);
    }

    try {
      await fetch(`${baseUrl}/api/session`);
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  }

  throw new Error(`Server did not start:\n${output}`);
}
