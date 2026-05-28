import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { createHash, randomUUID } from "node:crypto";
import { DatabaseSync } from "node:sqlite";

const DEFAULT_OPTIMIZER_TEXT = `請將我接下來提供的內容 優化為更清晰、結構化、且適合 AI coding agent（如 Codex / Cursor / GPT）理解與執行的提示詞。

優化原則：
保留原始需求與技術細節，不改變需求本身
讓描述更清楚、可執行、避免歧義
適度加入結構（例如條列、區塊、步驟）
避免冗長敘述
讓 AI 工具更容易理解修改目標與限制

輸出規則：
只輸出優化後的提示詞
不要加入說明、分析或額外文字

以下是需要優化的提示詞：`;

const SYNC_TABLES = ["sections", "items", "optimizers", "memo_documents"];

export class ClipDatabase {
  constructor(databasePath) {
    mkdirSync(dirname(databasePath), { recursive: true });
    this.db = new DatabaseSync(databasePath);
    this.db.exec("PRAGMA foreign_keys = ON");
    this.migrate();
    this.ensureDefaultOptimizers();
  }

  close() {
    this.db.close();
  }

  migrate() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS sections (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL UNIQUE,
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE IF NOT EXISTS items (
        id TEXT PRIMARY KEY,
        section_id TEXT NOT NULL REFERENCES sections(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        content TEXT NOT NULL,
        metadata TEXT,
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE IF NOT EXISTS optimizers (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL UNIQUE,
        placement TEXT NOT NULL CHECK (placement IN ('prefix', 'suffix')),
        affix_text TEXT NOT NULL,
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE IF NOT EXISTS memo_documents (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL UNIQUE,
        content TEXT NOT NULL,
        copyable_paragraphs TEXT NOT NULL DEFAULT '[]',
        copyable_ranges TEXT NOT NULL,
        position INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE IF NOT EXISTS sessions (
        token TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        expires_at INTEGER NOT NULL
      );
    `);

    this.ensureSyncColumns();
    this.ensureMemoDocumentColumns();
  }

  getState() {
    const sections = this.db.prepare("SELECT id, title FROM sections WHERE deleted_at IS NULL ORDER BY position ASC, title ASC").all();
    const items = this.db.prepare(`
      SELECT id, section_id AS sectionId, name, content, metadata
      FROM items
      WHERE deleted_at IS NULL
      ORDER BY position ASC, rowid ASC
    `).all();
    const itemsBySection = new Map();

    for (const item of items) {
      const list = itemsBySection.get(item.sectionId) || [];
      list.push({ id: item.id, name: item.name, content: item.content, metadata: item.metadata ?? null });
      itemsBySection.set(item.sectionId, list);
    }

    return {
      sections: sections.map((section) => ({
        id: section.id,
        title: section.title,
        items: itemsBySection.get(section.id) || []
      })),
      optimizers: this.db.prepare(`
        SELECT id, title, placement, affix_text AS affixText
        FROM optimizers
        WHERE deleted_at IS NULL
        ORDER BY position ASC, rowid ASC
      `).all(),
      memoDocuments: this.db.prepare(`
        SELECT id, title, content, copyable_ranges AS copyableRanges
        FROM memo_documents
        WHERE deleted_at IS NULL
        ORDER BY position ASC, rowid ASC
      `).all().map(mapMemoDocumentRow)
    };
  }

  isEmpty() {
    const row = this.db.prepare("SELECT COUNT(*) AS count FROM sections WHERE deleted_at IS NULL").get();
    return row.count === 0;
  }

  createSection(title, now = Date.now()) {
    const trimmedTitle = title.trim();
    if (!trimmedTitle) {
      throw new ValidationError("分類名稱不可空白");
    }

    const section = {
      id: randomUUID(),
      title: this.uniqueTitle("sections", "title", trimmedTitle)
    };
    const position = this.nextPosition("sections");
    this.db.prepare("INSERT INTO sections (id, title, position, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)")
      .run(section.id, section.title, position, now);
    return { ...section, items: [] };
  }

  updateSection(sectionId, title, now = Date.now()) {
    const trimmedTitle = title.trim();
    if (!trimmedTitle) {
      throw new ValidationError("分類名稱不可空白");
    }
    this.assertSectionExists(sectionId);

    const resolvedTitle = this.uniqueTitle("sections", "title", trimmedTitle, sectionId);
    this.db.prepare("UPDATE sections SET title = ?, updated_at = ?, deleted_at = NULL WHERE id = ?").run(resolvedTitle, now, sectionId);
    return { id: sectionId, title: resolvedTitle };
  }

  deleteSection(sectionId, now = Date.now()) {
    const section = this.db.prepare("SELECT id, title FROM sections WHERE id = ? AND deleted_at IS NULL").get(sectionId);
    if (!section) {
      throw new NotFoundError("找不到分類");
    }
    if (section.title === "其它") {
      throw new ValidationError("其它分類不可刪除");
    }

    const fallback = this.ensureOtherSection(now);
    const firstPosition = this.firstPositionForSection(fallback.id);

    this.db.exec("BEGIN");
    try {
      this.db.prepare("UPDATE items SET section_id = ?, position = position + ?, updated_at = ? WHERE section_id = ? AND deleted_at IS NULL")
        .run(fallback.id, firstPosition - 1, now, sectionId);
      this.db.prepare("UPDATE sections SET deleted_at = ? WHERE id = ?").run(now, sectionId);
      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }

    return fallback;
  }

  createItem(sectionId, name, content, metadata = null, now = Date.now()) {
    const trimmedName = name.trim();
    const trimmedContent = content.trim();
    if (!trimmedName || !trimmedContent) {
      throw new ValidationError("項目名稱與內容不可空白");
    }
    this.assertSectionExists(sectionId);

    const item = {
      id: randomUUID(),
      name: trimmedName,
      content: trimmedContent,
      metadata
    };
    const position = this.firstPositionForSection(sectionId) - 1;
    this.db.prepare(`
      INSERT INTO items (id, section_id, name, content, metadata, position, updated_at, deleted_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, NULL)
    `).run(item.id, sectionId, item.name, item.content, item.metadata, position, now);

    return item;
  }

  updateItem(itemId, name, content, sectionId = null, now = Date.now()) {
    const trimmedName = name.trim();
    const trimmedContent = content.trim();
    if (!trimmedName || !trimmedContent) {
      throw new ValidationError("項目名稱與內容不可空白");
    }

    const item = this.db.prepare("SELECT id, section_id AS sectionId, metadata FROM items WHERE id = ? AND deleted_at IS NULL").get(itemId);
    if (!item) {
      throw new NotFoundError("找不到項目");
    }

    const destinationSectionId = sectionId || item.sectionId;
    this.assertSectionExists(destinationSectionId);
    const position = destinationSectionId === item.sectionId ? null : this.firstPositionForSection(destinationSectionId) - 1;

    if (position === null) {
      this.db.prepare("UPDATE items SET name = ?, content = ?, updated_at = ?, deleted_at = NULL WHERE id = ?")
        .run(trimmedName, trimmedContent, now, itemId);
    } else {
      this.db.prepare("UPDATE items SET name = ?, content = ?, section_id = ?, position = ?, updated_at = ?, deleted_at = NULL WHERE id = ?")
        .run(trimmedName, trimmedContent, destinationSectionId, position, now, itemId);
    }

    return {
      id: itemId,
      name: trimmedName,
      content: trimmedContent,
      metadata: item.metadata ?? null
    };
  }

  moveItem(itemId, destinationSectionId) {
    this.assertSectionExists(destinationSectionId);
    const existing = this.db.prepare("SELECT id FROM items WHERE id = ? AND deleted_at IS NULL").get(itemId);
    if (!existing) {
      throw new NotFoundError("找不到項目");
    }

    const position = this.firstPositionForSection(destinationSectionId) - 1;
    this.db.prepare("UPDATE items SET section_id = ?, position = ?, updated_at = ?, deleted_at = NULL WHERE id = ?")
      .run(destinationSectionId, position, Date.now(), itemId);
  }

  deleteItem(itemId, now = Date.now()) {
    this.db.prepare("UPDATE items SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL").run(now, itemId);
  }

  createOptimizer(title, placement, affixText, now = Date.now()) {
    const trimmedTitle = title.trim();
    const trimmedAffixText = affixText.trim();
    if (!trimmedTitle || !trimmedAffixText) {
      throw new ValidationError("優化器名稱與內容不可空白");
    }
    if (!["prefix", "suffix"].includes(placement)) {
      throw new ValidationError("優化器類型不正確");
    }

    const optimizer = {
      id: randomUUID(),
      title: this.uniqueTitle("optimizers", "title", trimmedTitle),
      placement,
      affixText: trimmedAffixText
    };
    const position = this.nextPosition("optimizers");
    this.db.prepare(`
      INSERT INTO optimizers (id, title, placement, affix_text, position, updated_at, deleted_at)
      VALUES (?, ?, ?, ?, ?, ?, NULL)
    `).run(optimizer.id, optimizer.title, optimizer.placement, optimizer.affixText, position, now);
    return optimizer;
  }

  updateOptimizer(optimizerId, title, placement, affixText, now = Date.now()) {
    const trimmedTitle = title.trim();
    const trimmedAffixText = affixText.trim();
    if (!trimmedTitle || !trimmedAffixText) {
      throw new ValidationError("優化器名稱與內容不可空白");
    }
    if (!["prefix", "suffix"].includes(placement)) {
      throw new ValidationError("優化器類型不正確");
    }

    const existing = this.db.prepare("SELECT id FROM optimizers WHERE id = ? AND deleted_at IS NULL").get(optimizerId);
    if (!existing) {
      throw new NotFoundError("找不到優化器");
    }

    const resolvedTitle = this.uniqueTitle("optimizers", "title", trimmedTitle, optimizerId);
    this.db.prepare("UPDATE optimizers SET title = ?, placement = ?, affix_text = ?, updated_at = ?, deleted_at = NULL WHERE id = ?")
      .run(resolvedTitle, placement, trimmedAffixText, now, optimizerId);

    return {
      id: optimizerId,
      title: resolvedTitle,
      placement,
      affixText: trimmedAffixText
    };
  }

  deleteOptimizer(optimizerId, now = Date.now()) {
    this.db.prepare("UPDATE optimizers SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL").run(now, optimizerId);
  }

  createMemoDocument(title, content = "", copyableRanges = [], now = Date.now()) {
    const trimmedTitle = title.trim();
    if (!trimmedTitle) {
      throw new ValidationError("文件標題不可空白");
    }

    const normalizedContent = String(content ?? "");
    const document = {
      id: randomUUID(),
      title: this.uniqueTitle("memo_documents", "title", trimmedTitle),
      content: normalizedContent,
      copyableRanges: normalizeTextRanges(copyableRanges, normalizedContent)
    };
    const position = this.nextPosition("memo_documents");
    this.db.prepare(`
      INSERT INTO memo_documents (id, title, content, copyable_paragraphs, copyable_ranges, position, updated_at, deleted_at)
      VALUES (?, ?, ?, '[]', ?, ?, ?, NULL)
    `).run(document.id, document.title, document.content, JSON.stringify(document.copyableRanges), position, now);
    return document;
  }

  updateMemoDocument(documentId, title, content = "", copyableRanges = [], now = Date.now()) {
    const trimmedTitle = title.trim();
    if (!trimmedTitle) {
      throw new ValidationError("文件標題不可空白");
    }

    const existing = this.db.prepare("SELECT id FROM memo_documents WHERE id = ? AND deleted_at IS NULL").get(documentId);
    if (!existing) {
      throw new NotFoundError("找不到文件");
    }

    const normalizedContent = String(content ?? "");
    const ranges = normalizeTextRanges(copyableRanges, normalizedContent);
    const resolvedTitle = this.uniqueTitle("memo_documents", "title", trimmedTitle, documentId);
    this.db.prepare(`
      UPDATE memo_documents
      SET title = ?, content = ?, copyable_paragraphs = '[]', copyable_ranges = ?, updated_at = ?, deleted_at = NULL
      WHERE id = ?
    `).run(resolvedTitle, normalizedContent, JSON.stringify(ranges), now, documentId);

    return {
      id: documentId,
      title: resolvedTitle,
      content: normalizedContent,
      copyableRanges: ranges
    };
  }

  deleteMemoDocument(documentId, now = Date.now()) {
    this.db.prepare("UPDATE memo_documents SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL").run(now, documentId);
  }

  importRows(rows) {
    this.replaceRows(rows);
  }

  exportRows() {
    const rows = [];
    const state = this.getState();

    for (const section of state.sections) {
      for (const item of section.items) {
        if (item.metadata?.startsWith("建立時間：")) {
          rows.push({
            section: section.title,
            subsection: item.name,
            field: "訊息",
            value: item.content
          });
          rows.push({
            section: section.title,
            subsection: item.name,
            field: "建立時間",
            value: item.metadata.replace("建立時間：", "")
          });
          continue;
        }

        const { subsection, field } = splitItemName(item.name);
        rows.push({
          section: section.title,
          subsection,
          field,
          value: item.content
        });
      }
    }

    return rows;
  }

  createSession(token, username, expiresAt) {
    this.db.prepare("INSERT INTO sessions (token, username, expires_at) VALUES (?, ?, ?)").run(hashSessionToken(token), username, expiresAt);
  }

  getSession(token, now = Date.now()) {
    if (!token) {
      return null;
    }

    const tokenHash = hashSessionToken(token);
    const session = this.db.prepare("SELECT token, username, expires_at AS expiresAt FROM sessions WHERE token = ?").get(tokenHash);
    if (!session || session.expiresAt <= now) {
      if (session) {
        this.deleteSession(token);
      }
      return null;
    }

    return session;
  }

  deleteSession(token) {
    this.db.prepare("DELETE FROM sessions WHERE token = ?").run(hashSessionToken(token));
  }

  getSyncChanges(since = 0) {
    const changedAfter = Number(since) || 0;

    return {
      sections: this.db.prepare(`
        SELECT id, title, position, updated_at AS updatedAt, deleted_at AS deletedAt
        FROM sections
        WHERE MAX(updated_at, COALESCE(deleted_at, 0)) > ?
        ORDER BY position ASC, rowid ASC
      `).all(changedAfter),
      items: this.db.prepare(`
        SELECT id, section_id AS sectionId, name, content, metadata, position, updated_at AS updatedAt, deleted_at AS deletedAt
        FROM items
        WHERE MAX(updated_at, COALESCE(deleted_at, 0)) > ?
        ORDER BY position ASC, rowid ASC
      `).all(changedAfter),
      optimizers: this.db.prepare(`
        SELECT id, title, placement, affix_text AS affixText, position, updated_at AS updatedAt, deleted_at AS deletedAt
        FROM optimizers
        WHERE MAX(updated_at, COALESCE(deleted_at, 0)) > ?
        ORDER BY position ASC, rowid ASC
      `).all(changedAfter),
      memoDocuments: this.db.prepare(`
        SELECT id, title, content, copyable_ranges AS copyableRanges, position, updated_at AS updatedAt, deleted_at AS deletedAt
        FROM memo_documents
        WHERE MAX(updated_at, COALESCE(deleted_at, 0)) > ?
        ORDER BY position ASC, rowid ASC
      `).all(changedAfter).map(mapMemoDocumentRow)
    };
  }

  exportBackup(exportedAt = Date.now()) {
    return {
      version: 1,
      exportedAt,
      changes: this.getSyncChanges(0)
    };
  }

  restoreBackup(backup) {
    const changes = validateBackup(backup);

    this.db.exec("BEGIN");
    try {
      this.db.prepare("DELETE FROM items").run();
      this.db.prepare("DELETE FROM sections").run();
      this.db.prepare("DELETE FROM optimizers").run();
      this.db.prepare("DELETE FROM memo_documents").run();

      changes.sections.forEach((section, index) => {
        this.db.prepare("INSERT INTO sections (id, title, position, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?)")
          .run(
            section.id,
            String(section.title || "").trim(),
            Number.isFinite(section.position) ? section.position : index,
            normalizeTimestamp(section.updatedAt),
            normalizeNullableTimestamp(section.deletedAt)
          );
      });

      changes.items.forEach((item, index) => {
        this.db.prepare(`
          INSERT INTO items (id, section_id, name, content, metadata, position, updated_at, deleted_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          item.id,
          item.sectionId,
          String(item.name || "").trim(),
          String(item.content ?? ""),
          item.metadata ?? null,
          Number.isFinite(item.position) ? item.position : index,
          normalizeTimestamp(item.updatedAt),
          normalizeNullableTimestamp(item.deletedAt)
        );
      });

      changes.optimizers.forEach((optimizer, index) => {
        const placement = ["prefix", "suffix"].includes(optimizer.placement) ? optimizer.placement : "prefix";
        this.db.prepare(`
          INSERT INTO optimizers (id, title, placement, affix_text, position, updated_at, deleted_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        `).run(
          optimizer.id,
          String(optimizer.title || "").trim(),
          placement,
          String(optimizer.affixText ?? ""),
          Number.isFinite(optimizer.position) ? optimizer.position : index,
          normalizeTimestamp(optimizer.updatedAt),
          normalizeNullableTimestamp(optimizer.deletedAt)
        );
      });

      changes.memoDocuments.forEach((document, index) => {
        const content = String(document.content ?? "");
        const copyableRanges = normalizeTextRanges(document.copyableRanges, content);
        this.db.prepare(`
          INSERT INTO memo_documents (id, title, content, copyable_paragraphs, copyable_ranges, position, updated_at, deleted_at)
          VALUES (?, ?, ?, '[]', ?, ?, ?, ?)
        `).run(
          document.id,
          String(document.title || "").trim(),
          content,
          JSON.stringify(copyableRanges),
          Number.isFinite(document.position) ? document.position : index,
          normalizeTimestamp(document.updatedAt),
          normalizeNullableTimestamp(document.deletedAt)
        );
      });

      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  applySyncChanges(changes = {}) {
    this.db.exec("BEGIN");
    try {
      for (const section of changes.sections || []) {
        this.applySectionSyncChange(section);
      }
      for (const item of changes.items || []) {
        this.applyItemSyncChange(item);
      }
      for (const optimizer of changes.optimizers || []) {
        this.applyOptimizerSyncChange(optimizer);
      }
      for (const document of changes.memoDocuments || []) {
        this.applyMemoDocumentSyncChange(document);
      }
      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  replaceRows(rows) {
    this.db.exec("BEGIN");
    try {
      this.db.prepare("DELETE FROM items").run();
      this.db.prepare("DELETE FROM sections").run();

      const sectionOrder = [];
      const regularItemsBySection = new Map();
      const customGroups = new Map();
      const customOrder = [];

      for (const row of rows) {
        if (!row.section) {
          continue;
        }
        if (!sectionOrder.includes(row.section)) {
          sectionOrder.push(row.section);
        }

        if (row.subsection && (row.field === "建立時間" || row.field === "訊息")) {
          const groupKey = `${row.section}\u0000${row.subsection}`;
          if (!customOrder.includes(groupKey)) {
            customOrder.push(groupKey);
          }
          const group = customGroups.get(groupKey) || { section: row.section, name: row.subsection };
          if (row.field === "建立時間") {
            group.createdAt = row.value;
          } else {
            group.message = row.value;
          }
          customGroups.set(groupKey, group);
          continue;
        }

        const itemName = row.subsection ? `${row.subsection} / ${row.field}` : row.field;
        const list = regularItemsBySection.get(row.section) || [];
        list.push({ name: itemName, content: row.value, metadata: null });
        regularItemsBySection.set(row.section, list);
      }

      sectionOrder.forEach((title, sectionIndex) => {
        const section = {
          id: randomUUID(),
          title: this.uniqueTitle("sections", "title", title)
        };
        const now = Date.now();
        this.db.prepare("INSERT INTO sections (id, title, position, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)")
          .run(section.id, section.title, sectionIndex, now);

        const groupedItems = customOrder
          .map((key) => customGroups.get(key))
          .filter((group) => group?.section === title)
          .map((group) => {
            return {
              name: group.name,
              content: group.message || "",
              metadata: group.createdAt ? `建立時間：${group.createdAt}` : null
            };
          });
        const items = [...(regularItemsBySection.get(title) || []), ...groupedItems];

        items.forEach((item, itemIndex) => {
          this.db.prepare(`
            INSERT INTO items (id, section_id, name, content, metadata, position, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, NULL)
          `).run(randomUUID(), section.id, item.name, item.content, item.metadata, itemIndex, now);
        });
      });

      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  ensureDefaultOptimizers() {
    const row = this.db.prepare("SELECT COUNT(*) AS count FROM optimizers").get();
    if (row.count > 0) {
      return;
    }

    this.createOptimizer("AI Coding Prompt 優化器", "prefix", DEFAULT_OPTIMIZER_TEXT);
  }

  applySectionSyncChange(change) {
    if (!change?.id || !change.title) {
      return;
    }
    if (this.shouldSkipSyncChange("sections", change.id, change.updatedAt, change.deletedAt)) {
      return;
    }

    const position = Number.isFinite(change.position) ? change.position : this.nextPosition("sections");
    const updatedAt = normalizeTimestamp(change.updatedAt);
    const deletedAt = normalizeNullableTimestamp(change.deletedAt);
    const existing = this.db.prepare("SELECT id, title, deleted_at AS deletedAt FROM sections WHERE id = ?").get(change.id);

    if (deletedAt) {
      if (existing?.deletedAt == null && existing?.title !== "其它") {
        const fallback = this.ensureOtherSection(deletedAt);
        const firstPosition = this.firstPositionForSection(fallback.id);
        this.db.prepare("UPDATE items SET section_id = ?, position = position + ?, updated_at = ? WHERE section_id = ? AND deleted_at IS NULL")
          .run(fallback.id, firstPosition - 1, deletedAt, change.id);
      }

      if (existing) {
        this.db.prepare("UPDATE sections SET title = ?, position = ?, updated_at = ?, deleted_at = ? WHERE id = ?")
          .run(existing.title || change.title, position, updatedAt, deletedAt, change.id);
      } else {
        this.db.prepare("INSERT INTO sections (id, title, position, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?)")
          .run(change.id, this.uniqueTitle("sections", "title", change.title, change.id), position, updatedAt, deletedAt);
      }
      return;
    }

    const resolvedTitle = this.uniqueTitle("sections", "title", change.title, change.id);
    if (existing) {
      this.db.prepare("UPDATE sections SET title = ?, position = ?, updated_at = ?, deleted_at = NULL WHERE id = ?")
        .run(resolvedTitle, position, updatedAt, change.id);
    } else {
      this.db.prepare("INSERT INTO sections (id, title, position, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)")
        .run(change.id, resolvedTitle, position, updatedAt);
    }
  }

  applyItemSyncChange(change) {
    if (!change?.id || !change.sectionId || !change.name) {
      return;
    }
    if (this.shouldSkipSyncChange("items", change.id, change.updatedAt, change.deletedAt)) {
      return;
    }

    const updatedAt = normalizeTimestamp(change.updatedAt);
    const deletedAt = normalizeNullableTimestamp(change.deletedAt);
    const position = Number.isFinite(change.position) ? change.position : this.firstPositionForSection(change.sectionId) - 1;
    const targetSectionId = this.resolveActiveSectionId(change.sectionId, maxTimestamp(updatedAt, deletedAt));
    const existing = this.db.prepare("SELECT id FROM items WHERE id = ?").get(change.id);

    if (existing) {
      this.db.prepare(`
        UPDATE items
        SET section_id = ?, name = ?, content = ?, metadata = ?, position = ?, updated_at = ?, deleted_at = ?
        WHERE id = ?
      `).run(
        targetSectionId,
        change.name,
        change.content || "",
        change.metadata ?? null,
        position,
        updatedAt,
        deletedAt,
        change.id
      );
    } else {
      this.db.prepare(`
        INSERT INTO items (id, section_id, name, content, metadata, position, updated_at, deleted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        change.id,
        targetSectionId,
        change.name,
        change.content || "",
        change.metadata ?? null,
        position,
        updatedAt,
        deletedAt
      );
    }
  }

  applyOptimizerSyncChange(change) {
    if (!change?.id || !change.title) {
      return;
    }
    if (this.shouldSkipSyncChange("optimizers", change.id, change.updatedAt, change.deletedAt)) {
      return;
    }

    const placement = ["prefix", "suffix"].includes(change.placement) ? change.placement : "prefix";
    const updatedAt = normalizeTimestamp(change.updatedAt);
    const deletedAt = normalizeNullableTimestamp(change.deletedAt);
    const position = Number.isFinite(change.position) ? change.position : this.nextPosition("optimizers");
    const existing = this.db.prepare("SELECT id FROM optimizers WHERE id = ?").get(change.id);
    const title = this.uniqueTitle("optimizers", "title", change.title, change.id);

    if (existing) {
      this.db.prepare(`
        UPDATE optimizers
        SET title = ?, placement = ?, affix_text = ?, position = ?, updated_at = ?, deleted_at = ?
        WHERE id = ?
      `).run(title, placement, change.affixText || "", position, updatedAt, deletedAt, change.id);
    } else {
      this.db.prepare(`
        INSERT INTO optimizers (id, title, placement, affix_text, position, updated_at, deleted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(change.id, title, placement, change.affixText || "", position, updatedAt, deletedAt);
    }
  }

  applyMemoDocumentSyncChange(change) {
    if (!change?.id || !change.title) {
      return;
    }
    if (this.shouldSkipSyncChange("memo_documents", change.id, change.updatedAt, change.deletedAt)) {
      return;
    }

    const updatedAt = normalizeTimestamp(change.updatedAt);
    const deletedAt = normalizeNullableTimestamp(change.deletedAt);
    const content = String(change.content ?? "");
    const copyableRanges = normalizeTextRanges(change.copyableRanges ?? paragraphMarksToRanges(change.copyableParagraphs, content), content);
    const position = Number.isFinite(change.position) ? change.position : this.nextPosition("memo_documents");
    const existing = this.db.prepare("SELECT id FROM memo_documents WHERE id = ?").get(change.id);
    const title = this.uniqueTitle("memo_documents", "title", change.title, change.id);

    if (existing) {
      this.db.prepare(`
        UPDATE memo_documents
        SET title = ?, content = ?, copyable_paragraphs = '[]', copyable_ranges = ?, position = ?, updated_at = ?, deleted_at = ?
        WHERE id = ?
      `).run(title, content, JSON.stringify(copyableRanges), position, updatedAt, deletedAt, change.id);
    } else {
      this.db.prepare(`
        INSERT INTO memo_documents (id, title, content, copyable_paragraphs, copyable_ranges, position, updated_at, deleted_at)
        VALUES (?, ?, ?, '[]', ?, ?, ?, ?)
      `).run(change.id, title, content, JSON.stringify(copyableRanges), position, updatedAt, deletedAt);
    }
  }

  shouldSkipSyncChange(table, id, updatedAt, deletedAt) {
    const existing = this.db.prepare(`SELECT updated_at AS updatedAt, deleted_at AS deletedAt FROM ${table} WHERE id = ?`).get(id);
    if (!existing) {
      return false;
    }

    return maxTimestamp(normalizeTimestamp(updatedAt), normalizeNullableTimestamp(deletedAt)) <=
      maxTimestamp(existing.updatedAt, existing.deletedAt);
  }

  assertSectionExists(sectionId) {
    const section = this.db.prepare("SELECT id FROM sections WHERE id = ? AND deleted_at IS NULL").get(sectionId);
    if (!section) {
      throw new NotFoundError("找不到分類");
    }
  }

  ensureOtherSection(now = Date.now()) {
    const existing = this.db.prepare("SELECT id, title, deleted_at AS deletedAt FROM sections WHERE title = ?").get("其它");
    if (existing && existing.deletedAt == null) {
      return { id: existing.id, title: existing.title };
    }
    if (existing) {
      this.db.prepare("UPDATE sections SET updated_at = ?, deleted_at = NULL WHERE id = ?").run(now, existing.id);
      return { id: existing.id, title: existing.title };
    }

    const section = {
      id: randomUUID(),
      title: "其它"
    };
    this.db.prepare("INSERT INTO sections (id, title, position, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)")
      .run(section.id, section.title, this.nextPosition("sections"), now);
    return section;
  }

  resolveActiveSectionId(sectionId, now = Date.now()) {
    const section = this.db.prepare("SELECT id FROM sections WHERE id = ? AND deleted_at IS NULL").get(sectionId);
    if (section) {
      return section.id;
    }

    return this.ensureOtherSection(now).id;
  }

  ensureSyncColumns() {
    const now = Date.now();
    for (const table of SYNC_TABLES) {
      const columns = new Set(this.db.prepare(`PRAGMA table_info(${table})`).all().map((column) => column.name));
      if (!columns.has("updated_at")) {
        this.db.prepare(`ALTER TABLE ${table} ADD COLUMN updated_at INTEGER`).run();
        this.db.prepare(`UPDATE ${table} SET updated_at = ? WHERE updated_at IS NULL`).run(now);
      }
      if (!columns.has("deleted_at")) {
        this.db.prepare(`ALTER TABLE ${table} ADD COLUMN deleted_at INTEGER`).run();
      }
    }
  }

  ensureMemoDocumentColumns() {
    const columns = new Set(this.db.prepare("PRAGMA table_info(memo_documents)").all().map((column) => column.name));
    if (!columns.has("copyable_paragraphs")) {
      this.db.prepare("ALTER TABLE memo_documents ADD COLUMN copyable_paragraphs TEXT NOT NULL DEFAULT '[]'").run();
    }
    if (!columns.has("copyable_ranges")) {
      this.db.prepare("ALTER TABLE memo_documents ADD COLUMN copyable_ranges TEXT NOT NULL DEFAULT '[]'").run();
      for (const row of this.db.prepare("SELECT id, content, copyable_paragraphs AS copyableParagraphs FROM memo_documents").all()) {
        this.db.prepare("UPDATE memo_documents SET copyable_ranges = ? WHERE id = ?")
          .run(JSON.stringify(paragraphMarksToRanges(parseJsonArray(row.copyableParagraphs), row.content)), row.id);
      }
    }
  }

  uniqueTitle(table, column, proposedTitle, excludedId = null) {
    const exists = (title) => {
      if (excludedId) {
        return this.db.prepare(`SELECT 1 FROM ${table} WHERE ${column} = ? AND id != ?`).get(title, excludedId);
      }
      return this.db.prepare(`SELECT 1 FROM ${table} WHERE ${column} = ?`).get(title);
    };
    if (!exists(proposedTitle)) {
      return proposedTitle;
    }

    let index = 2;
    while (exists(`${proposedTitle} (${index})`)) {
      index += 1;
    }

    return `${proposedTitle} (${index})`;
  }

  nextPosition(table) {
    const row = this.db.prepare(`SELECT COALESCE(MAX(position), -1) + 1 AS position FROM ${table}`).get();
    return row.position;
  }

  firstPositionForSection(sectionId) {
    const row = this.db.prepare("SELECT COALESCE(MIN(position), 0) AS position FROM items WHERE section_id = ? AND deleted_at IS NULL").get(sectionId);
    return row.position;
  }
}

export class ValidationError extends Error {
  constructor(message) {
    super(message);
    this.statusCode = 400;
  }
}

export class NotFoundError extends Error {
  constructor(message) {
    super(message);
    this.statusCode = 404;
  }
}

function splitItemName(name) {
  const separator = " / ";
  if (!name.includes(separator)) {
    return { subsection: "", field: name };
  }

  const [subsection, ...fieldParts] = name.split(separator);
  return {
    subsection,
    field: fieldParts.join(separator)
  };
}

function mapMemoDocumentRow(row) {
  return {
    ...row,
    copyableRanges: normalizeTextRanges(parseJsonArray(row.copyableRanges), row.content)
  };
}

function parseJsonArray(value) {
  if (Array.isArray(value)) {
    return value;
  }

  try {
    const parsed = JSON.parse(value || "[]");
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function validateBackup(backup) {
  if (!backup || backup.version !== 1 || !backup.changes) {
    throw new ValidationError("備份檔格式不正確");
  }

  const changes = {
    sections: Array.isArray(backup.changes.sections) ? backup.changes.sections : [],
    items: Array.isArray(backup.changes.items) ? backup.changes.items : [],
    optimizers: Array.isArray(backup.changes.optimizers) ? backup.changes.optimizers : [],
    memoDocuments: Array.isArray(backup.changes.memoDocuments) ? backup.changes.memoDocuments : []
  };

  const sectionIds = new Set();
  for (const section of changes.sections) {
    if (!section?.id || !String(section.title || "").trim()) {
      throw new ValidationError("備份檔包含無效分類資料");
    }
    sectionIds.add(section.id);
  }

  for (const item of changes.items) {
    if (!item?.id || !item.sectionId || !String(item.name || "").trim() || !sectionIds.has(item.sectionId)) {
      throw new ValidationError("備份檔包含無效項目資料");
    }
  }

  for (const optimizer of changes.optimizers) {
    if (!optimizer?.id || !String(optimizer.title || "").trim()) {
      throw new ValidationError("備份檔包含無效優化器資料");
    }
  }

  for (const document of changes.memoDocuments) {
    if (!document?.id || !String(document.title || "").trim()) {
      throw new ValidationError("備份檔包含無效備忘文件資料");
    }
  }

  return changes;
}

function normalizeTextRanges(value, content) {
  const contentLength = String(content ?? "").replace(/\r\n/g, "\n").length;
  const ranges = parseJsonArray(value)
    .map((range) => ({ start: Number(range?.start), end: Number(range?.end) }))
    .filter((range) => (
      Number.isInteger(range.start) &&
      Number.isInteger(range.end) &&
      range.start >= 0 &&
      range.end <= contentLength &&
      range.start < range.end
    ))
    .sort((left, right) => left.start - right.start || left.end - right.end);

  const merged = [];
  for (const range of ranges) {
    const previous = merged.at(-1);
    if (previous && range.start <= previous.end) {
      previous.end = Math.max(previous.end, range.end);
      continue;
    }
    merged.push({ ...range });
  }

  return merged;
}

function paragraphMarksToRanges(value, content) {
  const paragraphs = splitParagraphsWithOffsets(content);
  return parseJsonArray(value)
    .filter((index) => Number.isInteger(index) && index >= 0 && index < paragraphs.length)
    .map((index) => paragraphs[index]);
}

function splitParagraphs(content) {
  const normalized = String(content ?? "").replace(/\r\n/g, "\n").trim();
  if (!normalized) {
    return [];
  }

  return normalized.split(/\n\s*\n/g).filter((paragraph) => paragraph.trim());
}

function splitParagraphsWithOffsets(content) {
  const normalized = String(content ?? "").replace(/\r\n/g, "\n");
  return [...normalized.matchAll(/\S[\s\S]*?(?=\n\s*\n|$)/g)].map((match) => ({
    start: match.index ?? 0,
    end: (match.index ?? 0) + match[0].trimEnd().length
  }));
}

function normalizeTimestamp(value) {
  const timestamp = Number(value);
  return Number.isFinite(timestamp) && timestamp > 0 ? timestamp : Date.now();
}

function normalizeNullableTimestamp(value) {
  if (value === null || value === undefined) {
    return null;
  }

  const timestamp = Number(value);
  return Number.isFinite(timestamp) && timestamp > 0 ? timestamp : null;
}

function maxTimestamp(updatedAt, deletedAt) {
  return Math.max(Number(updatedAt) || 0, Number(deletedAt) || 0);
}

function hashSessionToken(token) {
  return createHash("sha256").update(String(token)).digest("hex");
}
