# ClipBase macOS

Native SwiftUI macOS client for ClipBase.

## Build

```bash
swift build
```

## Run

```bash
./script/build_and_run.sh
```

The app uses the ClipBase sync API with bearer tokens:

- `POST /api/login` with `tokenMode: "bearer"`
- `POST /api/sync`
- `GET /api/sync?since=...`

Session tokens are stored in UserDefaults for this personal-tool build. Clip data
is stored locally in Application Support with stable IDs, `updatedAt`,
`deletedAt`, and tombstones.
