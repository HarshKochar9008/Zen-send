import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/supabase_config.dart';

// ── Models ───────────────────────────────────────────────────────────────────

enum FileUploadStatus { pending, hashing, uploading, completed, failed }

class FileUploadProgress {
  final String fileName;
  final int fileSize;
  final FileUploadStatus status;
  final double progress;
  final String? sha256;
  final String? error;
  final int attempt;

  const FileUploadProgress({
    required this.fileName,
    required this.fileSize,
    this.status = FileUploadStatus.pending,
    this.progress = 0,
    this.sha256,
    this.error,
    this.attempt = 0,
  });

  FileUploadProgress copyWith({
    FileUploadStatus? status,
    double? progress,
    String? sha256,
    String? error,
    int? attempt,
  }) =>
      FileUploadProgress(
        fileName: fileName,
        fileSize: fileSize,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        sha256: sha256 ?? this.sha256,
        error: error,
        attempt: attempt ?? this.attempt,
      );
}

class TransferResult {
  final bool success;
  final int completedFiles;
  final int totalFiles;
  final List<FileUploadProgress> fileStates;

  const TransferResult({
    required this.success,
    required this.completedFiles,
    required this.totalFiles,
    required this.fileStates,
  });
}

// ── Exceptions ───────────────────────────────────────────────────────────────

class FileTooLargeException implements Exception {
  final String fileName;
  final int size;
  FileTooLargeException(this.fileName, this.size);

  @override
  String toString() =>
      '$fileName is too large (${(size / 1024 / 1024).toStringAsFixed(0)} MB). '
      'Max allowed: ${AppConstants.maxFileSizeBytes ~/ 1024 ~/ 1024} MB.';
}

class TooManyFilesException implements Exception {
  final int count;
  TooManyFilesException(this.count);

  @override
  String toString() =>
      'Too many files ($count). Max: ${AppConstants.maxFilesPerTransfer}.';
}

class IntegrityException implements Exception {
  final String fileName;
  IntegrityException(this.fileName);

  @override
  String toString() => 'Integrity check failed for $fileName.';
}

// ── SHA-256 helper sink ──────────────────────────────────────────────────────

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

// ── Service ──────────────────────────────────────────────────────────────────

class TransferService {
  static const _maxRetries = 3;

  /// Compute SHA-256 of a file using streaming reads (constant memory).
  static Future<String> computeSha256(
    File file, {
    void Function(int processed, int total)? onProgress,
  }) async {
    final fileLength = await file.length();
    final digestSink = _DigestSink();
    final byteSink = sha256.startChunkedConversion(digestSink);

    var processed = 0;
    await for (final chunk in file.openRead()) {
      byteSink.add(chunk);
      processed += chunk.length;
      onProgress?.call(processed, fileLength);
    }

    byteSink.close();
    return digestSink.value!.toString();
  }

  /// Strip dangerous chars from file names to prevent path traversal.
  static String sanitizeFileName(String name) {
    var safe = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    safe = safe.replaceAll('..', '_');
    if (safe.isEmpty) safe = 'unnamed_file';
    return safe;
  }

  // ── Streaming upload (avoids loading full file into RAM) ─────────────────

  static Future<void> _streamUpload({
    required String storagePath,
    required File file,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final session = SupabaseConfig.client.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    final fileLength = await file.length();
    final url = Uri.parse(
      '${AppConstants.supabaseUrl}/storage/v1/object/transfers/$storagePath',
    );

    final httpClient = HttpClient();
    try {
      final request = await httpClient.postUrl(url);
      request.headers.set('Authorization', 'Bearer ${session.accessToken}');
      request.headers.set('apikey', AppConstants.supabaseAnonKey);
      request.headers.set('Content-Type', contentType);
      request.headers.set('x-upsert', 'true');
      request.contentLength = fileLength;

      var bytesSent = 0;
      final progressStream = file.openRead().map((chunk) {
        bytesSent += chunk.length;
        onProgress?.call(bytesSent, fileLength);
        return chunk;
      });

      await request.addStream(progressStream);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 400) {
        throw Exception(
          'Storage upload failed (${response.statusCode}): $body',
        );
      }
    } finally {
      httpClient.close();
    }
  }

