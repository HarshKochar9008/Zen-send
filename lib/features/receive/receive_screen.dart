import 'package:flutter/material.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../transfer/transfer_service.dart';
import 'save_file.dart';

class ReceiveScreen extends StatefulWidget {
  final String transferId;
  final String senderCode;

  const ReceiveScreen({
    super.key,
    required this.transferId,
    required this.senderCode,
  });

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  static const _downloadedKeysPrefix = 'downloaded_files_';
  List<Map<String, dynamic>>? _files;
  bool _loading = true;
  String? _loadError;
  final Map<String, _FileDownloadState> _dlStates = {};
  final Map<String, TransferCancellationToken> _downloadTokens = {};
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

    final rawSize = file['file_size'];
    final fileSize = rawSize is int ? rawSize : int.tryParse('$rawSize') ?? 0;
    final freeSpaceGb = await DiskSpacePlus().getFreeDiskSpace ?? 0.0;
    final freeSpaceBytes = (freeSpaceGb * 1024 * 1024 * 1024).toInt();
    if (fileSize > 0 && freeSpaceBytes > 0 && freeSpaceBytes < fileSize) {
      if (mounted) {
        setState(() => _dlStates[fileId] = const _FileDownloadState(
              status: _DownloadStatus.failed,
              error: 'Not enough free device storage for this file',
            ));
      }
      return;
    }

    final cancellationToken = TransferCancellationToken();
    _downloadTokens[fileId] = cancellationToken;
    setState(() => _dlStates[fileId] = const _FileDownloadState(
          status: _DownloadStatus.downloading,
        ));

    try {
      final downloadedFile = await TransferService.downloadToFile(
        storagePath: storagePath,
        fileName: fileName,
        cancellationToken: cancellationToken,
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
            backgroundColor: AppColors.snackBarBg,
          ),
        );
      }
    } on TransferCancelledException catch (_) {
      if (mounted) {
        setState(() => _dlStates[fileId] = const _FileDownloadState(
              status: _DownloadStatus.failed,
              error: 'Download cancelled',
            ));
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
    } finally {
      _downloadTokens.remove(fileId);
    }
  }

  void _cancelDownload(String fileId) {
    _downloadTokens[fileId]?.cancel();
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
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.onSurfaceVariant, size: 22),
                  ),
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset('assets/logo.png',
                        width: 32, height: 32),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'From ${widget.senderCode}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (_files != null &&
                      _files!.isNotEmpty &&
                      !allCompleted)
                    TextButton.icon(
                      onPressed: _downloadAll,
                      icon:
                          const Icon(Icons.download_rounded, size: 16),
                      label: const Text('All'),
                    ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _loading
                  ? Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                              AppColors.primary.withValues(alpha: 0.6),
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
                                  color: AppColors.onSurfaceVariant
                                      .withValues(alpha: 0.5),
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(20),
                              itemCount: _files!.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final file = _files![index];
                                final fileId = file['id'] as String;
                                final dlState = _dlStates[fileId];

                                return _FileDownloadTile(
                                  fileName:
                                      file['file_name'] as String,
                                  fileSize:
                                      _formatSize(file['file_size']),
                                  state: dlState,
                                  onDownload: () =>
                                      _downloadFile(file),
                                  onCancel: () => _cancelDownload(fileId),
                                );
                              },
                            ),
            ),
          ],
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

class _FileDownloadTile extends StatelessWidget {
  final String fileName;
  final String fileSize;
  final _FileDownloadState? state;
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  const _FileDownloadTile({
    required this.fileName,
    required this.fileSize,
    required this.state,
    required this.onDownload,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final status = state?.status ?? _DownloadStatus.idle;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_fileIcon(status),
                    color: _iconColor(status), size: 20),
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
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fileSize,
                      style: TextStyle(
                        color: AppColors.onSurfaceVariant
                            .withValues(alpha: 0.4),
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
                backgroundColor:
                    AppColors.outlineVariant.withValues(alpha: 0.15),
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.primary),
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Downloading… ${(state!.progress * 100).toInt()}%',
              style: TextStyle(
                color:
                    AppColors.onSurfaceVariant.withValues(alpha: 0.4),
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
                      color: AppColors.success.withValues(alpha: 0.7),
                      size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'SHA-256 verified',
                    style: TextStyle(
                      color:
                          AppColors.success.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ] else ...[
                  Icon(Icons.check_circle_outline,
                      color: AppColors.onSurfaceVariant
                          .withValues(alpha: 0.4),
                      size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'Saved',
                    style: TextStyle(
                      color: AppColors.onSurfaceVariant
                          .withValues(alpha: 0.4),
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
                  color: AppColors.outlineVariant
                      .withValues(alpha: 0.5),
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
              style: const TextStyle(
                  color: AppColors.error, fontSize: 11),
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
        return GestureDetector(
          onTap: onDownload,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.download_rounded,
                color: AppColors.primary, size: 20),
          ),
        );
      case _DownloadStatus.downloading:
        return GestureDetector(
          onTap: onCancel,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.close_rounded,
                color: AppColors.error, size: 18),
          ),
        );
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
