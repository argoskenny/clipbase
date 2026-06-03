# ClipBase Web Technical Reference

這份文件描述 ClipBase Web 版本的完整功能、資料模型、API、同步規則與跨平台實作指南。

目標讀者：

- 需要製作 macOS app、iOS app、Android app、CLI 或其它 client 的工程師。
- 需要依照現有 Web 版行為重建功能的 AI coding agent。
- 需要理解 Web API 與同步協議的系統整合者。

使用方式：

- 若要重做其它平台 UI，請先讀「產品功能規格」與「UI/UX 行為」。
- 若要串 API，請讀「API Reference」。
- 若要做資料同步，請讀「同步模型」與 [sync-api.md](../../docs/sync-api.md)。
- 若要讓 AI coding agent 實作，請直接把本文件與根目錄 `docs/sync-api.md` 一起放進 prompt context。

## 1. Product Summary

ClipBase 是一個個人/內部用的剪貼資料庫、提示詞優化工具與備忘文件管理工具。

Web 版包含核心能力：

1. 登入保護
2. 剪貼內容管理
3. 提示詞優化器管理
4. 備忘文件管理
5. CSV 匯入/匯出
6. 跨平台資料同步 API

Web 版目前是單一使用者模型。帳密在後端設定，前端不包含帳密。

## 2. Runtime Architecture

目前 Web 版位於：

```txt
web/
```

技術棧：

- Frontend：React 19 + Vite
- Backend：Express 5
- Database：Node 24 built-in `node:sqlite`
- Auth：server-side session token
- Sync：last-write-wins with `updatedAt` / `deletedAt`

主要檔案：

```txt
web/src/App.tsx                  # React UI and client API calls
web/src/styles.css               # UI styling
web/server/index.js              # Express routes
web/server/lib/database.js       # SQLite repository and sync logic
web/server/lib/auth.js           # Login credential verification and sessions
web/server/lib/csv.js            # CSV parse/export
web/tests/*.test.ts              # Unit tests
docs/sync-api.md                 # Dedicated sync API documentation for all platforms
```

開發指令：

```bash
cd web
npm install
CLIPBASE_USERNAME=your_user CLIPBASE_PASSWORD=your_password npm run dev
```

正式/本機 production 啟動：

```bash
cd web
npm run build
CLIPBASE_USERNAME=your_user CLIPBASE_PASSWORD=your_password npm start
```

預設服務：

```txt
http://127.0.0.1:4174
```

Web 版不會預設 seed macOS CSV。若需要以 CSV 初始化空資料庫，可明確設定：

```bash
CLIPBASE_SEED_CSV=true CLIPBASE_USERNAME=your_user CLIPBASE_PASSWORD=your_password npm start
```

若正式環境 Web app 透過不同 origin 呼叫 API，可用逗號設定允許來源：

```bash
CLIPBASE_ALLOWED_ORIGINS=https://clipbase.example,https://admin.example
```

## 3. Product Features

### 3.1 Authentication

Web 版啟動後會先顯示登入頁。

啟動前必須用環境變數設定帳密。程式碼不提供預設密碼，避免公開 repo 或正式部署時誤用固定帳密：

```bash
CLIPBASE_USERNAME=your_user CLIPBASE_PASSWORD=your_password npm start
```

登入成功後：

- Web browser 使用 HttpOnly cookie，login response 不回傳 token。
- 其它平台在 login request 加 `tokenMode: "bearer"` 或 `client: "native"`，使用 response 裡的 `token`，並以 Bearer token 呼叫 API。

### 3.2 Clip Library

剪貼內容由「分類」與「項目」組成。

功能：

- 顯示分類列表
- 顯示分類內項目表格
- 新增分類
- 編輯分類名稱
- 刪除分類
- 新增項目
- 編輯項目
- 移動項目到其它分類
- 刪除項目
- 複製項目內容到 clipboard

分類刪除規則：

- 刪除分類時，分類內的未刪除項目會自動移到 `其它` 分類。
- `其它` 分類不可刪除。
- 若 `其它` 不存在，系統會自動建立。

項目欄位：

- `name`：項目名稱
- `content`：可複製內容
- `metadata`：選用，目前常用於「建立時間：...」
- `sectionId`：所屬分類

### 3.3 Prompt Optimizer

提示詞優化器用於把固定前綴或後綴與使用者輸入合併。