  // ── Send files ───────────────────────────────────────────────────────────

  /// Upload files to a recipient using streaming I/O.
  /// Reports per-file progress via [onProgress].
  static Future<TransferResult> sendFiles({
    required String senderId,
    required String receiverId,
    required List<PlatformFile> files,
    required void Function(List<FileUploadProgress> states) onProgress,
  }) async {
    final client = SupabaseConfig.client;

    for (final file in files) {
      if (file.size > AppConstants.maxFileSizeBytes) {
        throw FileTooLargeException(file.name, file.size);
      }
    }
    if (files.length > AppConstants.maxFilesPerTransfer) {
      throw TooManyFilesException(files.length);
    }

    var states = files
        .map((f) => FileUploadProgress(fileName: f.name, fileSize: f.size))
        .toList();
    onProgress(states);

    final transfer = await client
        .from('transfers')
        .insert({
          'sender_id': senderId,
          'receiver_id': receiverId,
          'status': 'uploading',
        })
        .select()
        .single();

    final transferId = transfer['id'] as String;
    var completedCount = 0;

    try {
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        final filePath = file.path;

        if (filePath == null || !await File(filePath).exists()) {
          states = _updateState(
            states,
            i,
            states[i].copyWith(
              status: FileUploadStatus.failed,
              error: 'File not accessible on disk',
            ),
          );
          onProgress(states);
          continue;
        }

        final diskFile = File(filePath);
        final safeName = sanitizeFileName(file.name);
        final mimeType =
            lookupMimeType(file.name) ?? 'application/octet-stream';
        final storagePath = '$transferId/$safeName';

        // ── Phase 1: SHA-256 ────────────────────────────────────────────
        states = _updateState(
          states,
          i,
          states[i].copyWith(status: FileUploadStatus.hashing, progress: 0),
        );
        onProgress(states);

        String hash;
        try {
          hash = await computeSha256(diskFile, onProgress: (p, t) {
            states = _updateState(
              states,
              i,
              states[i].copyWith(progress: t > 0 ? p / t : 0),
            );
            onProgress(states);
          });
        } catch (e) {
          states = _updateState(
            states,
            i,
            states[i].copyWith(
              status: FileUploadStatus.failed,
              error: 'Hash computation failed',
            ),
          );
          onProgress(states);
          continue;
        }

        // ── Phase 2: Upload with retry ──────────────────────────────────
        states = _updateState(
          states,
          i,
          states[i].copyWith(
            status: FileUploadStatus.uploading,
            sha256: hash,
            progress: 0,
          ),
        );
        onProgress(states);

        var uploaded = false;
        String? lastError;

        for (var attempt = 1; attempt <= _maxRetries; attempt++) {
          try {
            states = _updateState(
              states,
              i,
              states[i].copyWith(attempt: attempt, progress: 0),
            );
            onProgress(states);

            await _streamUpload(
              storagePath: storagePath,
              file: diskFile,
              contentType: mimeType,
              onProgress: (sent, total) {
                states = _updateState(
                  states,
                  i,
                  states[i].copyWith(
                    progress: total > 0 ? sent / total : 0,
                  ),
                );
                onProgress(states);
              },
            );

            await _insertTransferFile({
              'transfer_id': transferId,
              'file_name': safeName,
              'file_size': file.size,
              'mime_type': mimeType,
              'storage_path': storagePath,
              'sha256_hash': hash,
            });

            uploaded = true;
            break;
          } catch (e) {
            lastError = e.toString();
            if (attempt < _maxRetries) {
              await Future.delayed(Duration(seconds: attempt * 2));
            }
          }
        }

        if (uploaded) {
          completedCount++;
          states = _updateState(
            states,
            i,
            states[i].copyWith(
              status: FileUploadStatus.completed,
              progress: 1.0,
            ),
          );
        } else {
          states = _updateState(
            states,
            i,
            states[i].copyWith(
              status: FileUploadStatus.failed,
              error: 'Failed after $_maxRetries attempts: $lastError',
            ),
          );
        }
        onProgress(states);
      }

      final allDone =
          states.every((s) => s.status == FileUploadStatus.completed);
      final anyDone =
          states.any((s) => s.status == FileUploadStatus.completed);

      await client
          .from('transfers')
          .update({
            'status': allDone
                ? 'completed'
                : anyDone
                    ? 'partial'
                    : 'failed',
          })
          .eq('id', transferId);

      return TransferResult(
        success: allDone,
        completedFiles: completedCount,
        totalFiles: files.length,
        fileStates: states,
      );
    } catch (e) {
      await client
          .from('transfers')
          .update({'status': 'failed'})
          .eq('id', transferId);
      rethrow;
    }
  }

  /// Insert a transfer_files row. Falls back without sha256_hash if the
  /// column does not exist yet in the user's Supabase schema.
  static Future<void> _insertTransferFile(Map<String, dynamic> data) async {
    try {
      await SupabaseConfig.client.from('transfer_files').insert(data);
    } on PostgrestException {
      final fallback = Map<String, dynamic>.from(data)..remove('sha256_hash');
      await SupabaseConfig.client.from('transfer_files').insert(fallback);
    }
  }

  static List<FileUploadProgress> _updateState(
    List<FileUploadProgress> states,
    int index,
    FileUploadProgress newState,
  ) {
    final updated = List<FileUploadProgress>.from(states);
    updated[index] = newState;
    return updated;
  }

  // ── Incoming transfers ───────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getIncomingTransfers(
    String userId,
  ) async {
    final result = await SupabaseConfig.client
        .from('transfers')
        .select('*, sender:users!transfers_sender_id_fkey(short_code)')
        .eq('receiver_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  static Future<List<Map<String, dynamic>>> getTransferFiles(
    String transferId,
  ) async {
    final result = await SupabaseConfig.client
        .from('transfer_files')
        .select()
        .eq('transfer_id', transferId)
        .order('created_at');

    return List<Map<String, dynamic>>.from(result);
  }

  // ── Streaming download (constant memory) ─────────────────────────────────

  /// Download a file to a temporary path on disk, reporting byte-level
  /// progress. Never loads the full payload into RAM.
  static Future<File> downloadToFile({
    required String storagePath,
    required String fileName,
    required void Function(int received, int total) onProgress,
  }) async {
    final url = await SupabaseConfig.client.storage
        .from('transfers')
        .createSignedUrl(storagePath, 3600);

    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();
      final totalBytes = response.contentLength;
      var receivedBytes = 0;

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${sanitizeFileName(fileName)}');
      final sink = file.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress(receivedBytes, totalBytes);
      }

      await sink.close();
      return file;
    } finally {
      httpClient.close();
    }
  }

  /// Verify a downloaded file's SHA-256 against the stored hash.
  static Future<bool> verifySha256(File file, String? expectedHash) async {
    if (expectedHash == null || expectedHash.isEmpty) return true;
    final actualHash = await computeSha256(file);
    return actualHash == expectedHash;
  }

  /// Convenience: get a signed URL for browser/external download.
  static Future<String> getDownloadUrl(String storagePath) async {
    return await SupabaseConfig.client.storage
        .from('transfers')
        .createSignedUrl(storagePath, 3600);
  }

  // ── Supabase Realtime ────────────────────────────────────────────────────

  /// Subscribe to new incoming transfers via Postgres CDC.
  /// Returns the channel (caller must [unsubscribe] in dispose).
  static RealtimeChannel? subscribeToIncoming({
    required String userId,
    required void Function(Map<String, dynamic> newRecord) onNewTransfer,
  }) {
    try {
      final channel = SupabaseConfig.client.channel('incoming-$userId');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'transfers',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'receiver_id',
          value: userId,
        ),
        callback: (PostgresChangePayload payload) {
          onNewTransfer(payload.newRecord);
        },
      );
      channel.subscribe();
      return channel;
    } catch (_) {
      return null;
    }
  }

  static Future<void> unsubscribe(RealtimeChannel channel) async {
    await SupabaseConfig.client.removeChannel(channel);
  }
}
