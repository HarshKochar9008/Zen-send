# NeoSapien Share

Real-time cross-device file sharing app built with Flutter and Supabase for the NeoSapien Flutter Developer Intern Assessment.

## Architecture

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter 3.x (Dart) |
| Auth | Supabase Anonymous Auth (no email/password/phone) |
| Database | Supabase Postgres (users, transfers, transfer_files) |
| Storage | Supabase Storage (bucket: `transfers`) |
| Real-time | Supabase Realtime (Postgres CDC on `transfers` table) |
| Integrity | SHA-256 via `package:crypto` (streaming, constant memory) |

### Project Structure

```
lib/
├── main.dart                              # Entry point, Supabase init
├── app.dart                               # MaterialApp + theme
├── core/
│   ├── constants.dart                     # App-wide config (limits, keys)
│   ├── supabase_config.dart               # Supabase singleton
│   └── utils/
│       └── short_code_generator.dart      # Safe-alphabet code generation
└── features/
    ├── identity/
    │   └── identity_service.dart          # Anonymous auth + short code provisioning
    ├── home/
    │   └── home_screen.dart               # Code display, navigation
    ├── send/
    │   └── send_screen.dart               # File pick → hash → stream upload → progress
    ├── receive/
    │   ├── receive_screen.dart            # Realtime subscription, download + verify
    │   └── save_file.dart                 # Platform-specific native file saving
    └── transfer/
        └── transfer_service.dart          # Core: streaming I/O, SHA-256, retry, Realtime
```

### Data Flow

```
[Sender]                              [Supabase]                           [Receiver]
   │                                      │                                    │
   ├─ Pick files (path only, no RAM)      │                                    │
   ├─ Validate sizes / count              │                                    │
   ├─ Compute SHA-256 (streaming)         │                                    │
   ├─ Stream upload ──────────────────────►│ Storage (transfers bucket)         │
   ├─ Insert transfer_files row ──────────►│ Postgres                          │
   │                                      ├─ Realtime CDC ────────────────────►│
   │                                      │                     Auto-refresh   │
   │                                      │◄──────────────── Stream download ──┤
   │                                      │                  Verify SHA-256    │
   │                                      │                  Save to device    │
```

## Features

### Core

- **Anonymous onboarding** — no email, password, or phone number. Uses Supabase anonymous auth with local persistence via SharedPreferences.
- **Unique 6-char short codes** — generated from a safe alphabet (`ABCDEFGHJKMNPQRSTUVWXYZ23456789`) that intentionally excludes ambiguous characters (O/0, I/1/L).
- **Atomic collision handling** — short codes are INSERT-ed directly; Postgres `UNIQUE` constraint violations (error 23505) trigger automatic retry with a new code.
- **Send via recipient code** — validates code against DB, fails fast with inline error if not found.
- **All file types** — images, videos, audio, documents, arbitrary binaries (`FileType.any`).
- **Multiple file transfer** — up to 20 files per transfer, validated before upload.
- **Cross-internet** — works on any network via Supabase cloud endpoints (not limited to same Wi-Fi).

### Transfer Engine

- **Streaming upload** — files are read from disk and streamed directly to Supabase Storage via `HttpClient.addStream()`. The full file is never loaded into RAM. Handles 500MB–1GB files without OOM.
- **Streaming download** — files are downloaded chunk-by-chunk and written directly to a temp file on disk. No in-memory accumulation.
- **SHA-256 integrity** — computed before upload using chunked `file.openRead()` (constant memory). After download, the hash is recomputed and compared. Mismatches are surfaced in the UI.
- **Per-file + aggregate progress** — sender sees individual progress bars (hashing %, uploading %) and an aggregate counter. Receiver sees per-file download progress.
- **Automatic retry** — each file upload retries up to 3 times with exponential backoff (2s, 4s, 6s). Retry count is visible in the UI.
- **File size validation** — rejects files exceeding the configured limit (default 1GB) before upload begins.
- **File name sanitization** — strips path traversal characters (`..`, `<>`, etc.) before constructing storage paths.

### Real-time

- **Supabase Realtime subscription** — the receive screen subscribes to Postgres CDC `INSERT` events on the `transfers` table, filtered by `receiver_id`. New transfers trigger an automatic list refresh.
- **In-app notification** — a SnackBar banner appears when a new transfer arrives while the receive screen is open.
- **Connection indicator** — the empty state shows whether the Realtime channel is active.

### Error Handling

| Scenario | Behavior |
|----------|----------|
| Invalid recipient code | Immediate inline error: `No user found with code "XYZ"` |
| Self-send attempt | Blocked: `You cannot send files to yourself` |
| File too large | Specific error with file name and size limit |
| Too many files | Specific error with count and limit |
| Upload failure | Per-file error state with retry attempt count |
| Download failure | Error state with retry button |
| SHA-256 mismatch | `Integrity check failed — file may be corrupted` |
| Permission denied | Descriptive message (e.g., `Gallery access denied. Please enable in Settings.`) |
| Network error | Descriptive message, retry available |
| Anonymous auth failure | `Ensure anonymous auth is enabled in Supabase` |
| Short code collision | Transparent retry (up to 10 attempts) |

### File Saving