功能：

- 顯示優化器列表
- 新增優化器
- 編輯優化器
- 刪除優化器
- 輸入內容
- 產生合併結果
- 複製合併結果到 clipboard

優化器類型：

- `prefix`：`affixText + "\n\n" + input`
- `suffix`：`input + "\n\n" + affixText`

若 input 為空，複製結果只包含 `affixText`。

### 3.4 Memo Documents

備忘文件用於保存長篇文字內容，並將指定文字片段標記為可快速複製。

功能：

- 顯示備忘文件列表
- 新增文件
- 編輯文件標題與長篇內容
- 刪除文件
- 瀏覽文件內容
- 在編輯器中選取任意文字片段並標記為可複製
- 瀏覽時點擊已標記文字片段，將該段文字複製到 clipboard

`copyableRanges` 保存已標記文字片段在 `content` 中的 `{ start, end }` offset；儲存時會依目前內容去重、排序、合併重疊範圍，並移除超出內容長度的 range。

### 3.5 CSV Import / Export

Web 版支援 CSV 匯入與匯出。

CSV 欄位固定：

```csv
區塊,子區塊,欄位,值
```

對應關係：

- `區塊` → section title
- `子區塊 + 欄位` → item name
- `值` → item content

一般項目：

```csv
📧 測試帳號,,帳號1,user@example.com
🏢 CRM 管理員,香港管理員,帳號,user@example.com
```

匯入後：

- 無子區塊：item name = `欄位`
- 有子區塊：item name = `子區塊 / 欄位`

特殊自定義項目：

```csv
📝 自定義項目,Token,訊息,abc
📝 自定義項目,Token,建立時間,2026/01/02
```

匯入後：

- item name = `Token`
- item content = `abc`
- metadata = `建立時間：2026/01/02`

## 4. Data Model

### 4.1 Section

```ts
type Section = {
  id: string;
  title: string;
  position: number;
  updatedAt: number;
  deletedAt: number | null;
};
```

UI 只顯示 `deletedAt == null` 的 section。

### 4.2 Item

```ts
type Item = {
  id: string;
  sectionId: string;
  name: string;
  content: string;
  metadata: string | null;
  position: number;
  updatedAt: number;
  deletedAt: number | null;
};
```

UI 只顯示 `deletedAt == null` 的 item。

### 4.3 Prompt Optimizer

```ts
type PromptOptimizer = {
  id: string;
  title: string;
  placement: "prefix" | "suffix";
  affixText: string;
  position: number;
  updatedAt: number;
  deletedAt: number | null;
};
```

UI 只顯示 `deletedAt == null` 的 optimizer。

### 4.4 Memo Document

```ts
type MemoDocument = {
  id: string;
  title: string;
  content: string;
  copyableRanges: Array<{ start: number; end: number }>;
  position: number;
  updatedAt: number;
  deletedAt: number | null;
};
```

UI 只顯示 `deletedAt == null` 的 memo document。`copyableRanges` 使用 `content` 內的 0-based text offset。

### 4.5 Stable IDs

所有平台都必須使用穩定 ID。

建議：

- Web：`crypto.randomUUID()` 或 server 產生 UUID。
- Swift：`UUID().uuidString`
- Kotlin：`UUID.randomUUID().toString()`

不要使用資料列 index 或排序位置當 ID。

## 5. API Reference

所有 `/api/*` 端點，除了 `/api/login` 與 `/api/session`，都需要登入。

其它平台請使用：

```http
Authorization: Bearer SESSION_TOKEN
```

所有非 safe method (`POST` / `PATCH` / `DELETE`) 若帶有 `Origin` header，server 會要求 origin 與目前 Host 相同，或出現在 `CLIPBASE_ALLOWED_ORIGINS`。不帶 `Origin` 的 native client / curl request 不會被這個檢查擋下。

### 5.1 Login

```http
POST /api/login
Content-Type: application/json
```

Web browser request:

```json
{
  "username": "YOUR_USERNAME",
  "password": "YOUR_PASSWORD"
}
```

Web browser response:

```json
{
  "username": "YOUR_USERNAME"
}
```

Native/Bearer-token request:

```json
{
  "username": "YOUR_USERNAME",
  "password": "YOUR_PASSWORD",
  "tokenMode": "bearer"
}
```

Native/Bearer-token response:

