import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { ClipDatabase } from "../server/lib/database.js";

describe("ClipDatabase", () => {
  let dir = "";
  let db: ClipDatabase;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "clipbase-web-"));
    db = new ClipDatabase(join(dir, "test.sqlite"));
  });

  afterEach(() => {
    db.close();
    rmSync(dir, { recursive: true, force: true });
  });

  test("imports CSV rows into sections and items", () => {
    db.importRows([
      { section: "帳號", subsection: "", field: "Email", value: "a@example.com" },
      { section: "自定義", subsection: "Token", field: "訊息", value: "abc" },
      { section: "自定義", subsection: "Token", field: "建立時間", value: "2026/01/02" }
    ]);

    const state = db.getState();

    expect(state.sections.map((section) => section.title)).toEqual(["帳號", "自定義"]);
    expect(state.sections[0].items[0]).toMatchObject({
      name: "Email",
      content: "a@example.com",
      metadata: null
    });
    expect(state.sections[1].items[0]).toMatchObject({
      name: "Token",
      content: "abc",
      metadata: "建立時間：2026/01/02"
    });
  });

  test("exports metadata items as message and created-at rows", () => {
    db.importRows([
      { section: "自定義", subsection: "Token", field: "訊息", value: "abc" },
      { section: "自定義", subsection: "Token", field: "建立時間", value: "2026/01/02" }
    ]);

    expect(db.exportRows()).toEqual([
      { section: "自定義", subsection: "Token", field: "訊息", value: "abc" },
      { section: "自定義", subsection: "Token", field: "建立時間", value: "2026/01/02" }
    ]);
  });

  test("adds and moves items between sections", () => {
    const source = db.createSection("來源");
    const target = db.createSection("目標");
    const item = db.createItem(source.id, "名稱", "內容");

    db.moveItem(item.id, target.id);

    const state = db.getState();
    expect(state.sections.find((section) => section.id === source.id)?.items).toHaveLength(0);
    expect(state.sections.find((section) => section.id === target.id)?.items[0]).toMatchObject({
      id: item.id,
      name: "名稱"
    });
  });

  test("updates section titles and item content", () => {
    const section = db.createSection("原分類");
    const item = db.createItem(section.id, "原名稱", "原內容");

    db.updateSection(section.id, "新分類");
    db.updateItem(item.id, "新名稱", "新內容");

    const state = db.getState();
    expect(state.sections.find((entry) => entry.id === section.id)?.title).toBe("新分類");
    expect(state.sections[0].items[0]).toMatchObject({
      id: item.id,
      name: "新名稱",
      content: "新內容"
    });
  });

  test("moves items to other section when deleting a section", () => {
    const source = db.createSection("待刪分類");
    const item = db.createItem(source.id, "保留項目", "保留內容");

    const fallback = db.deleteSection(source.id);

    const state = db.getState();
    expect(state.sections.some((section) => section.id === source.id)).toBe(false);
    expect(fallback.title).toBe("其它");
    expect(state.sections.find((section) => section.id === fallback.id)?.items[0]).toMatchObject({
      id: item.id,
      name: "保留項目",
      content: "保留內容"
    });
  });

  test("creates prefix and suffix prompt optimizers", () => {
    const optimizer = db.createOptimizer("潤稿", "prefix", "請優化");

    expect(db.getState().optimizers.find((item) => item.id === optimizer.id)).toMatchObject(optimizer);
  });

  test("updates prompt optimizers", () => {
    const optimizer = db.createOptimizer("潤稿", "prefix", "請優化");

    db.updateOptimizer(optimizer.id, "翻譯", "suffix", "請輸出英文");

    expect(db.getState().optimizers.find((item) => item.id === optimizer.id)).toMatchObject({
      id: optimizer.id,
      title: "翻譯",
      placement: "suffix",
      affixText: "請輸出英文"
    });
  });

  test("creates and updates memo documents with copyable text ranges", () => {
    const content = "第一段\n\n第二段可複製";
    const copyableText = "可複製";
    const start = content.indexOf(copyableText);
    const document = db.createMemoDocument("會議備忘", content, [{ start, end: start + copyableText.length }], 1000);

    expect(db.getState().memoDocuments.find((entry) => entry.id === document.id)).toMatchObject({
      id: document.id,
      title: "會議備忘",
      content,
      copyableRanges: [{ start, end: start + copyableText.length }]
    });

    const updatedContent = "第一段已更新\n\n第二段仍可複製";
    const updatedStart = updatedContent.indexOf("第二段");
    db.updateMemoDocument(document.id, "更新備忘", updatedContent, [{ start: updatedStart, end: updatedStart + "第二段".length }], 1200);

    expect(db.getState().memoDocuments.find((entry) => entry.id === document.id)).toMatchObject({
      id: document.id,
      title: "更新備忘",
      content: updatedContent,
      copyableRanges: [{ start: updatedStart, end: updatedStart + "第二段".length }]
    });
  });

  test("hides deleted memo documents while retaining sync tombstones", () => {
    const document = db.createMemoDocument("待刪備忘", "可保留的歷史內容", [{ start: 0, end: 3 }], 2000);

    db.deleteMemoDocument(document.id, 2500);

    expect(db.getState().memoDocuments).toEqual([]);
    expect(db.getSyncChanges(0).memoDocuments.find((entry) => entry.id === document.id)).toMatchObject({
      id: document.id,
      title: "待刪備忘",
      content: "可保留的歷史內容",
      copyableRanges: [{ start: 0, end: 3 }],
      updatedAt: 2000,
      deletedAt: 2500
    });
  });

  test("returns sync changes with operation timestamps and tombstones", () => {
    const section = db.createSection("同步分類", 1000);
    const item = db.createItem(section.id, "同步項目", "同步內容", null, 1100);
    db.deleteItem(item.id, 1200);

    const changes = db.getSyncChanges(0);

    expect(changes.items.find((entry) => entry.id === item.id)).toMatchObject({
      id: item.id,
      name: "同步項目",
      content: "同步內容",
      updatedAt: 1100,
      deletedAt: 1200
    });
    expect(db.getState().sections.find((entry) => entry.id === section.id)?.items).toEqual([]);
  });

  test("applies newer sync changes and ignores older ones", () => {
    const section = db.createSection("本機分類", 2000);
    const item = db.createItem(section.id, "本機項目", "本機內容", null, 2000);

    db.applySyncChanges({
      sections: [
        {
          id: section.id,
          title: "較舊分類",
          position: 0,
          updatedAt: 1500,
          deletedAt: null
        }
      ],
      items: [
        {
          id: item.id,
          sectionId: section.id,
          name: "遠端項目",
          content: "遠端內容",
          metadata: null,
          position: 0,
          updatedAt: 2500,
          deletedAt: null
        }
      ],
      optimizers: []
    });

    const state = db.getState();
    expect(state.sections.find((entry) => entry.id === section.id)?.title).toBe("本機分類");
    expect(state.sections.find((entry) => entry.id === section.id)?.items[0]).toMatchObject({
      id: item.id,
      name: "遠端項目",
      content: "遠端內容"
    });
  });

  test("moves active items to other when a newer section tombstone syncs in", () => {
    const section = db.createSection("遠端刪除分類", 3000);
    const item = db.createItem(section.id, "待搬項目", "待搬內容", null, 3000);

    db.applySyncChanges({
      sections: [
        {
          id: section.id,
          title: "遠端刪除分類",
          position: 0,
          updatedAt: 3000,
          deletedAt: 3500
        }
      ],
      items: [],
      optimizers: [],
      memoDocuments: []
    });

    const state = db.getState();
    expect(state.sections.some((entry) => entry.id === section.id)).toBe(false);
    expect(state.sections.find((entry) => entry.title === "其它")?.items[0]).toMatchObject({
      id: item.id,
      name: "待搬項目"
    });
  });

  test("applies newer memo document sync changes and ignores older ones", () => {
    const document = db.createMemoDocument("本機備忘", "本機內容", [{ start: 0, end: 2 }], 4000);

    db.applySyncChanges({
      sections: [],
      items: [],
      optimizers: [],
      memoDocuments: [
        {
          id: document.id,
          title: "較舊備忘",
          content: "較舊內容",
          copyableRanges: [],
          position: 0,
          updatedAt: 3000,
          deletedAt: null
        },
        {
          id: "remote-memo",
          title: "遠端備忘",
          content: "遠端第一段\n\n遠端第二段",
          copyableRanges: [{ start: 8, end: 10 }],
          position: 1,
          updatedAt: 4500,
          deletedAt: null
        }
      ]
    });

    const state = db.getState();
    expect(state.memoDocuments.find((entry) => entry.id === document.id)).toMatchObject({
      title: "本機備忘",
      content: "本機內容",
      copyableRanges: [{ start: 0, end: 2 }]
    });
    expect(state.memoDocuments.find((entry) => entry.id === "remote-memo")).toMatchObject({
      title: "遠端備忘",
      content: "遠端第一段\n\n遠端第二段",
      copyableRanges: [{ start: 8, end: 10 }]
    });
  });

  test("exports and restores a full backup with sync metadata and tombstones", () => {
    const section = db.createSection("備份分類", 1000);
    const item = { id: "backup-item" };
    db.applySyncChanges({
      sections: [],
      items: [
        {
          id: item.id,
          sectionId: section.id,
          name: "備份項目",
          content: "備份內容",
          metadata: "建立時間：2026/01/02",
          position: 0,
          updatedAt: 1100,
          deletedAt: null
        }
      ],
      optimizers: [],
      memoDocuments: []
    });
    const optimizer = db.createOptimizer("備份優化器", "suffix", "請補上結論", 1200);
    const memo = db.createMemoDocument("備份備忘", "第一段\n\n第二段", [{ start: 5, end: 8 }], 1300);

    db.deleteItem(item.id, 1400);
    db.deleteSection(section.id, 1500);

    const backup = db.exportBackup(1600);

    const restoreDir = mkdtempSync(join(tmpdir(), "clipbase-restore-"));
    const restoredDb = new ClipDatabase(join(restoreDir, "restore.sqlite"));
    try {
      restoredDb.createSection("應被覆蓋", 2000);
      restoredDb.createOptimizer("應被覆蓋的優化器", "prefix", "temporary", 2000);

      restoredDb.restoreBackup(backup);

      expect(restoredDb.getState().sections.some((entry) => entry.title === "應被覆蓋")).toBe(false);
      expect(restoredDb.getState().optimizers.some((entry) => entry.id === optimizer.id)).toBe(true);
      expect(restoredDb.getState().memoDocuments.find((entry) => entry.id === memo.id)).toMatchObject({
        id: memo.id,
        title: "備份備忘",
        content: "第一段\n\n第二段",
        copyableRanges: [{ start: 5, end: 8 }]
      });

      const restoredChanges = restoredDb.getSyncChanges(0);
      expect(restoredChanges.sections.find((entry) => entry.id === section.id)).toMatchObject({
        id: section.id,
        title: "備份分類",
        updatedAt: 1000,
        deletedAt: 1500
      });
      expect(restoredChanges.items.find((entry) => entry.id === item.id)).toMatchObject({
        id: item.id,
        sectionId: section.id,
        name: "備份項目",
        content: "備份內容",
        metadata: "建立時間：2026/01/02",
        updatedAt: 1100,
        deletedAt: 1400
      });
    } finally {
      restoredDb.close();
      rmSync(restoreDir, { recursive: true, force: true });
    }
  });

  test("stores session token hashes instead of raw tokens", () => {
    db.createSession("raw-session-token", "operator", 5000);

    const storedSession = db.db.prepare("SELECT token, username, expires_at AS expiresAt FROM sessions").get();

    expect(storedSession).toBeTruthy();
    expect(storedSession).toMatchObject({
      username: "operator",
      expiresAt: 5000
    });
    expect(storedSession!.token).not.toBe("raw-session-token");
    expect(storedSession!.token).toMatch(/^[a-f0-9]{64}$/);
    expect(db.getSession("raw-session-token", 1000)).toMatchObject({ username: "operator" });

    db.deleteSession("raw-session-token");

    expect(db.getSession("raw-session-token", 1000)).toBeNull();
  });
});
