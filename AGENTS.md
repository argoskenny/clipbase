# AGENTS.md

This repository contains ClipBase across multiple platforms. Treat this file as the entrypoint for AI coding agents working in this repo.

## Project Layout

```txt
clipbase/
  web/       # Web implementation: React + Vite + Express + SQLite
  macapp/    # Original macOS SwiftPM app
  iosapp/    # Native iOS SwiftUI app
```

Platform ownership:

- `web/`: source of truth for current full product behavior, API, auth, CSV import/export, and sync protocol.
- `macapp/`: existing SwiftUI macOS app. When updating it, preserve native macOS UX while matching the cross-platform data/sync rules.
- `iosapp/`: native SwiftUI iOS implementation. Keep it aligned with the Web technical reference and sync API docs.

## Required Reading

Before changing cross-platform behavior, read:

- `web/docs/web-app-technical-reference.md`
- `docs/sync-api.md`

Use those documents as the canonical product and sync references. If implementation and docs diverge, inspect the current code and update the docs or code in the same task.

## Product Summary

ClipBase is a protected personal/internal tool for:

- clip library management
- prompt optimizer management
- memo document management
- CSV import/export
- cross-platform sync

The product is currently single-user. Credentials are configured server-side in the Web app. Do not put passwords in frontend or native client code.
The Web app requires `CLIPBASE_USERNAME` and `CLIPBASE_PASSWORD` at startup; do not add fallback credentials.

## Web Platform

Main files:

```txt
web/src/App.tsx
web/src/styles.css
web/server/index.js
web/server/lib/database.js
web/server/lib/auth.js
web/server/lib/csv.js
web/tests/*.test.ts
web/docs/*.md
```

Commands:

```bash
cd web
npm install
npm run dev
npm test
npm run typecheck
npm run build
npm start
```

Set credentials when running the Web app:

```bash
CLIPBASE_USERNAME=your_user CLIPBASE_PASSWORD=your_password npm start
```

For cross-origin deployments, set allowed browser origins explicitly:

```bash
CLIPBASE_ALLOWED_ORIGINS=https://clipbase.example,https://admin.example
```

Default local URL:

```txt
http://127.0.0.1:4174
```

Do not commit generated/runtime artifacts:

```txt
web/node_modules/
web/dist/
web/data/
web/output/
web/.playwright-cli/
```

## macOS Platform

The macOS app is a SwiftPM app in `macapp/`.

Commands:

```bash
cd macapp
swift build
./scripts/build_app.sh
```

Important files:

```txt
macapp/Package.swift
macapp/Sources/ClipBaseApp/*.swift
macapp/Sources/ClipBaseApp/Resources/src.csv
macapp/src.csv
```

The macOS app stores the Bearer session token in `UserDefaults` for this personal-tool build. It stores sync data as a local JSON snapshot with stable IDs, `updatedAt`, `deletedAt`, and tombstones.

## iOS Platform

The iOS app is an Xcode SwiftUI project in `iosapp/`.

Commands:

```bash
cd iosapp
xcodebuild -project ClipBase.xcodeproj -scheme ClipBase -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project ClipBase.xcodeproj -scheme ClipBase -destination 'platform=iOS Simulator,name=iPhone 17' test CODE_SIGNING_ALLOWED=NO
```

If the named simulator is unavailable, replace `iPhone 17` with an installed iOS Simulator.

Important files:

```txt
iosapp/ClipBase.xcodeproj
iosapp/ClipBase/*.swift
iosapp/ClipBase/Assets.xcassets
iosapp/ClipBaseTests/*.swift
```

Before changing iOS product or sync behavior, use:

- `web/docs/web-app-technical-reference.md`
- `docs/sync-api.md`

Current iOS storage:

- A JSON sync snapshot in Application Support for the first native implementation.
- UserDefaults for Bearer API token storage.
- The JSON snapshot must preserve stable IDs, `updatedAt`, `deletedAt`, and tombstones.

Recommended future storage for larger data sets:

- SQLite, SwiftData, or CoreData with the sync fields below.

Do not store passwords in `UserDefaults`. iOS and macOS currently store Bearer session tokens in `UserDefaults` for this personal/internal build.

## Core Data Model

All platforms must model these four entities:

```ts
type Section = {
  id: string;
  title: string;
  position: number;
  updatedAt: number;
  deletedAt: number | null;
};

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

type PromptOptimizer = {
  id: string;
  title: string;
  placement: "prefix" | "suffix";
  affixText: string;
  position: number;
  updatedAt: number;
  deletedAt: number | null;
};

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

Required invariants:

- IDs must be stable across platforms.
- New platform-created records must use UUIDs.
- UI lists must hide records where `deletedAt != null`.
- Sync must keep tombstones. Do not hard delete synced entities during normal operation.

## Sync Rules

Sync is last-write-wins at row level.

```txt
effectiveTime = max(updatedAt, deletedAt || 0)
```

The record with the higher `effectiveTime` wins.

Required behavior:

- Create/edit sets `updatedAt` to current Unix epoch milliseconds.
- Delete sets `deletedAt` to current Unix epoch milliseconds.
- Do not update `lastSyncAt` until all local and remote changes are successfully applied.
- Preserve local changes while offline and sync later.
- If an API call returns `401`, re-authenticate.

Classification rule:

- Deleting a section moves active items in that section to `其它`.
- `其它` must not be deleted.
- If `其它` does not exist, create it.

Prompt optimizer merge rule:

```txt
if input is empty:
  output = affixText