- **Images / videos** → saved to device gallery via `Gal` (NeoShare album)
- **Other files (Android)** → saved to `/Download/` or external storage
- **Other files (iOS)** → saved to app Documents (`NeoShare/` directory)
- **Permissions** — gallery permission requested before save on iOS; Android uses MediaStore/WRITE_EXTERNAL_STORAGE as appropriate

## Setup

### Prerequisites

- Flutter SDK >= 3.0.0
- A Supabase project ([supabase.com](https://supabase.com))

### Environment

1. Copy `.env.example` to `.env`
2. Fill in your Supabase project URL and anon key
3. Update `lib/core/constants.dart` with the same values

### Supabase Configuration

#### 1. Enable Anonymous Auth

Supabase Dashboard → Authentication → Settings → Enable "Allow anonymous sign-ins"

#### 2. Create Tables

```sql
-- Users table
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_uid UUID NOT NULL UNIQUE,
  short_code VARCHAR(8) NOT NULL UNIQUE,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Transfers table
CREATE TABLE transfers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID REFERENCES users(id),
  receiver_id UUID REFERENCES users(id),
  status VARCHAR(20) DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Transfer files table
CREATE TABLE transfer_files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id UUID REFERENCES transfers(id),
  file_name VARCHAR(255) NOT NULL,
  file_size BIGINT NOT NULL,
  mime_type VARCHAR(100),
  storage_path VARCHAR(500) NOT NULL,
  sha256_hash VARCHAR(64),
  created_at TIMESTAMPTZ DEFAULT now()
);
```

#### 3. Create Storage Bucket

Supabase Dashboard → Storage → New Bucket → Name: `transfers`

#### 4. Enable Realtime

Supabase Dashboard → Database → Replication → Enable Realtime for the `transfers` table.

#### 5. RLS Policies (recommended)

```sql
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE transfer_files ENABLE ROW LEVEL SECURITY;

-- Users: anyone can read (for code lookup), auth users can insert their own
CREATE POLICY "Anyone can look up users" ON users FOR SELECT USING (true);
CREATE POLICY "Auth users can insert themselves" ON users FOR INSERT
  WITH CHECK (auth_uid = auth.uid());

-- Transfers: participants can read, auth users can insert
CREATE POLICY "Participants can view transfers" ON transfers FOR SELECT
  USING (
    sender_id IN (SELECT id FROM users WHERE auth_uid = auth.uid())
    OR receiver_id IN (SELECT id FROM users WHERE auth_uid = auth.uid())
  );
CREATE POLICY "Auth users can create transfers" ON transfers FOR INSERT
  WITH CHECK (sender_id IN (SELECT id FROM users WHERE auth_uid = auth.uid()));
CREATE POLICY "Sender can update transfer status" ON transfers FOR UPDATE
  USING (sender_id IN (SELECT id FROM users WHERE auth_uid = auth.uid()));

-- Transfer files: linked to transfers the user can see
CREATE POLICY "Participants can view files" ON transfer_files FOR SELECT
  USING (transfer_id IN (SELECT id FROM transfers WHERE
    sender_id IN (SELECT id FROM users WHERE auth_uid = auth.uid())
    OR receiver_id IN (SELECT id FROM users WHERE auth_uid = auth.uid())
  ));
CREATE POLICY "Sender can insert files" ON transfer_files FOR INSERT
  WITH CHECK (transfer_id IN (SELECT id FROM transfers WHERE
    sender_id IN (SELECT id FROM users WHERE auth_uid = auth.uid())
  ));
```

### Run

```bash
flutter pub get
flutter run
```

## Security

| Concern | Implementation |
|---------|---------------|
| Transport encryption | All Supabase endpoints use **TLS 1.2+** (HTTPS). No plaintext communication. |
| Authentication | Supabase Anonymous Auth with **JWT tokens**. Each device gets a unique auth identity. |
| Storage access | Download URLs are **signed** with 1-hour expiry. No public bucket access. |
| File integrity | **SHA-256** hash computed before upload (streaming) and verified after download. |
| Data isolation | **Row Level Security** policies ensure users can only access their own transfers. |
| API keys | The `supabase_anon_key` is a **public/anonymous key** (not a service role key). Data security is enforced via RLS on the server, not client-side key secrecy. |

## Known Limitations

| Area | Limitation | Path to Fix |
|------|-----------|-------------|
| Push notifications | Not implemented. Transfers are detected via Supabase Realtime (requires app to be open). | Integrate FCM/APNs + Supabase Edge Function webhook |
| Background transfers | Transfers run in the foreground. App kill = failed transfer. | Add `flutter_background_service` or `workmanager` |
| Supabase Storage limits | Free tier: 50MB/file, 1GB total. Pro plan: 5GB/file. | Upgrade Supabase plan or implement chunked/tus uploads |
| State management | Uses `setState` for per-screen state. | Riverpod or Bloc for better testability and separation |
| Platform channels | Pure Flutter/Dart — no native `MethodChannel` code. | Add native hashing, connectivity checks, or file I/O |
| Tests | Placeholder only. Supabase services need mocking. | Add unit tests with `mockito` + `supabase` test helpers |
| TTL enforcement | `transferTtlHours` constant defined but not enforced server-side. | Add Supabase cron/Edge Function to expire old transfers |

## License

MIT
