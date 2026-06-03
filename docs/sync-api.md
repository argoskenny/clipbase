# ClipBase Sync API

這份文件說明 ClipBase 正式 Web API，以及 macOS / iOS / 其它平台 app 應如何串接同步。

同步目標：

- Web 編輯的分類、剪貼項目、提示詞優化器可同步到其它平台。
- 其它平台編輯的資料可同步回 Web。
- 所有衝突依操作時間決定，採用 last-write-wins。
- 刪除也會同步。API 會保留 tombstone，不會直接硬刪同步資料。

## Base URL

正式環境：

```txt
https://clipbase.thelonesomeera.com
```

本機開發：

```txt
http://127.0.0.1:4174
```

以下範例預設使用正式環境。若在本機開發，將 base URL 改為 `http://127.0.0.1:4174`。

## Authentication

### 登入

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

Web 瀏覽器會收到 `clipbase_session` HttpOnly cookie，但 login JSON 不回傳 token。其它平台 app 不使用 cookie，請在 login request 加 `tokenMode: "bearer"` 或 `client: "native"`，儲存 response 的 `token`，後續 API 使用 Bearer token。

```http
Authorization: Bearer SESSION_TOKEN
```

Token 目前有效期為 6 個月（180 天）。過期後 API 會回傳 `401`，app 應重新登入。

Server 啟動前必須設定 `CLIPBASE_USERNAME` 與 `CLIPBASE_PASSWORD`。程式碼不提供預設密碼。

Web server 會檢查 unsafe method (`POST` / `PATCH` / `DELETE`) 的 `Origin` header。若 request 帶有 `Origin`，它必須與目前 Host 相同，或列在 `CLIPBASE_ALLOWED_ORIGINS` 逗號清單中。Native app 通常不送 `Origin`，不會被此檢查擋下。

### 登出

```http
POST /api/logout
Authorization: Bearer SESSION_TOKEN
```

Response:

```json
{
  "ok": true
}
```

## Sync Model

同步資料分成四類：

- `sections`：分類
- `items`：剪貼項目
- `optimizers`：提示詞優化器
- `memoDocuments`：備忘文件

每筆資料都有：

- `id`：全平台共用的穩定 ID。其它平台新增資料時必須產生 UUID。
- `updatedAt`：最後新增或編輯時間，Unix epoch milliseconds。
- `deletedAt`：刪除時間，Unix epoch milliseconds；未刪除為 `null`。

Canonical JSON 建議未刪除時明確傳 `deletedAt: null`，但 Web 接收 `/api/sync` push 時會把省略的 nullable 欄位視為 `null`，以相容 Swift `Codable` 等 native encoder 的預設輸出。這也適用於 item 的 `metadata`。

衝突規則：

```txt
effectiveTime = max(updatedAt, deletedAt || 0)
```

當同一筆 `id` 在兩端都有變更時，`effectiveTime` 較新的版本勝出。較舊的遠端變更會被忽略。

時間要求：

- 請使用毫秒 timestamp，例如 JavaScript `Date.now()`。
- iOS/macOS 可使用 `Int(Date().timeIntervalSince1970 * 1000)`。
- 裝置時間不準會影響同步勝負。若需要更嚴謹，可在 app 端以 API 回傳的 `serverTime` 計算 clock offset。

## Data Shapes

### Section

```json
{
  "id": "uuid-string",
  "title": "測試帳號",
  "position": 0,
  "updatedAt": 1779280000000,
  "deletedAt": null
}
```

欄位：

- `id`：必填。
- `title`：必填。
- `position`：排序用整數。較小排前面。
- `updatedAt`：必填。
- `deletedAt`：未刪除時傳 `null`。

注意：

- 刪除分類時，Web 會將分類內未刪除項目移到 `其它`。
- `其它` 是保護分類，不應由 app 主動刪除。

### Item