```json
{
  "username": "YOUR_USERNAME",
  "token": "SESSION_TOKEN"
}
```

### 5.2 Session

```http
GET /api/session
```

Response:

```json
{
  "authenticated": true,
  "username": "admin"
}
```

### 5.3 App State

```http
GET /api/state
Authorization: Bearer SESSION_TOKEN
```

Response:

```json
{
  "sections": [
    {
      "id": "section-id",
      "title": "分類",
      "items": [
        {
          "id": "item-id",
          "name": "項目名稱",
          "content": "項目內容",
          "metadata": null
        }
      ]
    }
  ],
  "optimizers": [
    {
      "id": "optimizer-id",
      "title": "優化器",
      "placement": "prefix",
      "affixText": "..."
    }
  ],
  "memoDocuments": [
    {
      "id": "memo-id",
      "title": "備忘標題",
      "content": "第一段\n\n第二段",
      "copyableRanges": [{ "start": 4, "end": 7 }]
    }
  ]
}
```

注意：`/api/state` 是 UI-friendly shape，不包含 `updatedAt/deletedAt`。其它平台若要同步，應使用 `/api/sync`。

### 5.4 Sections

Create:

```http
POST /api/sections
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

```json
{
  "title": "新分類"
}
```

Update:

```http
PATCH /api/sections/:id
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

```json
{
  "title": "新名稱"
}
```

Delete:

```http
DELETE /api/sections/:id
Authorization: Bearer SESSION_TOKEN
```

刪除分類會把項目搬到 `其它`。

### 5.5 Items

Create:

```http
POST /api/items
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

```json
{
  "sectionId": "section-id",
  "name": "項目名稱",
  "content": "項目內容"
}
```

Update:

```http
PATCH /api/items/:id
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

```json
{
  "sectionId": "section-id",
  "name": "項目名稱",
  "content": "項目內容"
}
```

Move:

```http
PATCH /api/items/:id/move
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

```json
{
  "sectionId": "destination-section-id"
}
```

Delete:

```http
DELETE /api/items/:id
Authorization: Bearer SESSION_TOKEN
```

### 5.6 Prompt Optimizers

Create:

```http
POST /api/optimizers
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

```json
{
  "title": "優化器名稱",
  "placement": "prefix",
  "affixText": "固定提示詞"
}
```

Update:

```http
PATCH /api/optimizers/:id
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

```json
{
  "title": "優化器名稱",
  "placement": "suffix",
  "affixText": "固定提示詞"
}
```

Delete:

```http
DELETE /api/optimizers/:id
Authorization: Bearer SESSION_TOKEN
```

### 5.7 Memo Documents

Create:

```http
POST /api/memo-documents
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

```json
{
  "title": "文件標題",
  "content": "第一段\n\n第二段",
  "copyableRanges": [{ "start": 4, "end": 7 }]
}
```

Update:

```http
PATCH /api/memo-documents/:id
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

```json
{
  "title": "文件標題",
  "content": "第一段\n\n第二段",
  "copyableRanges": [{ "start": 4, "end": 7 }]
}
```

Delete:

```http
DELETE /api/memo-documents/:id
Authorization: Bearer SESSION_TOKEN
```

### 5.8 CSV Import / Export

CSV import/export 只處理剪貼內容的四欄格式，不包含提示詞優化器、備忘文件、`updatedAt` / `deletedAt` 或 tombstones。完整搬移資料請使用 Full Backup / Restore。

CSV export 會防止 spreadsheet formula injection：任何欄位若以 `=`, `+`, `-`, `@` 開頭，或前方空白後接這些字元，輸出時會加上單引號前綴。

Import:

```http
POST /api/import
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

```json
{
  "csv": "區塊,子區塊,欄位,值\n..."
}
```

Export:

```http
GET /api/export
Authorization: Bearer SESSION_TOKEN
```

Response content type:

```txt
text/csv; charset=utf-8
```

### 5.9 Full Backup / Restore

完整備份會輸出 JSON，包含四個同步資料表與 `updatedAt` / `deletedAt`，適合公開 repo 前自行備份正式資料，清空 repo seed 後再到正式機還原。

Export:

```http
GET /api/backup
Authorization: Bearer SESSION_TOKEN
```

Response content type:

```txt
application/json; charset=utf-8
```

Restore:

