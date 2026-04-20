# ZenSend

Real-time mobile file sharing app (Android/iOS only) built with Flutter and Supabase for the NeoSapien Flutter Developer Intern Assessment.

## Architecture

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter 3.x (Dart, Android/iOS targets only) |
| Auth | Supabase Anonymous Auth (no email/password/phone) |
| Database | Supabase Postgres (users, transfers, transfer_files) |
| Storage | Supabase Storage (bucket: `transfers`) |
| Real-time | Supabase Realtime (Postgres CDC on `transfers` table) |
| Integrity | SHA-256 via `package:crypto` (streaming, constant memory) |
| Connectivity | `connectivity_plus` for network awareness |
| Transport | TLS 1.2+ via Supabase HTTPS endpoints (all traffic encrypted) |

### Project Structure

```
lib/
├── main.dart                              # Entry point, Supabase init, auth listener
├── app.dart                               # MaterialApp + theme
├── core/
│   ├── constants.dart                     # App-wide config (limits, keys, pagination)
│   ├── supabase_config.dart               # Supabase singleton + auth state management
│   ├── network/
│   │   ├── connection_status.dart         # Shared connectivity notifier (connectivity_plus)
│   │   └── network_errors.dart            # Retryable transport/DNS classification
│   ├── offline/
│   │   ├── offline_sync_coordinator.dart  # When-online drain: FCM DB sync, push invoke queue
│   │   └── pending_backend_jobs.dart      # SharedPreferences queue for deferred backend calls
│   └── utils/
│       └── short_code_generator.dart      # Safe-alphabet code generation
└── features/
    ├── identity/
    │   └── identity_service.dart          # Anonymous auth + short code provisioning + session refresh
    ├── home/
    │   └── home_screen.dart               # Code display, navigation, sent history, connectivity
    ├── send/
    │   └── send_screen.dart               # File pick → hash → stream upload → progress
    ├── receive/
    │   ├── receive_screen.dart            # Realtime subscription, download + verify, TTL, pagination
    │   └── save_file.dart                 # Platform-specific native file saving + permissions
    └── transfer/
        └── transfer_service.dart          # Core: streaming I/O, SHA-256, retry, Realtime, pagination
```

### Data Flow

```
[Sender]                              [Supabase]                           [Receiver]
   │                                      │                                    │
   ├─ Connectivity pre-check              │                                    │
   ├─ Pick files (path only, no RAM)      │                                    │
   ├─ Validate sizes / count / dupes      │                                    │
   ├─ Compute SHA-256 (streaming)         │                                    │
   ├─ Stream upload (with retry) ────────►│ Storage (transfers bucket)         │
   ├─ Insert transfer_files row ─────────►│ Postgres                          │
   │                                      ├─ Realtime CDC ────────────────────►│
   │                                      │                     Auto-refresh   │
   │                                      │◄──────────────── Stream download ──┤
   │                                      │                  Verify SHA-256    │
   │                                      │                  Save to device    │
```

## Features

### Core

- **Anonymous onboarding** — no email, password, or phone number. Uses Supabase anonymous auth with local persistence via SharedPreferences. Session refresh handled automatically.
- **Unique 6-char short codes** — generated from a safe alphabet (`ABCDEFGHJKMNPQRSTUVWXYZ23456789`) that intentionally excludes ambiguous characters (O/0, I/1/L).
- **Atomic collision handling** — short codes are INSERT-ed directly; Postgres `UNIQUE` constraint violations (error 23505) trigger automatic retry with a new code (up to 10 attempts).
- **Send via recipient code** — validates code against DB, fails fast with inline error if not found. Self-send blocked.
- **All file types** — images, videos, audio, documents, arbitrary binaries (`FileType.any`).
- **Multiple file transfer** — up to 20 files per transfer, validated before upload. Duplicate file detection.
- **Cross-internet** — works on any network via Supabase cloud endpoints (not limited to same Wi-Fi).
- **Connectivity awareness** — pre-flight network check before send operations, real-time online/offline indicator on home screen.
- **Offline retry orchestration** — `ConnectionStatus` + `OfflineSyncCoordinator` retry persisted work when connectivity returns: FCM token sync to Supabase, queued `send-transfer-fcm` invokes after uploads, and nudges for an interrupted send (`PendingUploadJob`). See library docs on `lib/core/offline/offline_sync_coordinator.dart`.