```json
{
  "id": "uuid-string",
  "sectionId": "section-uuid",
  "name": "帳號",
  "content": "user@example.com",
  "metadata": null,
  "position": 0,
  "updatedAt": 1779280000000,
  "deletedAt": null
}
```

欄位：

- `id`：必填。
- `sectionId`：必填。若同步進來時該分類不存在或已刪除，Web 會歸到 `其它`。
- `name`：必填。
- `content`：可為空字串，但建議 app 端仍限制非空。
- `metadata`：可為 `null`。目前主要用於顯示「建立時間：...」。
- `position`：排序用整數。較小排前面。
- `updatedAt`：必填。
- `deletedAt`：未刪除時傳 `null`。

### Optimizer

```json
{
  "id": "uuid-string",
  "title": "AI Coding Prompt 優化器",
  "placement": "prefix",
  "affixText": "請將以下內容優化...",
  "position": 0,
  "updatedAt": 1779280000000,
  "deletedAt": null
}
```

欄位：

- `id`：必填。
- `title`：必填。
- `placement`：`prefix` 或 `suffix`。
- `affixText`：必填。
- `position`：排序用整數。
- `updatedAt`：必填。
- `deletedAt`：未刪除時傳 `null`。

### MemoDocument

```json
{
  "id": "uuid-string",
  "title": "會議備忘",
  "content": "第一段\n\n第二段可複製",
  "copyableRanges": [{ "start": 8, "end": 11 }],
  "position": 0,
  "updatedAt": 1779280000000,
  "deletedAt": null
}
```

欄位：

- `id`：必填。
- `title`：必填。
- `content`：長篇文件內容，可為空字串。
- `copyableRanges`：已標記為可複製的文字 range array，`start` / `end` 使用 `content` 內的 0-based text offset。
- `position`：排序用整數。
- `updatedAt`：必填。
- `deletedAt`：未刪除時傳 `null`。

注意：

- Web 會對 `copyableRanges` 去重、排序、合併重疊範圍，並移除超出目前內容長度的 range。
- 瀏覽 UI 只會複製被點擊的 marked range 文字。

## Pull Changes

取得指定時間之後的所有變更。

```http
GET /api/sync?since=1779280000000
Authorization: Bearer SESSION_TOKEN
```

Response:

```json
{
  "serverTime": 1779281234567,
  "changes": {
    "sections": [],
    "items": [],
    "optimizers": [],
    "memoDocuments": []
  }
}
```

`since` 應傳 app 本地最後成功同步後儲存的 high-water mark。第一次同步可傳 `0`。

建議 high-water mark：

```txt
newLastSyncAt = response.serverTime
```

只有當本次同步完整成功套用到本地資料庫後，才更新 `lastSyncAt`。

## Push And Pull Changes

推送本地變更，並同時取得 server 上 `since` 之後的變更。

