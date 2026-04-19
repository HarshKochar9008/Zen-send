import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide UserIdentity;

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../identity/identity_service.dart';
import '../transfer/transfer_service.dart';
import 'save_file.dart';

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
  int _currentPage = 0;
  bool _hasMore = true;

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
      onNewTransfer: (record) {
        _loadTransfers();
        if (mounted) {
          final status = record['status'] as String? ?? 'pending';
          final msg = status == 'completed'
              ? 'Transfer ready — files available for download!'
              : 'New file transfer incoming…';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.surfaceContainerHigh,
              duration: const Duration(seconds: 3),
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
      _currentPage = 0;
    });
    try {
      final transfers = await TransferService.getIncomingTransfers(
        widget.identity.id,
        page: 0,
      );
      if (mounted) {
        setState(() {
          _transfers = transfers;
          _loading = false;
          _hasMore = transfers.length >= AppConstants.transfersPageSize;
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

  Future<void> _loadMore() async {
    if (!_hasMore) return;
    final nextPage = _currentPage + 1;
    try {
      final more = await TransferService.getIncomingTransfers(
        widget.identity.id,
        page: nextPage,
      );
      if (mounted) {
        setState(() {
          _transfers = [...?_transfers, ...more];
          _currentPage = nextPage;
          _hasMore = more.length >= AppConstants.transfersPageSize;
        });
      }
    } catch (_) {}
  }

  String _timeAgo(String isoDate) {
    final date = DateTime.tryParse(isoDate);
    if (date == null) return '';
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
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
            onPressed: _loadTransfers,
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary.withValues(alpha: 0.6),
                ),
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _loadTransfers,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _transfers == null || _transfers!.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _loadTransfers,
                      color: AppColors.primary,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(24),
                        itemCount: _transfers!.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          if (index == _transfers!.length) {
                            _loadMore();
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            );
                          }

                          final t = _transfers![index];
                          final senderCode =
                              (t['sender'] as Map?)?['short_code'] ?? '???';
                          final status =
                              (t['status'] ?? 'pending') as String;
                          final createdAt =
                              (t['created_at'] ?? '') as String;
                          final isExpired = status == 'expired';
                          return _TransferCard(
                            senderCode: senderCode,
                            status: status,
                            timeAgo: _timeAgo(createdAt),
                            isExpired: isExpired,
                            onTap: isExpired
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            _TransferDetailScreen(
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
          Icon(Icons.inbox_rounded,
              size: 48,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.15)),
          const SizedBox(height: 20),
          const Text(
            'No files received yet',
            style: TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Share your code so others can send you files',
            style: TextStyle(
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          if (_channel != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Real-time updates active',
                  style: TextStyle(
                    color: AppColors.success.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  final String senderCode;
  final String status;
  final String timeAgo;
  final bool isExpired;
  final VoidCallback? onTap;

  const _TransferCard({
    required this.senderCode,
    required this.status,
    required this.timeAgo,
    this.isExpired = false,
    this.onTap,
  });

  Color _statusColor() {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'uploading':
      case 'pending':
        return AppColors.warning;
      case 'partial':
        return AppColors.error;
      case 'expired':
        return AppColors.outlineVariant;
      case 'failed':
        return AppColors.error;
      default:
        return AppColors.outlineVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isExpired ? 0.45 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isExpired
                      ? Icons.timer_off_rounded
                      : Icons.person_rounded,
                  color: isExpired
                      ? AppColors.outlineVariant
                      : AppColors.primaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'From $senderCode',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.onSurface,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _statusColor(),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isExpired ? 'Expired' : status,
                          style: TextStyle(
                            color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeAgo,
                          style: TextStyle(
                            color: AppColors.onSurfaceVariant.withValues(alpha: 0.3),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isExpired)
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DownloadStatus {
  idle,
  downloading,
  verifying,
  saving,
  completed,
  failed,
}

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
  static const _downloadedKeysPrefix = 'downloaded_files_';
  List<Map<String, dynamic>>? _files;
  bool _loading = true;
  String? _loadError;
  final Map<String, _FileDownloadState> _dlStates = {};
  Set<String> _persistedDownloads = {};

  @override
  void initState() {
    super.initState();
    _loadPersistedState();
    _loadFiles();
  }

  Future<void> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(
      '$_downloadedKeysPrefix${widget.transferId}',
    );
    if (saved != null && mounted) {
      setState(() {
        _persistedDownloads = saved.toSet();
        for (final fileId in _persistedDownloads) {
          _dlStates[fileId] = const _FileDownloadState(
            status: _DownloadStatus.completed,
            progress: 1.0,
          );
        }
      });
    }
  }

  Future<void> _markDownloaded(String fileId) async {
    _persistedDownloads.add(fileId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      '$_downloadedKeysPrefix${widget.transferId}',
      _persistedDownloads.toList(),
    );
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final files =
          await TransferService.getTransferFiles(widget.transferId);
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError =
              'Could not load files: ${e.toString().replaceAll('Exception: ', '')}';
          _loading = false;
        });
      }
    }
  }

  String _formatSize(dynamic bytes) {
    final b = (bytes is int) ? bytes : int.tryParse(bytes.toString()) ?? 0;
    return TransferService.formatFileSize(b);
  }

  Future<void> _downloadFile(Map<String, dynamic> file) async {
    final fileId = file['id'] as String;
    final storagePath = file['storage_path'] as String;
    final fileName = file['file_name'] as String;
    final expectedHash = file['sha256_hash'] as String?;

    if (_persistedDownloads.contains(fileId)) return;
    final existingState = _dlStates[fileId];
    if (existingState?.status == _DownloadStatus.completed) return;

    setState(() => _dlStates[fileId] = const _FileDownloadState(
          status: _DownloadStatus.downloading,
        ));

    try {
      final downloadedFile = await TransferService.downloadToFile(
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

      if (mounted) {
        setState(() => _dlStates[fileId] = const _FileDownloadState(
              status: _DownloadStatus.verifying,
              progress: 1.0,
            ));
      }

      bool? hashVerified;
      if (expectedHash != null && expectedHash.isNotEmpty) {
        hashVerified = await TransferService.verifySha256(
          downloadedFile,
          expectedHash,
        );
        if (hashVerified == false) {
          if (mounted) {
            setState(() => _dlStates[fileId] = const _FileDownloadState(
                  status: _DownloadStatus.failed,
                  error: 'Integrity check failed — file may be corrupted',
                  hashVerified: false,
                ));
          }
          return;
        }
      }

      if (mounted) {
        setState(() => _dlStates[fileId] = _FileDownloadState(
              status: _DownloadStatus.saving,
              progress: 1.0,
              hashVerified: hashVerified,
            ));
      }

      final location = await saveFileToDevice(downloadedFile, fileName);

      await _markDownloaded(fileId);

      if (mounted) {
        setState(() => _dlStates[fileId] = _FileDownloadState(
              status: _DownloadStatus.completed,
              progress: 1.0,
              hashVerified: hashVerified,
              savedLocation: location,
            ));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved to $location'
              '${hashVerified == true ? '  (verified)' : ''}',
            ),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.surfaceContainerHigh,
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
              error:
                  'Download failed: ${e.toString().replaceAll('Exception: ', '')}',
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
        actions: [
          if (_files != null && _files!.isNotEmpty && !allCompleted)
            TextButton.icon(
              onPressed: _downloadAll,
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('All'),
            ),
        ],
      ),
      body: _loading
          ? Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary.withValues(alpha: 0.6),
                ),
              ),
            )
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _loadFiles,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _files == null || _files!.isEmpty
                  ? Center(
                      child: Text(
                        'No files in this transfer',
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(24),
                      itemCount: _files!.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_fileIcon(status), color: _iconColor(status), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      fileSize,
                      style: TextStyle(
                        color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildTrailing(status),
            ],
          ),

          if (status == _DownloadStatus.downloading) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: state!.progress,
                backgroundColor: AppColors.outlineVariant.withValues(alpha: 0.15),
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.primary),
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Downloading… ${(state!.progress * 100).toInt()}%',
              style: TextStyle(
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ],

          if (status == _DownloadStatus.verifying) ...[
            const SizedBox(height: 8),
            Text(
              'Verifying integrity…',
              style: TextStyle(
                color: AppColors.primary.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ],

          if (status == _DownloadStatus.saving) ...[
            const SizedBox(height: 8),
            Text(
              'Saving to device…',
              style: TextStyle(
                color: AppColors.warning.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],

          if (status == _DownloadStatus.completed) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (state?.hashVerified == true) ...[
                  Icon(Icons.verified_rounded,
                      color: AppColors.success.withValues(alpha: 0.7), size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'SHA-256 verified',
                    style: TextStyle(
                      color: AppColors.success.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ] else ...[
                  Icon(Icons.check_circle_outline,
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                      size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'Saved',
                    style: TextStyle(
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
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
                style: TextStyle(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  fontSize: 10,
                ),
              ),
            ],
          ],

          if (status == _DownloadStatus.failed &&
              state?.error != null) ...[
            const SizedBox(height: 8),
            Text(
              state!.error!,
              style: const TextStyle(color: AppColors.error, fontSize: 11),
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
        return AppColors.success;
      case _DownloadStatus.failed:
        return AppColors.error;
      default:
        return AppColors.primary.withValues(alpha: 0.6);
    }
  }

  Widget _buildTrailing(_DownloadStatus status) {
    switch (status) {
      case _DownloadStatus.idle:
      case _DownloadStatus.failed:
        return IconButton(
          onPressed: onDownload,
          icon: const Icon(Icons.download_rounded,
              color: AppColors.primary, size: 20),
        );
      case _DownloadStatus.downloading:
      case _DownloadStatus.verifying:
      case _DownloadStatus.saving:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary.withValues(alpha: 0.6),
          ),
        );
      case _DownloadStatus.completed:
        return Icon(Icons.check_rounded,
            color: AppColors.success.withValues(alpha: 0.7), size: 20);
    }
  }
}