### Transfer Engine

- **Resumable TUS upload** — uploads use Supabase’s TUS endpoint (`*.storage.supabase.co/storage/v1/upload/resumable`) with **6 MiB chunks** (Supabase requirement) and a persistent fingerprint store so interrupted uploads **resume from the last confirmed offset** instead of restarting from byte 0. Falls back to a single streaming `POST` if TUS is unavailable (404/405/501).
- **Streaming download** — files are downloaded chunk-by-chunk and written directly to a temp file on disk. No in-memory accumulation. Handles `-1` content length (chunked transfer encoding) gracefully.
- **SHA-256 integrity** — computed before upload using chunked `file.openRead()` (constant memory). After download, the hash is recomputed and compared. Mismatches are surfaced in the UI with clear error messages.
- **Per-file + aggregate progress** — sender sees individual progress bars (hashing %, uploading %) and an aggregate counter. Receiver sees per-file download progress.
- **Automatic retry** — TUS client performs many internal resume/retry cycles; the UI still shows an outer attempt counter for rare hard failures (up to 3 outer passes).
- **File size validation** — rejects files exceeding the configured limit (default 1GB) before upload begins.
- **File name sanitization** — strips path traversal characters (`..`, `<>`, pipe, wildcards) before constructing storage paths.
- **Collision-safe temp files** — downloads use timestamped random prefixes to prevent overwriting when multiple files share the same name.
- **Persistent duplicate delivery prevention** — downloaded file IDs are persisted to `SharedPreferences` keyed by transfer ID. Even after app restart, already-downloaded files show as completed and cannot be re-downloaded.

### Auth & Session Management

- **Auto token refresh** — `SupabaseConfig` listens for `onAuthStateChange` events. Before every API call, `ensureValidSession()` checks token expiry and proactively refreshes if needed.
- **Session recovery** — if the auth session expires but local identity exists, the app re-authenticates anonymously and restores the cached identity.
- **Custom exception types** — `AuthFailedException`, `CodeGenerationException`, `AuthenticationException`, `StorageUploadException`, `NoConnectionException` provide clear, actionable error messages instead of generic exceptions.

### Real-time

- **Supabase Realtime subscription** — the receive screen subscribes to Postgres CDC on the `transfers` table (both `INSERT` and `UPDATE` events), filtered by `receiver_id`. This ensures the receiver is notified both when a transfer is created AND when files finish uploading (status changes to `completed`).
- **Smart notifications** — different SnackBar messages for new incoming transfer vs. files-ready-to-download.
- **Connection indicator** — the empty state shows whether the Realtime channel is active.

### Error Handling

| Scenario | Behavior |
|----------|----------|
| Invalid recipient code | Immediate inline error: `No user found with code "XYZ"` |
| Self-send attempt | Blocked: `You cannot send files to yourself` |
| No internet | Pre-flight check: `No internet connection. Please try again.` |
| File too large | Specific error with file name and size limit |
| Too many files | Specific error with count and limit |
| Duplicate files | Alert dialog listing already-added file names |
| Upload failure | Per-file error state with retry attempt count |
| Download failure | Error state with retry button |
| SHA-256 mismatch | `Integrity check failed — file may be corrupted` |
| Permission denied | Descriptive message (e.g., `Gallery access denied. Please enable in Settings.`) |
| Network error | Descriptive message, retry available; lists auto-refresh when back online if the last load failed |
| FCM token not saved (offline) | Pending flag; retried when device is online (`OfflineSyncCoordinator`) |
| Push edge function failed after upload | Job queued; retried when online (non-network errors dropped) |
| Anonymous auth failure | `Ensure anonymous auth is enabled in Supabase` |
| Short code collision | Transparent retry (up to 10 attempts) |
| Code validation failure | `Could not validate code. Check your connection.` |
| Transfer expired | Visual dimming with "Expired" status badge |

### File Saving