```http
POST /api/sync
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

Request:

```json
{
  "since": 1779280000000,
  "changes": {
    "sections": [
      {
        "id": "section-id",
        "title": "測試帳號",
        "position": 0,
        "updatedAt": 1779281000000,
        "deletedAt": null
      }
    ],
    "items": [
      {
        "id": "item-id",
        "sectionId": "section-id",
        "name": "帳號",
        "content": "user@example.com",
        "metadata": null,
        "position": 0,
        "updatedAt": 1779281000000,
        "deletedAt": null
      }
    ],
    "optimizers": [],
    "memoDocuments": [
      {
        "id": "memo-id",
        "title": "會議備忘",
        "content": "第一段\n\n第二段可複製",
        "copyableRanges": [{ "start": 8, "end": 11 }],
        "position": 0,
        "updatedAt": 1779281000000,
        "deletedAt": null
      }
    ]
  }
}
```

Response:

```json
{
  "serverTime": 1779281234567,
  "changes": {
    "sections": [],
    "items": [],
    "optimizers": [],
    "memoDocuments": []
  }
}
```

伺服器處理順序：

1. 套用 `sections`
2. 套用 `items`
3. 套用 `optimizers`
4. 套用 `memoDocuments`
5. 回傳 server 端 `since` 之後的所有變更

驗證規則：

- `since` 必須是非負數字。
- `changes.sections`、`changes.items`、`changes.optimizers`、`changes.memoDocuments` 必須都是陣列。
- 每筆 record 必須符合上方 Data Shapes 的必填欄位與型別。
- `updatedAt` 必須是正整數 timestamp；`deletedAt` 必須是正整數 timestamp 或 `null`。
- Nullable 欄位如 `deletedAt`、`metadata` 可省略；Web 會視為 `null`。
- 若任一筆 record 格式不正確，API 會回傳 `400`，且不會套用該次 request 的任何變更。

## App-Side Sync Algorithm

其它平台 app 建議使用本地資料庫，至少要有同樣的四類資料表與同步欄位。

本地需保存：

- `sessionToken`
- `lastSyncAt`
- `dirty` 或可查詢 `updatedAt/deletedAt > lastSyncAt` 的資料

### 第一次同步

1. 使用帳密呼叫 `POST /api/login`。
2. Native/Bearer-token client 在 request 加 `tokenMode: "bearer"`，並儲存 response 的 `token`。
3. 呼叫 `GET /api/sync?since=0`。
4. 將 response changes 寫入本地資料庫。
5. 儲存 `lastSyncAt = response.serverTime`。

### 一般同步

建議流程：

1. 收集本地 `effectiveTime > lastSyncAt` 的變更。
2. 呼叫 `POST /api/sync`，帶入 `since = lastSyncAt` 與本地 changes。
3. 伺服器會套用較新的本地變更，忽略較舊變更。
4. App 將 response changes 套用到本地資料庫。
5. 全部成功後，儲存 `lastSyncAt = response.serverTime`。

Pseudo code:

```pseudo
function sync():
  token = ensureLoggedIn()
  lastSyncAt = loadLastSyncAt()
  localChanges = db.findChangesAfter(lastSyncAt)

  response = POST /api/sync {
    since: lastSyncAt,
    changes: localChanges
  }

  db.transaction:
    applyRemoteChanges(response.changes)
    saveLastSyncAt(response.serverTime)
```

### 套用遠端變更

對每筆遠端資料：

```pseudo
remoteTime = max(remote.updatedAt, remote.deletedAt || 0)
localTime = max(local.updatedAt, local.deletedAt || 0)

if local does not exist:
  insert remote
else if remoteTime > localTime:
  replace local with remote
else:
  ignore remote
```

刪除處理：

```pseudo
if remote.deletedAt != null:
  mark local row deleted
  hide from normal UI
