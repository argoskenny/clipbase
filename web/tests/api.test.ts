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

  test("sync accepts native payloads that omit nil optional fields", async () => {
    const token = await loginForBearerToken(baseUrl);

    const response = await fetch(`${baseUrl}/api/sync`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        since: 0,
        changes: {
          sections: [
            {
              id: "native-section",
              title: "Native Section",
              position: 0,
              updatedAt: 1000
            }
          ],
          items: [
            {
              id: "native-item",
              sectionId: "native-section",
              name: "Native Item",
              content: "from Swift Codable",
              position: 0,
              updatedAt: 1100
            }
          ],
          optimizers: [
            {
              id: "native-optimizer",
              title: "Native Optimizer",
              placement: "prefix",
              affixText: "Prefix",
              position: 0,
              updatedAt: 1200
            }
          ],
          memoDocuments: [
            {
              id: "native-memo",
              title: "Native Memo",
              content: "copy this",
              copyableRanges: [{ start: 0, end: 4 }],
              position: 0,
              updatedAt: 1300
            }
          ]
        }
      })
    });

    expect(response.status).toBe(200);

    const pullResponse = await fetch(`${baseUrl}/api/sync?since=0`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    const body = await pullResponse.json();
    expect(body.changes.sections).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: "native-section", deletedAt: null })
      ])
    );
    expect(body.changes.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: "native-item", metadata: null, deletedAt: null })
      ])
    );
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

    const malformedRecordResponse = await fetch(`${baseUrl}/api/sync`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        since: 0,
        changes: {
          sections: [
            {
              id: "section-before-invalid-item",
              title: "不應被套用",
              position: 0,
              updatedAt: 1000,
              deletedAt: null
            }
          ],
          items: [
            {
              id: "invalid-item",
              sectionId: "section-before-invalid-item",
              content: "missing name",
              position: 0,
              updatedAt: 1000,
              deletedAt: null
            }
          ],
          optimizers: [],
          memoDocuments: []
        }
      })
    });
    expect(malformedRecordResponse.status).toBe(400);

    const pullResponse = await fetch(`${baseUrl}/api/sync?since=0`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    const pullBody = await pullResponse.json();
    expect(pullBody.changes.sections.some((section: { id: string }) => section.id === "section-before-invalid-item")).toBe(false);

    const invalidEnumResponse = await fetch(`${baseUrl}/api/sync`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        since: 0,
        changes: {
          sections: [],
          items: [],
          optimizers: [
            {
              id: "invalid-optimizer",
              title: "Bad",
              placement: "middle",
              affixText: "text",
              position: 0,
              updatedAt: 1000,
              deletedAt: null
            }
          ],
          memoDocuments: []
        }
      })
    });
    expect(invalidEnumResponse.status).toBe(400);
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