- **Images / videos** → saved to device gallery via `Gal` (ZenSend album)
- **Other files (Android)** → saved to `/Download/` or external storage with unique naming
- **Other files (iOS)** → saved to app Documents (`ZenSend/` directory)
- **Unique file names** — existing files are not overwritten; a `_(1)`, `_(2)` suffix is appended
- **Permissions** — Android: `permission_handler` resolves the correct permission level automatically based on the device's SDK version (granular media for API 33+, storage for older). iOS: `photosAddOnly` with Info.plist descriptions.

### Transfer History

- **Sent transfers** — home screen displays recent sent transfers with recipient code, status, and timestamp
- **Received transfers** — paginated list with infinite scroll, expired transfers shown with visual dimming
- **TTL enforcement** — transfers older than 24 hours are marked as expired client-side

## Setup

### Prerequisites

- Flutter SDK >= 3.0.0
- A Supabase project ([supabase.com](https://supabase.com))

### Environment

1. Copy `.env.example` to `.env`
2. Fill in your Supabase project URL and anon key
3. Run with compile-time defines:
   - `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
4. Do not commit secrets. `lib/core/constants.dart` now reads from `--dart-define`.

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
  fcm_token TEXT,
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

#### 3. Fix ENUM (if you used an ENUM for status)

If you created `transfers.status` as a Postgres ENUM type (e.g. `transfer_status`), it must include all values the app uses. Run this in the SQL Editor:

```sql
-- Option A (recommended): Convert ENUM to VARCHAR for flexibility
ALTER TABLE transfers ALTER COLUMN status TYPE VARCHAR(20) USING status::VARCHAR(20);
DROP TYPE IF EXISTS transfer_status;
```

Or if you want to keep the ENUM, add the missing values:

```sql
-- Option B: Add missing ENUM values
ALTER TYPE transfer_status ADD VALUE IF NOT EXISTS 'failed';
ALTER TYPE transfer_status ADD VALUE IF NOT EXISTS 'partial';
ALTER TYPE transfer_status ADD VALUE IF NOT EXISTS 'uploading';
```

#### 4. Create Storage Bucket

Supabase Dashboard → Storage → New Bucket → Name: `transfers` (set as **private**, NOT public)

#### 5. Enable Realtime

Supabase Dashboard → Database → Replication → Enable Realtime for the `transfers` table.

#### 5b. Push Notifications (Incoming while app closed)

1. **Replace** the checked-in Android placeholder with your real Firebase Android app file:
   - Firebase Console → Project settings → Your apps → Android — the app **package name must match** `applicationId` in `android/app/build.gradle.kts` (currently `com.Zen.app`). Download `google-services.json` → `android/app/google-services.json`.
   - iOS: add `ios/Runner/GoogleService-Info.plist` from the same console (enable Push Notifications + Background Modes → Remote notifications in Xcode).
2. Ensure `users.fcm_token` exists (see schema above). The app registers `FirebaseMessaging.onBackgroundMessage` **before** `Firebase.initializeApp()`, requests Android 13+ notification permission, creates the `incoming_transfers` channel, shows **data-only** pushes in the background isolate, and merges **notification + data** payloads for deep-linking (`transfer_id`, `sender_code`).
3. **Deploy the included Edge Function** `supabase/functions/send-transfer-fcm/` (FCM HTTP v1). Set secrets `FCM_PROJECT_ID` and `FCM_SERVICE_ACCOUNT_JSON` (Firebase service account JSON with *Firebase Cloud Messaging API Admin*). The **app invokes this after upload** — do **not** add a duplicate **Database Webhook** on `transfers` INSERT (that caused multiple notifications per transfer). See `index.ts` header comments.
4. **FCM payload contract** (what the function already sends): `data.transfer_id`, `data.sender_code`, plus `notification.title/body` for system tray display on Android/iOS.

#### 6. RLS Policies (Database Tables)

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

#### 7. Storage Policies (REQUIRED — upload will fail with 403 without these)

Run this in the **SQL Editor** (not the Storage UI):

```sql
-- Allow authenticated users to upload to the transfers bucket
CREATE POLICY "Auth users can upload"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'transfers' AND (SELECT auth.role()) = 'authenticated');

-- Allow authenticated users to read/download from the transfers bucket
CREATE POLICY "Auth users can read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'transfers' AND (SELECT auth.role()) = 'authenticated');

-- Allow authenticated users to update (upsert) files in the transfers bucket
CREATE POLICY "Auth users can update"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'transfers' AND (SELECT auth.role()) = 'authenticated');
```

### Run

```bash
flutter pub get
flutter run
```

### Run Tests

```bash
flutter test
```

## Security

| Concern | Implementation |
|---------|---------------|
| Transport encryption | All Supabase endpoints use **TLS 1.2+** (HTTPS). No plaintext communication. `HttpClient` used for streaming communicates exclusively over HTTPS. |
| Authentication | Supabase Anonymous Auth with **JWT tokens**. Each device gets a unique auth identity. Tokens auto-refreshed before expiry. |
| Storage access | Download URLs are **signed** with 1-hour expiry. No public bucket access. |
| File integrity | **SHA-256** hash computed before upload (streaming) and verified after download. Failures shown in UI. |
| Data isolation | **Row Level Security** policies ensure users can only access their own transfers. |
| Path traversal | File names sanitized — `..`, `<>`, pipes, wildcards stripped before storage path construction. |
| API keys | The `supabase_anon_key` is a **public/anonymous key** (not a service role key). Data security is enforced via RLS on the server. |
| Duplicate delivery | Transfer file IDs persisted to `SharedPreferences` — survives app restarts. |

## Delivery Semantics (Explicit)

- **Recipient offline:** accepted. Upload succeeds to cloud relay, recipient can download later.
- **Transfer TTL:** 24 hours (`AppConstants.transferTtlHours`). Expired transfers are hidden/marked expired.
- **Invalid recipient code:** rejected before upload starts with an inline error.
- **Network drop mid-upload:** uploads use **Supabase TUS** (chunked, resumable). Transient failures retry within the TUS session; outer attempts still cap at 3 for catastrophic errors. If all attempts fail, the file is marked failed with actionable error text.
- **Upload/download cancel:** user can cancel in-progress operations from UI.
- **Storage pressure:** receiver checks free disk space before download; if insufficient, download is blocked with a clear message.
- **Incoming while app closed:** FCM + local notifications (foreground + background/terminated data messages) and tap-to-open navigation to `ReceiveScreen` when `transfer_id` is present. Requires real Firebase project files + deployed `send-transfer-fcm` webhook.
- **Closed-app delivery readiness gate:** before upload starts, sender runs a push `dry_run` health check (recipient token + function readiness). If not ready, send is blocked with an actionable message instead of silently delivering without closed-app notification.

## Known Limitations

| Area | Limitation | Path to Fix |
|------|-----------|-------------|
| Push delivery | Deploy `send-transfer-fcm`, set `FCM_*` secrets; client calls the function after upload (no INSERT webhook). Placeholder `google-services.json` must be replaced for real FCM. | Follow §5b |
| Background transfers | Transfers run in the foreground. App kill = failed transfer. | Add `flutter_background_service` or `workmanager` |
| Supabase Storage limits | Free tier: 50MB/file, 1GB total. Pro plan: 5GB/file. | Upgrade Supabase plan or implement chunked/tus uploads |
| Platform channels | Native share sheet implemented with `MethodChannel` (`zensend/native_share`) for Android and iOS. | Extend with native file picker (Pigeon) or MediaStore save channel |
| Server-side TTL | TTL is enforced client-side only (24h cutoff in query). | Add Supabase cron/Edge Function to delete expired files |
| Certificate pinning | Not implemented — relies on OS trust store. | Add `badCertificateCallback` to HttpClient for production |

## Testing

Unit tests cover:
- `ShortCodeGenerator` — correct length, safe alphabet, ambiguous char exclusion, statistical uniqueness
- `TransferService.sanitizeFileName` — path traversal, XSS, control chars, normal names, empty input
- `TransferService.formatFileSize` — bytes, KB, MB, GB formatting
- `AppConstants` — alphabet exclusions, code length, file size limits, TTL

## License

MIT
