import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../identity/identity_service.dart';
import '../transfer/transfer_service.dart';

class SendScreen extends StatefulWidget {
  final UserIdentity identity;
  const SendScreen({super.key, required this.identity});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _codeController = TextEditingController();
  List<PlatformFile> _selectedFiles = [];
  List<FileUploadProgress>? _uploadStates;
  bool _validatingCode = false;
  bool _sending = false;
  String? _error;
  String? _codeError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<bool> _hasConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return !result.contains(ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
      );
      if (result == null || !mounted) return;

      final accessibleRaw =
          result.files.where((f) => f.path != null).toList();
      final seenNames = <String>{};
      final accessible = <PlatformFile>[];
      for (final f in accessibleRaw) {
        if (seenNames.add(f.name)) accessible.add(f);
      }

      final oversized = accessible
          .where((f) => f.size > AppConstants.maxFileSizeBytes)
          .toList();
      if (oversized.isNotEmpty) {
        setState(() {
          _error =
              '${oversized.first.name} exceeds '
              '${AppConstants.maxFileSizeBytes ~/ 1024 ~/ 1024} MB limit';
        });
        return;
      }

      final existingNames = _selectedFiles.map((f) => f.name).toSet();
      final duplicates =
          accessible.where((f) => existingNames.contains(f.name)).toList();
      final newFiles =
          accessible.where((f) => !existingNames.contains(f.name)).toList();

      if (newFiles.isEmpty && duplicates.isNotEmpty) {
        _showDuplicateAlert(duplicates.map((f) => f.name).toList());
        return;
      }

      final totalCount = _selectedFiles.length + newFiles.length;
      if (totalCount > AppConstants.maxFilesPerTransfer) {
        setState(() {
          _error =
              'Max ${AppConstants.maxFilesPerTransfer} files per transfer';
        });
        return;
      }

      setState(() {
        _selectedFiles = [..._selectedFiles, ...newFiles];
        _error = null;
      });

      if (duplicates.isNotEmpty) {
        _showDuplicateAlert(duplicates.map((f) => f.name).toList());
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Could not pick files. Check app permissions.',
        );
      }
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles = List.from(_selectedFiles)..removeAt(index);
    });
  }

  void _showDuplicateAlert(List<String> fileNames) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.dialogBg,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.file_copy_rounded,
                color: AppColors.warning, size: 20),
            const SizedBox(width: 10),
            const Text(
              'Duplicate Files',
              style: TextStyle(color: AppColors.onSurface, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileNames.length == 1
                  ? 'This file has already been added:'
                  : 'These files have already been added:',
              style: TextStyle(
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...fileNames.map(
              (name) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file_rounded,
                        color: AppColors.outlineVariant, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                            color: AppColors.onSurfaceVariant, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _codeError = 'Enter a recipient code');
      return;
    }
    if (code == widget.identity.shortCode) {
      setState(() => _codeError = 'You cannot send files to yourself');
      return;
    }
    if (_selectedFiles.isEmpty) {
      setState(() => _error = 'Pick at least one file');
      return;
    }

    if (!await _hasConnectivity()) {
      setState(() => _error = 'No internet connection. Please try again.');
      return;
    }

    setState(() {
      _validatingCode = true;
      _codeError = null;
      _error = null;
    });

    Map<String, dynamic>? recipient;
    try {
      recipient = await IdentityService.findUserByCode(code);
    } catch (e) {
      if (mounted) {
        setState(() {
          _codeError = 'Could not validate code. Check your connection.';
          _validatingCode = false;
        });
      }
      return;
    }

    if (recipient == null) {
      if (mounted) {
        setState(() {
          _codeError = 'No user found with code "$code"';
          _validatingCode = false;
        });
      }
      return;
    }

    setState(() {
      _validatingCode = false;
      _sending = true;
      _uploadStates = null;
    });

    try {
      final result = await TransferService.sendFiles(
        senderId: widget.identity.id,
        receiverId: recipient['id'] as String,
        files: _selectedFiles,
        onProgress: (states) {
          if (mounted) setState(() => _uploadStates = states);
        },
      );

      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result.completedFiles} file(s) sent to $code'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        );
        Navigator.pop(context);
      } else {
        setState(() {
          _error =
              '${result.completedFiles}/${result.totalFiles} files sent. '
              'Some failed — see details above.';
          _sending = false;
        });
      }
    } on FileTooLargeException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _sending = false;
        });
      }
    } on TooManyFilesException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _sending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'Transfer failed: '
              '${e.toString().replaceAll('Exception: ', '')}';
          _sending = false;
        });
      }
    }
  }

  String _formatSize(int bytes) {
    return TransferService.formatFileSize(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send Files')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Recipient code
            Text(
              'Recipient Code',
              style: TextStyle(
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _codeController,
              enabled: !_sending,
              textCapitalization: TextCapitalization.characters,
              maxLength: AppConstants.codeLength,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: AppColors.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'ABC123',
                hintStyle: TextStyle(
                  color: AppColors.outlineVariant.withValues(alpha: 0.4),
                  fontSize: 24,
                  letterSpacing: 8,
                  fontFamily: 'monospace',
                ),
                counterText: '',
                filled: true,
                fillColor: AppColors.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                errorText: _codeError,
                errorStyle: const TextStyle(fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Files header
            Row(
              children: [
                Text(
                  'Files',
                  style: TextStyle(
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (!_sending)
                  TextButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(
                      _selectedFiles.isEmpty ? 'Pick Files' : 'Add More',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // ── File list / progress view
            Expanded(
              child: _sending && _uploadStates != null
                  ? _UploadProgressList(states: _uploadStates!)
                  : _selectedFiles.isEmpty
                      ? _EmptyFilesView(onPick: _pickFiles)
                      : ListView.separated(
                          itemCount: _selectedFiles.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final file = _selectedFiles[index];
                            return _FileTile(
                              name: file.name,
                              size: _formatSize(file.size),
                              onRemove: _sending
                                  ? null
                                  : () => _removeFile(index),
                            );
                          },
                        ),
            ),

            // ── Error
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],

            const SizedBox(height: 16),

            // ── Send button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: (_sending || _validatingCode)
                      ? null
                      : const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryContainer],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                  color: (_sending || _validatingCode)
                      ? AppColors.surfaceContainerHigh
                      : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FilledButton(
                  onPressed: (_sending || _validatingCode) ? null : _send,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _sending
                      ? _buildSendingLabel()
                      : _validatingCode
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onSurfaceVariant,
                              ),
                            )
                          : const Text(
                              'Send',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onPrimary,
                              ),
                            ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendingLabel() {
    final states = _uploadStates;
    if (states == null) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.onSurfaceVariant,
        ),
      );
    }
    final done =
        states.where((s) => s.status == FileUploadStatus.completed).length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Sending $done / ${states.length}',
          style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
  }
}

class _UploadProgressList extends StatelessWidget {
  final List<FileUploadProgress> states;
  const _UploadProgressList({required this.states});

  @override
  Widget build(BuildContext context) {
    final completed =
        states.where((s) => s.status == FileUploadStatus.completed).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$completed / ${states.length} uploaded',
                style: TextStyle(
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: states.isNotEmpty ? completed / states.length : 0,
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: states.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                _FileProgressTile(state: states[index]),
          ),
        ),
      ],
    );
  }
}