```http
POST /api/backup/restore
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

Body 為 `/api/backup` 下載的完整 JSON。Restore 是覆蓋式操作，會重建 `sections`、`items`、`optimizers`、`memo_documents`，但不會還原舊 session。

### 5.10 Sync

Pull:

```http
GET /api/sync?since=0
Authorization: Bearer SESSION_TOKEN
```

Push and pull:

```http
POST /api/sync
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

`POST /api/sync` 會先驗證 `since`、四個 changes bucket，以及每筆 record 的必填欄位與型別。任一筆 record 不合法時回傳 `400`，且不套用該次 request 的任何變更。

更多細節見 [sync-api.md](../../docs/sync-api.md)。

## 6. Sync Model

同步使用 last-write-wins。

比較規則：

```txt
effectiveTime = max(updatedAt, deletedAt || 0)
```

新資料勝過舊資料。

重要規則：

- 新增或編輯時更新 `updatedAt`。
- 刪除時不要硬刪，設定 `deletedAt`。
- 一般 UI 隱藏 `deletedAt != null` 的資料。
- 同步 API 必須傳出 tombstone，讓其它平台知道刪除事件。
- `lastSyncAt` 只在完整同步成功後更新。

其它平台應保留本地資料庫，不建議只依賴 memory state。

## 7. UI/UX Behavior For Other Platforms

其它平台可依照平台習慣調整 UI，但行為需一致。

### 7.1 Clip Library UI

必要畫面：

- 分類列表
- 分類內項目列表
- 新增分類
- 編輯分類
- 刪除分類
- 新增項目
- 編輯項目
- 刪除項目
- 移動項目分類
- 複製內容

建議：

- macOS：sidebar + table/detail layout。
- iOS：tab view + navigation list + detail page。
- Android：navigation drawer/bottom nav + list/detail。

分類刪除：

- 刪除前顯示確認。
- 說明項目會移到 `其它`。
- 不允許刪除 `其它`。

### 7.2 Prompt Optimizer UI

必要畫面：

- 優化器列表
- 優化器 detail
- 新增/編輯優化器
- 輸入內容
- 合併結果
- 複製合併結果

合併規則：

```ts
if input is empty:
  output = affixText
else if placement == "prefix":
  output = affixText + "\n\n" + input
else:
  output = input + "\n\n" + affixText
```

### 7.3 Memo Documents UI

必要畫面：

- 備忘文件列表
- 文件瀏覽 detail
- 新增/編輯文件的長篇文字編輯器
- 文字標記狀態

必要行為：

- 新增與編輯都使用同一個簡易長篇文字編輯器。
- 使用者選取 textarea 內的任意文字片段後，可標記該文字為可複製。
- 已標記文字在編輯器 preview 與瀏覽畫面都有明確視覺狀態。
- 瀏覽文件時，點擊已標記文字只複製該段被選取的文字。

### 7.4 Login UI

必要行為：

- 顯示帳號/密碼輸入。
- 登入失敗顯示錯誤。
- Web 登入成功後依賴 HttpOnly cookie；native app 登入時要求 Bearer token 後再儲存 token。
- token 過期或 API 回 `401` 時重新登入。

安全建議：

- macOS：目前 personal-tool build 將 Bearer token 存 UserDefaults。
- iOS：token 存 Keychain。
- Android：token 存 EncryptedSharedPreferences 或 Keystore-backed storage。
- 不要把密碼硬寫在 client code。

## 8. Cross-Platform Implementation Guide

### 8.1 Recommended Local Tables

每個平台都建議建立本地資料庫。

```sql
CREATE TABLE sections (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  position INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE TABLE items (
  id TEXT PRIMARY KEY,
  section_id TEXT NOT NULL,
  name TEXT NOT NULL,
  content TEXT NOT NULL,
  metadata TEXT,
  position INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE TABLE optimizers (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  placement TEXT NOT NULL,
  affix_text TEXT NOT NULL,
  position INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE TABLE memo_documents (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  copyable_ranges TEXT NOT NULL,
  position INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE TABLE sync_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

### 8.2 App Startup

Recommended startup flow:

```pseudo
if no token:
  show login
else:
  load local database
  show UI immediately
  run sync in background
```

### 8.3 Create Operation

```pseudo
function createItem(sectionId, name, content):
  now = currentTimeMillis()
  item = {
    id: uuid(),
    sectionId,
    name,
    content,
    metadata: null,
    position: nextPosition(),
    updatedAt: now,
    deletedAt: null
  }
  db.insert(item)
  scheduleSync()