```

不要在同步時硬刪資料，否則未同步的另一端無法得知刪除事件。

## Local Database Recommendation

macOS / iOS 建議本地至少有以下欄位。

### sections

```sql
CREATE TABLE sections (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  position INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
```

### items

```sql
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
```

### optimizers

```sql
CREATE TABLE optimizers (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  placement TEXT NOT NULL,
  affix_text TEXT NOT NULL,
  position INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
```

### memo_documents

```sql
CREATE TABLE memo_documents (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  copyable_ranges TEXT NOT NULL,
  position INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
```

### sync_state

```sql
CREATE TABLE sync_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

可用 `sync_state` 儲存：

- `sessionToken`
- `lastSyncAt`
- `serverClockOffsetMs`，選用

## Platform Implementation Notes

### macOS Swift / iOS Swift

時間：

```swift
let now = Int64(Date().timeIntervalSince1970 * 1000)
```

macOS app 目前將 Bearer token 儲存在 UserDefaults；iOS app 目前將 Bearer token 儲存在 Keychain。不要將密碼儲存在 client 端。

API request header：

```swift
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
```

ID：

```swift
let id = UUID().uuidString
```

同步建議：

- 啟動 app 後同步一次。
- app 進入 foreground 時同步一次。
- 使用者完成新增、編輯、刪除後可 debounce 1-3 秒再同步。
- 網路失敗時保留本地 changes，下次再送。

### Offline Handling

App 可離線新增/編輯/刪除。

離線操作時：

1. 先寫本地資料庫。
2. 設定新的 `updatedAt` 或 `deletedAt`。
3. UI 直接讀本地資料庫。
4. 網路恢復後跑一般同步。

### Delete Rules

刪除項目：

```json
{
  "id": "item-id",
  "sectionId": "section-id",
  "name": "原項目名稱",
  "content": "原內容",
  "metadata": null,
  "position": 0,
  "updatedAt": 1779280000000,
  "deletedAt": 1779282000000
}
```

刪除分類：

- app 端可送 section tombstone。
- app 端也應將該分類下未刪項目移到本地 `其它`。
- Web 收到分類 tombstone 時，也會把仍在該分類的 active items 移到 `其它`。

刪除優化器：

- 設定 optimizer 的 `deletedAt`。
- 一般 UI 不顯示 `deletedAt != null` 的資料。

## Full Backup / Restore

完整備份是 Web 管理用 API，不取代一般跨平台 sync。它用於將目前 Web 資料庫整包匯出到 JSON，再覆蓋式還原到另一個 Web 資料庫。

下載完整備份：

```http
GET /api/backup
Authorization: Bearer SESSION_TOKEN
```

Response:

```json
{
  "version": 1,
  "exportedAt": 1779280000000,
  "changes": {
    "sections": [],
    "items": [],
    "optimizers": [],
    "memoDocuments": []
  }
}
```

還原完整備份：

```http
POST /api/backup/restore
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

Body 使用 `/api/backup` 下載的 JSON。還原會覆蓋 `sections`、`items`、`optimizers`、`memo_documents`，保留 stable IDs、`updatedAt`、`deletedAt` 與 tombstones，但不會還原 session token。

## Error Handling

常見狀態碼：

| Status | Meaning | App action |
| --- | --- | --- |
| `200` | 成功 | 套用 changes 並更新 `lastSyncAt` |
| `400` | request 格式或資料不合法 | 記錄錯誤，保留本地 changes |
| `401` | 未登入或 token 過期 | 重新登入 |
| `404` | 一般 CRUD 找不到資料 | 重新 pull sync 或刷新本地狀態 |
| `500` | server error | 稍後重試 |

同步時若發生錯誤：

- 不要更新 `lastSyncAt`。
- 保留本地 changes。
- 下次重試同一批或重新查詢 `effectiveTime > lastSyncAt` 的資料。

## Example curl

登入：

```bash
BASE_URL="https://clipbase.thelonesomeera.com"
TOKEN=$(curl -s \
  -H 'Content-Type: application/json' \
  -d '{"username":"YOUR_USERNAME","password":"YOUR_PASSWORD","tokenMode":"bearer"}' \
  "$BASE_URL/api/login" \
  | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(JSON.parse(s).token))")
```

第一次拉同步：

```bash
curl -s \
  -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/sync?since=0"
```

推送一個遠端分類：

```bash
NOW=$(node -e 'console.log(Date.now())')

curl -s \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{
    \"since\": 0,
    \"changes\": {
      \"sections\": [
        {
          \"id\": \"remote-section-1\",
          \"title\": \"Remote Section\",
          \"position\": 0,
          \"updatedAt\": $NOW,
          \"deletedAt\": null
        }
      ],
      \"items\": [],
      \"optimizers\": []
    }
  }" \
  "$BASE_URL/api/sync"
```

## Compatibility Notes

目前同步 API 是單一使用者模型。若未來要支援多使用者，需要在所有同步資料表增加 `user_id`，並讓每次 query 依登入 user scope 過濾。

目前衝突解法是 last-write-wins。若未來需要欄位級合併，例如只合併 item name 或 content，需要新增 per-field timestamp 或 operation log。