class _FileProgressTile extends StatelessWidget {
  final FileUploadProgress state;
  const _FileProgressTile({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusIcon(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.onSurface),
                ),
              ),
              Text(
                _statusLabel(),
                style: TextStyle(
                  color: _statusColor(),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (state.status == FileUploadStatus.hashing ||
              state.status == FileUploadStatus.uploading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: state.progress,
                backgroundColor: AppColors.outlineVariant.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(_statusColor()),
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              state.status == FileUploadStatus.hashing
                  ? 'Verifying… ${(state.progress * 100).toInt()}%'
                  : 'Uploading… ${(state.progress * 100).toInt()}%'
                      '${state.attempt > 1 ? ' (retry ${state.attempt})' : ''}',
              style: TextStyle(
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ],
          if (state.status == FileUploadStatus.completed &&
              state.sha256 != null) ...[
            const SizedBox(height: 4),
            Text(
              'SHA-256: ${state.sha256!.substring(0, 16)}…',
              style: TextStyle(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (state.status == FileUploadStatus.failed &&
              state.error != null) ...[
            const SizedBox(height: 4),
            Text(
              state.error!,
              style: const TextStyle(color: AppColors.error, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusIcon() {
    switch (state.status) {
      case FileUploadStatus.pending:
        return Icon(Icons.schedule,
            color: AppColors.outlineVariant.withValues(alpha: 0.5), size: 18);
      case FileUploadStatus.hashing:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case FileUploadStatus.uploading:
        return const Icon(Icons.cloud_upload_rounded,
            color: AppColors.primary, size: 18);
      case FileUploadStatus.completed:
        return const Icon(Icons.check_circle_rounded,
            color: AppColors.success, size: 18);
      case FileUploadStatus.failed:
        return const Icon(Icons.error_rounded,
            color: AppColors.error, size: 18);
    }
  }

  String _statusLabel() {
    switch (state.status) {
      case FileUploadStatus.pending:
        return 'Queued';
      case FileUploadStatus.hashing:
        return 'Hashing';
      case FileUploadStatus.uploading:
        return 'Uploading';
      case FileUploadStatus.completed:
        return 'Sent';
      case FileUploadStatus.failed:
        return 'Failed';
    }
  }

  Color _statusColor() {
    switch (state.status) {
      case FileUploadStatus.pending:
        return AppColors.outlineVariant;
      case FileUploadStatus.hashing:
        return AppColors.primaryContainer;
      case FileUploadStatus.uploading:
        return AppColors.primary;
      case FileUploadStatus.completed:
        return AppColors.success;
      case FileUploadStatus.failed:
        return AppColors.error;
    }
  }
}

class _EmptyFilesView extends StatelessWidget {
  final VoidCallback onPick;
  const _EmptyFilesView({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.15),
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_upload_outlined,
                  size: 40,
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text(
                'Tap to select files',
                style: TextStyle(
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Images, videos, documents — any file type',
                style: TextStyle(
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.25),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  final String name;
  final String size;
  final VoidCallback? onRemove;

  const _FileTile({required this.name, required this.size, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file_rounded,
              color: AppColors.primary.withValues(alpha: 0.6), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.onSurface),
                ),
                Text(
                  size,
                  style: TextStyle(
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: Icon(Icons.close_rounded,
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  size: 18),
            ),
        ],
      ),
    );
  }
}
