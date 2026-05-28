# ClipBase

ClipBase is a personal clip library, prompt optimizer, memo manager, and sync-ready knowledge utility. It is designed for people who frequently reuse account notes, snippets, prompt templates, operational text, or selected parts of longer documents.

The current full implementation is the Web app. A native macOS SwiftUI app is included, and the iOS directory is reserved for future work.

## Features

- Protected single-user login with server-side credentials
- Clip library organized by sections and items
- One-click copy for saved clip content
- Prompt optimizers that merge reusable prefixes or suffixes with input text
- Memo documents with selectable copyable text ranges
- CSV import and export for clip library data
- Full JSON backup and restore
- Cross-platform sync API with stable IDs, tombstones, and last-write-wins conflict handling
- Native macOS SwiftUI app kept in the repository as the original desktop implementation

## Project Layout

```txt
clipbase/
  web/       # React + Vite frontend, Express API, SQLite storage
  macapp/    # Original SwiftPM macOS app
  iosapp/    # Reserved for a future iOS implementation
  docs/      # Cross-platform sync API documentation
```

Key references:

- [Web technical reference](web/docs/web-app-technical-reference.md)
- [Sync API documentation](docs/sync-api.md)
- [macOS app notes](macapp/README.md)

## Web App

The Web app is the source of truth for current product behavior, API, authentication, CSV import/export, backup/restore, and sync.

Tech stack:

- React 19
- Vite
- Express 5
- SQLite through Node.js `node:sqlite`
- Vitest

### Requirements

- Node.js 24 or newer
- npm

### Development

```bash
cd web
npm install
CLIPBASE_USERNAME=admin CLIPBASE_PASSWORD=change-me npm run dev
```

The default local API URL is:

```txt
http://127.0.0.1:4174
```

### Production-Like Local Run

```bash
cd web
npm install
npm run build
CLIPBASE_USERNAME=admin CLIPBASE_PASSWORD=change-me npm start
```

Credentials are required at startup. ClipBase intentionally does not provide fallback usernames or passwords.

For local convenience, you can create `web/.env.local`:

```env
CLIPBASE_USERNAME=admin
CLIPBASE_PASSWORD=change-me
```

Do not commit real credentials. `.env.local` is ignored by Git.

### Useful Commands

```bash
cd web
npm test
npm run typecheck
npm run build
```

## macOS App

The macOS app lives in `macapp/` and uses SwiftPM.

```bash
cd macapp
swift build
./scripts/build_app.sh
```

The Web app remains the canonical implementation for the current data model and sync behavior.

## Sync Model

ClipBase models four entity types across platforms:

- Sections
- Items
- Prompt optimizers
- Memo documents

All synced records use stable IDs and timestamps:

- `id`
- `updatedAt`
- `deletedAt`

Conflict resolution is row-level last-write-wins:

```txt
effectiveTime = max(updatedAt, deletedAt || 0)
```

Deleted records are retained as tombstones for sync and hidden from normal UI. See [docs/sync-api.md](docs/sync-api.md) for the API contract and platform implementation notes.

## CSV Format

CSV import/export for clip data uses exactly four columns:

```csv
區塊,子區塊,欄位,值
```

CSV export neutralizes spreadsheet formulas by prefixing risky values with a single quote. This helps avoid formula injection when exported files are opened in spreadsheet software.

## Security Notes

ClipBase is intended as a protected personal or internal tool.

- Configure credentials only on the server side with `CLIPBASE_USERNAME` and `CLIPBASE_PASSWORD`.
- Do not put passwords in frontend or native client code.
- Browser sessions use HttpOnly cookies.
- Native clients can request Bearer tokens through `/api/login`.
- Runtime data such as SQLite databases, local env files, build outputs, and deployment configs are ignored by Git.
- For public deployments, put ClipBase behind HTTPS and use strong credentials.

## Documentation

For implementation details, start with:

- [web/docs/web-app-technical-reference.md](web/docs/web-app-technical-reference.md)
- [docs/sync-api.md](docs/sync-api.md)

These documents define the current product behavior, sync rules, API shapes, and cross-platform expectations.

## License

No license has been declared yet. Add a license before publishing if you want others to reuse, modify, or redistribute the code under clear terms.
