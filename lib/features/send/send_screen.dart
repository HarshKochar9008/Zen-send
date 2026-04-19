import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/constants.dart';
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

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
      );
      if (result == null || !mounted) return;

      final accessible =
          result.files.where((f) => f.path != null).toList();

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

      final totalCount = _selectedFiles.length + accessible.length;
      if (totalCount > AppConstants.maxFilesPerTransfer) {
        setState(() {
          _error =
              'Max ${AppConstants.maxFilesPerTransfer} files per transfer';
        });
        return;
      }

      setState(() {
        _selectedFiles = [..._selectedFiles, ...accessible];
        _error = null;
      });
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

    setState(() {
      _validatingCode = true;
      _codeError = null;
      _error = null;
    });

    final recipient = await IdentityService.findUserByCode(code);
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
            content: Text(
              '${result.completedFiles} file(s) sent to $code',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF4CAF50),
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
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Files'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Recipient code ───────────────────────────────────────
            const Text(
              'Recipient Code',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              enabled: !_sending,
              textCapitalization: TextCapitalization.characters,
              maxLength: AppConstants.codeLength,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: 'ABC123',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.15),
                  fontSize: 24,
                  letterSpacing: 8,
                ),
                counterText: '',
                filled: true,
                fillColor: const Color(0xFF1A1A24),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                errorText: _codeError,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Files header ─────────────────────────────────────────
            Row(
              children: [
                const Text(
                  'Files',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (!_sending)
                  TextButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      _selectedFiles.isEmpty ? 'Pick Files' : 'Add More',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // ── File list / progress view ────────────────────────────
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
                              onRemove:
                                  _sending ? null : () => _removeFile(index),
                            );
                          },
                        ),
            ),

            // ── Error ────────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // ── Send button ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed:
                    (_sending || _validatingCode) ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _sending
                    ? _buildSendingLabel()
                    : _validatingCode
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Send',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
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
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      );
    }
    final done =
        states.where((s) => s.status == FileUploadStatus.completed).length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        Text('Sending $done / ${states.length} files'),
      ],
    );
  }
}

// ── Upload progress list ─────────────────────────────────────────────────────

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
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$completed / ${states.length} files uploaded',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: states.isNotEmpty ? completed / states.length : 0,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(
                    Color(0xFF6C63FF),
                  ),
                  minHeight: 6,
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

// ── Per-file progress tile ───────────────────────────────────────────────────

class _FileProgressTile extends StatelessWidget {
  final FileUploadProgress state;
  const _FileProgressTile({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A24),
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
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              Text(
                _statusLabel(),
                style: TextStyle(
                  color: _statusColor(),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (state.status == FileUploadStatus.hashing ||
              state.status == FileUploadStatus.uploading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: state.progress,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(_statusColor()),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              state.status == FileUploadStatus.hashing
                  ? 'Verifying integrity… ${(state.progress * 100).toInt()}%'
                  : 'Uploading… ${(state.progress * 100).toInt()}%'
                      '${state.attempt > 1 ? ' (retry ${state.attempt})' : ''}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
          if (state.status == FileUploadStatus.completed &&
              state.sha256 != null) ...[
            const SizedBox(height: 4),
            Text(
              'SHA-256: ${state.sha256!.substring(0, 16)}…',
              style: const TextStyle(
                color: Colors.white24,
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

  Widget _statusIcon() {
    switch (state.status) {
      case FileUploadStatus.pending:
        return const Icon(Icons.schedule, color: Colors.white24, size: 20);
      case FileUploadStatus.hashing:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case FileUploadStatus.uploading:
        return const Icon(
          Icons.cloud_upload_rounded,
          color: Color(0xFF6C63FF),
          size: 20,
        );
      case FileUploadStatus.completed:
        return const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF4CAF50),
          size: 20,
        );
      case FileUploadStatus.failed:
        return const Icon(
          Icons.error_rounded,
          color: Colors.redAccent,
          size: 20,
        );
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
        return Colors.white24;
      case FileUploadStatus.hashing:
        return const Color(0xFF3F8CFF);
      case FileUploadStatus.uploading:
        return const Color(0xFF6C63FF);
      case FileUploadStatus.completed:
        return const Color(0xFF4CAF50);
      case FileUploadStatus.failed:
        return Colors.redAccent;
    }
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyFilesView extends StatelessWidget {
  final VoidCallback onPick;
  const _EmptyFilesView({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1.5,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                size: 48,
                color: Colors.white24,
              ),
              SizedBox(height: 12),
              Text(
                'Tap to select files',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
              SizedBox(height: 4),
              Text(
                'Images, videos, documents — any file type',
                style: TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── File tile (pre-send) ─────────────────────────────────────────────────────

class _FileTile extends StatelessWidget {
  final String name;
  final String size;
  final VoidCallback? onRemove;

  const _FileTile({required this.name, required this.size, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.insert_drive_file_rounded,
            color: Color(0xFF6C63FF),
            size: 22,
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
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  size,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white24,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }
}
