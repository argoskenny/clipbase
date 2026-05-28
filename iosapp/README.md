# ClipBase iOS App

This directory contains the native SwiftUI iOS implementation of ClipBase.

References before changing product, sync, or data behavior:

- `../web/docs/web-app-technical-reference.md`
- `../docs/sync-api.md`

## Features

- Login with native Bearer-token mode
- Keychain session token storage
- Local offline snapshot with stable IDs, `updatedAt`, `deletedAt`, and tombstones
- `/api/sync` push/pull with row-level last-write-wins
- Clip library CRUD with section delete moving active items to `其它`
- CSV import/export for clip library rows
- Prompt optimizer prefix/suffix merge
- Memo documents with copyable text ranges
- App icon generated from `../appicon.png`

## Commands

```bash
xcodebuild -project ClipBase.xcodeproj -scheme ClipBase -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project ClipBase.xcodeproj -scheme ClipBase -destination 'platform=iOS Simulator,name=iPhone 17' test CODE_SIGNING_ALLOWED=NO
```

Replace `iPhone 17` with an installed simulator name if needed.

## Notes

The first iOS implementation persists the sync snapshot as JSON in Application Support. Keep the snapshot schema aligned with the sync API. Do not store passwords or session tokens in `UserDefaults`; tokens belong in Keychain.