```

### 8.4 Update Operation

```pseudo
function updateItem(id, patch):
  now = currentTimeMillis()
  db.update(id, patch + { updatedAt: now, deletedAt: null })
  scheduleSync()
```

### 8.5 Delete Operation

```pseudo
function deleteItem(id):
  now = currentTimeMillis()
  db.update(id, { deletedAt: now })
  scheduleSync()
```

### 8.6 Sync Operation

```pseudo
function sync():
  token = tokenStore.load()
  lastSyncAt = syncState.load("lastSyncAt") || 0
  changes = db.findRowsWhereEffectiveTimeGreaterThan(lastSyncAt)

  response = POST /api/sync {
    since: lastSyncAt,
    changes
  }

  db.transaction:
    applyRemoteChanges(response.changes)
    syncState.save("lastSyncAt", response.serverTime)
```

### 8.7 Apply Remote Changes

```pseudo
function applyRemote(remote, table):
  local = db.find(table, remote.id)
  remoteTime = max(remote.updatedAt, remote.deletedAt || 0)

  if local == null:
    db.insert(remote)
    return

  localTime = max(local.updatedAt, local.deletedAt || 0)
  if remoteTime > localTime:
    db.replace(remote)
```

### 8.8 Sync Scheduling

建議觸發點：

- app launch
- app foreground
- user creates/updates/deletes data
- network reconnect
- manual pull-to-refresh

建議節流：

- 使用者連續操作時 debounce 1-3 秒。
- 同時間只允許一個 sync job 執行。
- 若 sync 正在跑，新的操作只標記 dirty，等目前 sync 完再跑下一輪。

### 8.9 Offline Behavior

離線時：

- 所有操作仍寫入本地資料庫。
- UI 從本地資料庫讀取。
- 不更新 `lastSyncAt`。
- 網路恢復後呼叫 sync。

## 9. AI Coding Agent Instructions

若 AI agent 要依此文件實作其它平台 client，請遵守：

1. 先建立本地資料庫 schema。
2. 所有資料都要有穩定 `id`、`updatedAt`、`deletedAt`。
3. 所有新增/編輯/刪除都先寫本地，再排程同步。
4. 不要硬刪資料，除非是清理非常舊的 tombstone 且確定所有平台已同步。
5. API token 儲存位置需符合各平台目前實作；macOS 目前使用 UserDefaults，iOS 使用 Keychain。
6. 同步成功前不可更新 `lastSyncAt`。
7. 收到 `401` 時重新登入。
8. UI 列表只顯示 `deletedAt == null` 的資料。
9. 刪分類時必須把 active items 移到 `其它`。
10. 優化器合併結果必須完全符合 Web 規則。

AI agent 實作前應確認：

- 使用平台：macOS / iOS / Android / CLI / other
- 本地資料庫方案：SQLite / CoreData / SwiftData / Room / other
- API base URL
- token 儲存方案
- 是否需要背景同步
- 是否需要手動同步按鈕

## 10. Verification Checklist

其它平台完成後，至少驗證：

- 登入成功取得 token。
- token 可呼叫 `/api/sync`。
- 第一次同步可拉到 Web 資料。
- Web 新增分類後，app 同步可看到。
- app 新增分類後，Web 同步/刷新可看到。
- Web 編輯 item 後，app 取得較新內容。
- app 編輯 item 後，Web 取得較新內容。
- Web 刪除 item 後，app 隱藏該 item。
- app 刪除 item 後，Web 隱藏該 item。
- 刪除分類後，項目移到 `其它`。
- 優化器 prefix/suffix 合併結果與 Web 一致。
- 離線新增資料後，恢復網路可同步。
- 較舊的遠端變更不會覆蓋較新的本地變更。

## 11. Known Constraints

目前限制：

- 單一使用者。
- session token 6 個月（180 天）有效。
- last-write-wins 是 row-level，不是 field-level。
- 裝置時間不準可能造成衝突判斷不準。
- 同步 API 目前不做分頁；資料量很大時需加 pagination 或 cursor。

未來可擴充：

- 多使用者 `user_id`
- refresh token
- per-field merge
- operation log
- sync pagination
- tombstone retention policy
- background push notification
