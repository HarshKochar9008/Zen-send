import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide UserIdentity;
import 'package:url_launcher/url_launcher.dart';

import '../identity/identity_service.dart';
import '../transfer/transfer_service.dart';
import 'save_file.dart';

// ── Main screen ──────────────────────────────────────────────────────────────

class ReceiveScreen extends StatefulWidget {
  final UserIdentity identity;
  const ReceiveScreen({super.key, required this.identity});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  List<Map<String, dynamic>>? _transfers;
  bool _loading = true;
  String? _error;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadTransfers();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    if (_channel != null) TransferService.unsubscribe(_channel!);
    super.dispose();
  }

  void _subscribeToRealtime() {
    _channel = TransferService.subscribeToIncoming(
      userId: widget.identity.id,
      onNewTransfer: (_) {
        _loadTransfers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('New file transfer received!'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Color(0xFF6C63FF),
              duration: Duration(seconds: 3),
            ),
          );
        }
      },
    );
  }

  Future<void> _loadTransfers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final transfers =
          await TransferService.getIncomingTransfers(widget.identity.id);
      if (mounted) {
        setState(() {
          _transfers = transfers;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load transfers. Check your connection.';
          _loading = false;
        });
      }
    }
  }

  String _timeAgo(String isoDate) {
    final date = DateTime.parse(isoDate);
    final diff = DateTime.now().toUtc().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incoming Files'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadTransfers,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _loadTransfers,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _transfers == null || _transfers!.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _loadTransfers,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _transfers!.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final t = _transfers![index];
                          final senderCode =
                              (t['sender'] as Map?)?['short_code'] ?? '???';
                          final status =
                              (t['status'] ?? 'pending') as String;
                          final createdAt =
                              (t['created_at'] ?? '') as String;
                          return _TransferCard(
                            senderCode: senderCode,
                            status: status,
                            timeAgo: _timeAgo(createdAt),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _TransferDetailScreen(
                                  transferId: t['id'] as String,
                                  senderCode: senderCode,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_rounded, size: 64, color: Colors.white12),
          const SizedBox(height: 16),
          const Text(
            'No files received yet',
            style: TextStyle(color: Colors.white38),
          ),
          const SizedBox(height: 4),
          const Text(
            'Share your code so others can send you files',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            _channel != null
                ? 'Real-time updates active'
                : 'Pull down to refresh',
            style: TextStyle(
              color: _channel != null
                  ? const Color(0xFF4CAF50)
                  : Colors.white24,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transfer card ────────────────────────────────────────────────────────────

class _TransferCard extends StatelessWidget {
  final String senderCode;
  final String status;
  final String timeAgo;
  final VoidCallback onTap;

  const _TransferCard({
    required this.senderCode,
    required this.status,
    required this.timeAgo,
    required this.onTap,
  });

  Color _statusColor() {
    switch (status) {
      case 'completed':
        return const Color(0xFF4CAF50);
      case 'uploading':
      case 'pending':
        return const Color(0xFFFFA726);
      case 'partial':
        return const Color(0xFFFF7043);
      case 'expired':
        return Colors.white24;
      default:
        return Colors.white38;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A24),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF3F8CFF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.person_rounded,
                color: Color(0xFF3F8CFF),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'From $senderCode',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _statusColor(),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeAgo,
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white24,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Transfer detail screen ───────────────────────────────────────────────────

enum _DownloadStatus { idle, downloading, verifying, saving, completed, failed }

class _FileDownloadState {
  final _DownloadStatus status;
  final double progress;
  final String? savedLocation;
  final bool? hashVerified;
  final String? error;

  const _FileDownloadState({
    this.status = _DownloadStatus.idle,
    this.progress = 0,
    this.savedLocation,
    this.hashVerified,
    this.error,
  });
}

class _TransferDetailScreen extends StatefulWidget {
  final String transferId;
  final String senderCode;

  const _TransferDetailScreen({
    required this.transferId,
    required this.senderCode,
  });

  @override
  State<_TransferDetailScreen> createState() => _TransferDetailScreenState();
}

class _TransferDetailScreenState extends State<_TransferDetailScreen> {
  List<Map<String, dynamic>>? _files;
  bool _loading = true;
  final Map<String, _FileDownloadState> _dlStates = {};

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    try {
      final files =
          await TransferService.getTransferFiles(widget.transferId);
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatSize(dynamic bytes) {
    final b = (bytes is int) ? bytes : int.tryParse(bytes.toString()) ?? 0;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _downloadFile(Map<String, dynamic> file) async {
    final fileId = file['id'] as String;
    final storagePath = file['storage_path'] as String;
    final fileName = file['file_name'] as String;
    final expectedHash = file['sha256_hash'] as String?;

    setState(() => _dlStates[fileId] = const _FileDownloadState(
      status: _DownloadStatus.downloading,
    ));

    try {
      // ── Stream download to disk ──────────────────────────────────────
      late final File downloadedFile;

      if (kIsWeb) {
        final url = await TransferService.getDownloadUrl(storagePath);
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        setState(() => _dlStates[fileId] = const _FileDownloadState(
          status: _DownloadStatus.completed,
        ));
        return;
      }

      downloadedFile = await TransferService.downloadToFile(
        storagePath: storagePath,
        fileName: fileName,
        onProgress: (received, total) {
          if (mounted) {
            setState(() => _dlStates[fileId] = _FileDownloadState(
              status: _DownloadStatus.downloading,
              progress: total > 0 ? received / total : 0,
            ));
          }
        },
      );

      // ── Verify SHA-256 ───────────────────────────────────────────────
      setState(() => _dlStates[fileId] = const _FileDownloadState(
        status: _DownloadStatus.verifying,
        progress: 1.0,
      ));

      bool? hashVerified;
      if (expectedHash != null && expectedHash.isNotEmpty) {
        hashVerified = await TransferService.verifySha256(
          downloadedFile,
          expectedHash,
        );
        if (hashVerified == false) {
          setState(() => _dlStates[fileId] = const _FileDownloadState(
            status: _DownloadStatus.failed,
            error: 'Integrity check failed — file may be corrupted',
            hashVerified: false,
          ));
          return;
        }
      }

      // ── Save to device ───────────────────────────────────────────────
      setState(() => _dlStates[fileId] = _FileDownloadState(
        status: _DownloadStatus.saving,
        progress: 1.0,
        hashVerified: hashVerified,
      ));

      final location = await saveFileToDevice(downloadedFile, fileName);

      setState(() => _dlStates[fileId] = _FileDownloadState(
        status: _DownloadStatus.completed,
        progress: 1.0,
        hashVerified: hashVerified,
        savedLocation: location,
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved to $location'
              '${hashVerified == true ? '  (verified)' : ''}',
            ),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } on PermissionDeniedException catch (e) {
      if (mounted) {
        setState(() => _dlStates[fileId] = _FileDownloadState(
          status: _DownloadStatus.failed,
          error: e.message,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _dlStates[fileId] = _FileDownloadState(
          status: _DownloadStatus.failed,
          error: 'Download failed: ${e.toString().replaceAll('Exception: ', '')}',
        ));
      }
    }
  }

  Future<void> _downloadAll() async {
    if (_files == null || _files!.isEmpty) return;
    for (final file in _files!) {
      final fileId = file['id'] as String;
      final state = _dlStates[fileId];
      if (state == null || state.status != _DownloadStatus.completed) {
        await _downloadFile(file);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allCompleted = _files != null &&
        _files!.isNotEmpty &&
        _files!.every((f) =>
            _dlStates[f['id']]?.status == _DownloadStatus.completed);

    return Scaffold(
      appBar: AppBar(
        title: Text('From ${widget.senderCode}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_files != null && _files!.isNotEmpty && !allCompleted)
            TextButton.icon(
              onPressed: _downloadAll,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('All'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files == null || _files!.isEmpty
              ? const Center(
                  child: Text(
                    'No files in this transfer',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _files!.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final file = _files![index];
                    final fileId = file['id'] as String;
                    final dlState = _dlStates[fileId];

                    return _FileDownloadTile(
                      fileName: file['file_name'] as String,
                      fileSize: _formatSize(file['file_size']),
                      state: dlState,
                      onDownload: () => _downloadFile(file),
                    );
                  },
                ),
    );
  }
}

// ── File download tile ───────────────────────────────────────────────────────

class _FileDownloadTile extends StatelessWidget {
  final String fileName;
  final String fileSize;
  final _FileDownloadState? state;
  final VoidCallback onDownload;

  const _FileDownloadTile({
    required this.fileName,
    required this.fileSize,
    required this.state,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final status = state?.status ?? _DownloadStatus.idle;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A24),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _fileIcon(status),
                color: _iconColor(status),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      fileSize,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildTrailing(status),
            ],
          ),

          // ── Progress bar ───────────────────────────────────────────
          if (status == _DownloadStatus.downloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: state!.progress,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(
                  Color(0xFF3F8CFF),
                ),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Downloading… ${(state!.progress * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
              ),
            ),
          ],

          if (status == _DownloadStatus.verifying) ...[
            const SizedBox(height: 6),
            const Text(
              'Verifying file integrity (SHA-256)…',
              style: TextStyle(
                color: Color(0xFF3F8CFF),
                fontSize: 11,
              ),
            ),
          ],

          if (status == _DownloadStatus.saving) ...[
            const SizedBox(height: 6),
            const Text(
              'Saving to device…',
              style: TextStyle(
                color: Color(0xFFFFA726),
                fontSize: 11,
              ),
            ),
          ],

          // ── Completed info ─────────────────────────────────────────
          if (status == _DownloadStatus.completed) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (state?.hashVerified == true) ...[
                  const Icon(
                    Icons.verified_rounded,
                    color: Color(0xFF4CAF50),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'SHA-256 verified',
                    style: TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 11,
                    ),
                  ),
                ] else ...[
                  const Icon(
                    Icons.check_circle_outline,
                    color: Colors.white38,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Saved',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ],
            ),
            if (state?.savedLocation != null) ...[
              const SizedBox(height: 2),
              Text(
                state!.savedLocation!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 10,
                ),
              ),
            ],
          ],

          // ── Error ──────────────────────────────────────────────────
          if (status == _DownloadStatus.failed &&
              state?.error != null) ...[
            const SizedBox(height: 6),
            Text(
              state!.error!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _fileIcon(_DownloadStatus status) {
    switch (status) {
      case _DownloadStatus.completed:
        return Icons.check_circle_rounded;
      case _DownloadStatus.failed:
        return Icons.error_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _iconColor(_DownloadStatus status) {
    switch (status) {
      case _DownloadStatus.completed:
        return const Color(0xFF4CAF50);
      case _DownloadStatus.failed:
        return Colors.redAccent;
      default:
        return const Color(0xFF3F8CFF);
    }
  }

  Widget _buildTrailing(_DownloadStatus status) {
    switch (status) {
      case _DownloadStatus.idle:
      case _DownloadStatus.failed:
        return IconButton(
          onPressed: onDownload,
          icon: const Icon(
            Icons.download_rounded,
            color: Color(0xFF3F8CFF),
          ),
        );
      case _DownloadStatus.downloading:
      case _DownloadStatus.verifying:
      case _DownloadStatus.saving:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _DownloadStatus.completed:
        return const Icon(
          Icons.check_rounded,
          color: Color(0xFF4CAF50),
          size: 22,
        );
    }
  }
}