else if placement == "prefix":
  output = affixText + "\n\n" + input
else:
  output = input + "\n\n" + affixText
```

Memo document rule:

- `copyableRanges` stores selected text ranges as `{ start, end }` offsets in `content`.
- Browsing UI highlights only the marked text ranges.
- Clicking a marked memo text range copies only that selected text.
- Save operations should de-duplicate, sort, merge overlapping ranges, and discard out-of-range ranges.

## Sync API

Authentication:

```http
POST /api/login
```

Response includes:

```json
{
  "username": "admin"
}
```

Native clients that need Bearer auth must include `"tokenMode": "bearer"` or `"client": "native"` in the login request. Only then does the response include `"token": "SESSION_TOKEN"`.

Native clients must use:

```http
Authorization: Bearer SESSION_TOKEN
```

Pull sync:

```http
GET /api/sync?since=LAST_SYNC_AT
Authorization: Bearer SESSION_TOKEN
```

Push and pull sync:

```http
POST /api/sync
Authorization: Bearer SESSION_TOKEN
Content-Type: application/json
```

Body:

```json
{
  "since": 0,
  "changes": {
    "sections": [],
    "items": [],
    "optimizers": [],
    "memoDocuments": []
  }
}
```

See `docs/sync-api.md` for exact schemas and examples.

## CSV Format

CSV import/export uses exactly four columns:

```csv
區塊,子區塊,欄位,值
```

Mapping:

- `區塊` -> section title
- no `子區塊` -> item name is `欄位`
- with `子區塊` -> item name is `子區塊 / 欄位`
- `值` -> item content

Special custom item rows:

```csv
📝 自定義項目,Token,訊息,abc
📝 自定義項目,Token,建立時間,2026/01/02
```

Become:

- item name: `Token`
- item content: `abc`
- metadata: `建立時間：2026/01/02`

CSV import/export only covers clip library sections/items. For full Web data backup and restore, use:

```http
GET /api/backup
POST /api/backup/restore
```

The full JSON backup includes sections, items, prompt optimizers, memo documents, sync timestamps, and tombstones.

CSV export neutralizes spreadsheet formulas by prefixing fields that begin with `=`, `+`, `-`, `@`, or whitespace followed by those characters with a single quote. Preserve this behavior when changing CSV output.

## Engineering Rules For Agents

When implementing features:

- Keep changes scoped to the target platform unless cross-platform behavior requires shared documentation updates.
- Update docs when API, sync, data model, or product behavior changes.
- Prefer tests for data model, sync, CSV, auth, and API changes.
- Do not hardcode credentials into frontend or native clients.
- Do not hardcode fallback server credentials.
- Preserve CSRF/Origin checks for unsafe browser requests.
- Do not remove tombstones as part of normal sync.
- Do not change sync conflict rules without updating `docs/sync-api.md` and this file.
- Do not assume Web `GET /api/state` is a sync source. Use `/api/sync` for sync because `/api/state` omits sync metadata.

When changing Web backend behavior:

```bash
cd web
npm test
npm run typecheck
npm run build
```

When changing macOS app behavior:

```bash
cd macapp
swift build
```

When changing iOS app behavior:

```bash
cd iosapp
xcodebuild -project ClipBase.xcodeproj -scheme ClipBase -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project ClipBase.xcodeproj -scheme ClipBase -destination 'platform=iOS Simulator,name=iPhone 17' test CODE_SIGNING_ALLOWED=NO
```

## AI Implementation Checklist

Before finishing a task, verify the relevant items:

- Login works and token is not stored insecurely.
- Web startup requires explicit server-side credentials.
- CRUD behavior matches Web behavior.
- Section delete moves items to `其它`.
- Prompt optimizer merge output matches Web exactly.
- Memo document copyable text ranges are saved and restored.
- Clicking a marked memo text range copies only that selected text.
- CSV import/export remains compatible.
- Sync uses `updatedAt` / `deletedAt`.
- Older changes do not overwrite newer changes.
- Deleted records are hidden from normal UI but retained for sync.
- Tests/build commands for touched platforms pass.
- Documentation remains accurate.

## Current Known Constraints

- Single-user model.
- Session token currently expires after 6 months (180 days).
- Row-level last-write-wins, not field-level merge.
- Device clock drift can affect conflict resolution.
- Sync API currently has no pagination.

If changing any of these constraints, update:

- `web/docs/web-app-technical-reference.md`
- `docs/sync-api.md`
- `AGENTS.md`
