import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';

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
  bool _codeValidated = false;
  bool _sending = false;
  String? _error;
  String? _codeError;
  String? _validatedRecipientId;
  TransferCancellationToken? _uploadCancellationToken;

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

  void _clearAll() {
    setState(() {
      _selectedFiles = [];
    });
  }

  void _showDuplicateAlert(List<String> fileNames) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
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

  Future<void> _validateCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _codeError = 'Enter a recipient code');
      return;
    }
    if (code == widget.identity.shortCode) {
      setState(() => _codeError = 'You cannot send files to yourself');
      return;
    }

    if (!await _hasConnectivity()) {
      setState(() => _codeError = 'No internet connection');
      return;
    }

    setState(() {
      _validatingCode = true;
      _codeError = null;
    });

    try {
      final recipient = await IdentityService.findUserByCode(code);
      if (!mounted) return;

      if (recipient == null) {
        setState(() {
          _codeError = 'No user found with code "$code"';
          _validatingCode = false;
        });
        return;
      }

      setState(() {
        _validatingCode = false;
        _codeValidated = true;
        _validatedRecipientId = recipient['id'] as String;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _codeError = 'Could not validate code. Check your connection.';
          _validatingCode = false;
        });
      }
    }
  }

  Future<void> _send() async {
    if (_validatedRecipientId == null || _selectedFiles.isEmpty) return;

    setState(() {
      _sending = true;
      _uploadStates = null;
      _error = null;
      _uploadCancellationToken = TransferCancellationToken();
    });

    try {
      final result = await TransferService.sendFiles(
        senderId: widget.identity.id,
        receiverId: _validatedRecipientId!,
        files: _selectedFiles,
        cancellationToken: _uploadCancellationToken,
        onProgress: (states) {
          if (mounted) setState(() => _uploadStates = states);
        },
      );

      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${result.completedFiles} file(s) sent successfully'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.snackBarBg,
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
    } on TransferCancelledException catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Transfer cancelled';
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
    } finally {
      _uploadCancellationToken = null;
    }
  }

  void _cancelUpload() {
    _uploadCancellationToken?.cancel();
  }

  String _formatSize(int bytes) {
    return TransferService.formatFileSize(bytes);
  }

  int get _totalSize =>
      _selectedFiles.fold<int>(0, (sum, f) => sum + f.size);

  String _mimeCategory(String fileName) {
    final mime = lookupMimeType(fileName) ?? '';
    if (mime.startsWith('image/')) return 'Image';
    if (mime.startsWith('video/')) return 'Video';
    if (mime.startsWith('audio/')) return 'Audio';
    if (mime.contains('pdf')) return 'PDF';
    if (mime.contains('zip') || mime.contains('tar') || mime.contains('rar')) {
      return 'Archive';
    }
    if (mime.contains('document') ||
        mime.contains('word') ||
        mime.contains('text/')) {
      return 'Document';
    }
    return 'File';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                  const Text(
                    'ZenSend',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.settings_rounded,
                        color: AppColors.onSurfaceVariant, size: 22),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text(
                      'Ready to Send',
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Enter the recipient's secure short-code to begin the encrypted handshake.",
                      style: TextStyle(
                        color:
                            AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Recipient code input card
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _codeController,
                              enabled: !_sending && !_codeValidated,
                              textCapitalization:
                                  TextCapitalization.characters,
                              maxLength: AppConstants.codeLength,
                              style: const TextStyle(
                                fontSize: 16,
                                letterSpacing: 4,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'monospace',
                                color: AppColors.cardText,
                              ),
                              decoration: InputDecoration(
                                hintText: 'RECIPIENT SHORTCODE',
                                hintStyle: TextStyle(
                                  color: AppColors.cardTextSecondary
                                      .withValues(alpha: 0.5),
                                  fontSize: 13,
                                  letterSpacing: 1,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                ),
                                counterText: '',
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                              onChanged: (_) {
                                if (_codeValidated) {
                                  setState(() {
                                    _codeValidated = false;
                                    _validatedRecipientId = null;
                                  });
                                }
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: SizedBox(
                              height: 40,
                              child: FilledButton(
                                onPressed: (_validatingCode ||
                                        _sending ||
                                        _codeValidated)
                                    ? null
                                    : _validateCode,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _codeValidated
                                      ? AppColors.success
                                      : AppColors.primary,
                                  disabledBackgroundColor: _codeValidated
                                      ? AppColors.success
                                      : AppColors.primary
                                          .withValues(alpha: 0.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  textStyle: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                child: _validatingCode
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _codeValidated
                                            ? 'Verified'
                                            : 'Validate',
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_codeError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _codeError!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 12),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // Selected files section
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Selected Files',
                              style: TextStyle(
                                color: AppColors.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_selectedFiles.isNotEmpty)
                              Text(
                                '${_selectedFiles.length} files, ${_formatSize(_totalSize)}',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                        const Spacer(),
                        if (!_sending && _selectedFiles.isNotEmpty) ...[
                          TextButton(
                            onPressed: _pickFiles,
                            child: const Text('Add More'),
                          ),
                          TextButton(
                            onPressed: _clearAll,
                            child: Text(
                              'Clear All',
                              style: TextStyle(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // File list or upload progress
                    if (_sending && _uploadStates != null)
                      _UploadProgressList(states: _uploadStates!)
                    else if (_selectedFiles.isEmpty)
                      _EmptyFilesView(onPick: _pickFiles)
                    else
                      ...List.generate(_selectedFiles.length, (index) {
                        final file = _selectedFiles[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _FileTile(
                            name: file.name,
                            size: _formatSize(file.size),
                            mimeType: _mimeCategory(file.name),
                            onRemove:
                                _sending ? null : () => _removeFile(index),
                          ),
                        );
                      }),

                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 12),
                      ),
                    ],

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Send button
            if (_codeValidated && _selectedFiles.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: _sending
                          ? null
                          : const LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primaryContainer
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                      color: _sending
                          ? AppColors.outlineVariant
                          : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: FilledButton(
                      onPressed: _sending ? null : _send,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _sending
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildSendingLabel(),
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: _cancelUpload,
                                  child: const Icon(
                                    Icons.close_rounded,
                                    color: AppColors.onSurfaceVariant,
                                    size: 18,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'Send',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
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
          style: const TextStyle(
              color: AppColors.onSurfaceVariant, fontSize: 13),
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
        ...states.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FileProgressTile(state: s),
            )),
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
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.6)),
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
                backgroundColor:
                    AppColors.outlineVariant.withValues(alpha: 0.15),
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
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.cardBorder,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_upload_outlined,
                  size: 40,
                  color:
                      AppColors.onSurfaceVariant.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text(
                'Tap to select files',
                style: TextStyle(
                  color:
                      AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Images, videos, documents — any file type',
                style: TextStyle(
                  color:
                      AppColors.onSurfaceVariant.withValues(alpha: 0.25),
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
  final String mimeType;
  final VoidCallback? onRemove;

  const _FileTile({
    required this.name,
    required this.size,
    required this.mimeType,
    this.onRemove,
  });

  IconData get _typeIcon {
    switch (mimeType) {
      case 'Image':
        return Icons.image_rounded;
      case 'Video':
        return Icons.videocam_rounded;
      case 'Audio':
        return Icons.audiotrack_rounded;
      case 'PDF':
        return Icons.picture_as_pdf_rounded;
      case 'Archive':
        return Icons.folder_zip_rounded;
      case 'Document':
        return Icons.description_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_typeIcon, color: AppColors.primary, size: 22),
          ),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$size • $mimeType',
                  style: TextStyle(
                    color:
                        AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close_rounded,
                    color:
                        AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                    size: 18),
              ),
            ),
        ],
      ),
    );
  }
}
