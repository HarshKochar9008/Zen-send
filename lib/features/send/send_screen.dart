import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/constants.dart';
import '../../core/network/connection_status.dart';
import '../../core/network/network_errors.dart';
import '../../core/theme.dart';
import '../identity/identity_service.dart';
import '../transfer/transfer_progress_widgets.dart';
import '../transfer/transfer_service.dart';

class SendScreen extends StatefulWidget {
  final UserIdentity identity;
  const SendScreen({super.key, required this.identity});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> with WidgetsBindingObserver {
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
  final Battery _battery = Battery();
  bool _powerSaveMode = false;
  int? _batteryLevel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPowerSaveMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkInterruptedUploadRecovery());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPowerSaveMode();
    }
  }

  Future<void> _refreshPowerSaveMode() async {
    final enabled = await _isPowerSaveModeEnabled();
    int? level;
    try {
      level = await _battery.batteryLevel;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _powerSaveMode = enabled;
      _batteryLevel = level;
    });
  }

  Future<void> _checkInterruptedUploadRecovery() async {
    final pending = await TransferService.getPendingUploadJob(
      senderId: widget.identity.id,
    );
    if (!mounted || pending == null) return;

    final existing = <PlatformFile>[];
    for (final file in pending.toPlatformFiles()) {
      final p = file.path;
      if (p != null && await File(p).exists()) {
        existing.add(file);
      }
    }
    if (!mounted) return;

    if (existing.isEmpty) {
      if (!mounted) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Interrupted send',
            style: TextStyle(color: AppColors.onSurface, fontSize: 16),
          ),
          content: Text(
            'A previous send did not finish, but the saved files are no longer '
            'on this device (common after a restart). Discard this reminder?',
            style: TextStyle(
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (discard == true) {
        await TransferService.discardPendingUploadJob(
          senderId: widget.identity.id,
        );
      }
      return;
    }

    final shouldResume = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Resume interrupted upload?',
          style: TextStyle(color: AppColors.onSurface, fontSize: 16),
        ),
        content: Text(
          'We found an interrupted upload with ${existing.length} file(s). '
          'Do you want to resume it?',
          style: TextStyle(
            color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Resume'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (shouldResume != true) {
      await TransferService.discardPendingUploadJob(senderId: widget.identity.id);
      return;
    }

    setState(() {
      _selectedFiles = existing;
      _validatedRecipientId = pending.receiverId;
      _codeValidated = true;
      _codeError = null;
      _error = 'Resumed interrupted upload. Tap Send to continue.';
      if (pending.receiverCode != null && pending.receiverCode!.isNotEmpty) {
        _codeController.text = pending.receiverCode!;
      }
    });
  }

  Future<bool> _isLikelyMeteredConnection() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.mobile);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _confirmMeteredUploadIfNeeded() async {
    final isMetered = await _isLikelyMeteredConnection();
    if (!mounted) return false;

    final threshold = isMetered
        ? AppConstants.cellularMeteredWarnThresholdBytes
        : AppConstants.largeUploadWarnThresholdBytes;
    if (_totalSize < threshold) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isMetered ? 'Using mobile data' : 'Large upload',
          style: TextStyle(color: AppColors.onSurface, fontSize: 16),
        ),
        content: Text(
          isMetered
              ? 'This upload is ${_formatSize(_totalSize)} and may use significant '
                  'cellular data. Continue?'
              : 'This upload is ${_formatSize(_totalSize)}. '
                  'Large uploads may take longer and use more data. Continue?',
          style: TextStyle(
            color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<bool> _isPowerSaveModeEnabled() async {
    try {
      return await _battery.isInBatterySaveMode;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _confirmPowerSaveUploadIfNeeded() async {
    if (_totalSize < AppConstants.largeUploadWarnThresholdBytes) return true;
    final powerSave = await _isPowerSaveModeEnabled();
    if (!powerSave || !mounted) return true;

    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Battery saver is on',
          style: TextStyle(color: AppColors.onSurface, fontSize: 16),
        ),
        content: Text(
          'This upload is ${_formatSize(_totalSize)}. '
          'Power-save mode may throttle network and interrupt long transfers. Continue anyway?',
          style: TextStyle(
            color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
      );
      if (result == null || !mounted) return;

      final accessibleRaw = result.files.where((f) => f.path != null).toList();
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
          _error = '${oversized.first.name} exceeds '
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
          _error = 'Max ${AppConstants.maxFilesPerTransfer} files per transfer';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.file_copy_rounded, color: AppColors.warning, size: 20),
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
    final code = AppConstants.normalizeShortCode(_codeController.text);
    if (code.isEmpty) {
      setState(() => _codeError = 'Enter a recipient code');
      return;
    }
    if (code.length != AppConstants.codeLength) {
      setState(
        () => _codeError =
            'Code must be exactly ${AppConstants.codeLength} characters',
      );
      return;
    }
    if (!AppConstants.isValidShortCodeFormat(code)) {
      setState(
        () => _codeError = 'Use only A-Z and 2-9 (excluding O, I, L, 0, 1)',
      );
      return;
    }
    if (code == widget.identity.shortCode) {
      setState(() => _codeError = 'You cannot send files to yourself');
      return;
    }

    if (!await ConnectionStatus.instance.refresh()) {
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
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _codeError = e.message.isNotEmpty
              ? 'Server error while looking up code: ${e.message}'
              : 'Server rejected this lookup. Check Supabase RLS allows '
                  'anonymous users to read `users` for `short_code`.';
          _validatingCode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _codeError = NetworkErrors.isRetryableFailure(e)
              ? 'Cannot reach Supabase to validate this code (network or '
                  'firewall). Wi‑Fi/VPN/DNS can block *.supabase.co — try '
                  'another network.'
              : 'Could not validate code: $e';
          _validatingCode = false;
        });
      }
    }
  }

  Future<void> _send() async {
    if (_validatedRecipientId == null || _selectedFiles.isEmpty) return;
    final pushReadiness = await TransferService.verifyClosedAppDeliveryReadiness(
      receiverId: _validatedRecipientId!,
    );
    if (!pushReadiness.ready) {
      if (!mounted) return;
      setState(() {
        _error = pushReadiness.reason ??
            'Incoming delivery while recipient app is closed is not configured yet.';
      });
      return;
    }

    final powerApproved = await _confirmPowerSaveUploadIfNeeded();
    if (!powerApproved || !mounted) return;
    final confirmed = await _confirmMeteredUploadIfNeeded();
    if (!confirmed || !mounted) return;

    if (!await ConnectionStatus.instance.refresh()) {
      if (!mounted) return;
      setState(() {
        _error = 'No internet connection. Try again when you are online.';
      });
      return;
    }

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
        receiverCode: AppConstants.normalizeShortCode(_codeController.text),
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
            content: Text('${result.completedFiles} file(s) sent successfully'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.snackBarBg,
          ),
        );
        Navigator.pop(context);
      } else {
        final failureMessage = _buildPartialFailureMessage(result);
        setState(() {
          _error = failureMessage;
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
          _error = _toUserFriendlyError(e.toString());
          _sending = false;
        });
      }
    } on TooManyFilesException catch (e) {
      if (mounted) {
        setState(() {
          _error = _toUserFriendlyError(e.toString());
          _sending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _toUserFriendlyError(e.toString());
          _sending = false;
        });
      }
    } finally {
      _uploadCancellationToken = null;
    }
  }

  String _buildPartialFailureMessage(TransferResult result) {
    final failed = result.fileStates
        .where((s) => s.status == FileUploadStatus.failed)
        .toList();
    if (failed.isEmpty) {
      return 'Some files could not be sent.';
    }

    final first = failed.first;
    final reason = _toUserFriendlyError(first.error ?? 'Unknown error');

    if (failed.length == 1) {
      return '$reason (${first.fileName})';
    }

    return '$reason (${first.fileName}). ${failed.length - 1} more file(s) failed.';
  }

  String _toUserFriendlyError(String raw) {
    var message = raw.replaceAll('Exception: ', '').trim();

    if (message.contains('Failed after')) {
      final idx = message.indexOf(':');
      if (idx != -1 && idx + 1 < message.length) {
        message = message.substring(idx + 1).trim();
      }
    }

    if (message.contains('No internet connection')) {
      return 'No internet connection. Please try again.';
    }
    if (message.contains('File not accessible on disk')) {
      return 'This file is no longer accessible. Please pick it again.';
    }
    if (message.contains('Hash computation failed')) {
      return 'Could not read this file. Please pick it again.';
    }
    if (message.contains('Upload failed (401') ||
        message.contains('Upload failed (403')) {
      return 'Upload permission failed. Please try again.';
    }
    if (message.toLowerCase().contains('protocol(413') ||
        message.toLowerCase().contains('payload too large') ||
        message.toLowerCase().contains('creating upload')) {
      return 'File is too large for the server upload limit. '
          'Try a smaller file or increase the Supabase Storage bucket size limit.';
    }
    if (message.toLowerCase().contains('invalid') &&
        message.toLowerCase().contains('mime')) {
      return 'This file format is not supported.';
    }

    return message;
  }

  void _cancelUpload() {
    _uploadCancellationToken?.cancel();
  }

  String _formatSize(int bytes) {
    return TransferService.formatFileSize(bytes);
  }

  int get _totalSize => _selectedFiles.fold<int>(0, (sum, f) => sum + f.size);

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

  Widget _buildPowerSaveBanner() {
    if (!_powerSaveMode) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.battery_saver_rounded,
            size: 16,
            color: AppColors.warning.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Battery saver is on. Large uploads may be slower or pause.',
              style: TextStyle(
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.85),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryBadge() {
    final levelText = _batteryLevel != null ? '${_batteryLevel!}%' : '--%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (_powerSaveMode ? AppColors.warning : AppColors.primary)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (_powerSaveMode ? AppColors.warning : AppColors.primary)
              .withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _powerSaveMode
                ? Icons.battery_saver_rounded
                : Icons.battery_std_rounded,
            size: 14,
            color: (_powerSaveMode ? AppColors.warning : AppColors.primary)
                .withValues(alpha: 0.95),
          ),
          const SizedBox(width: 6),
          Text(
            levelText,
            style: TextStyle(
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                    child:
                        Image.asset('assets/logo.png', width: 32, height: 32),
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
                  _buildBatteryBadge(),
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
                    _buildPowerSaveBanner(),

                    // Recipient code input card
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.cardBorder.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _codeController,
                              enabled: !_sending && !_codeValidated,
                              textCapitalization: TextCapitalization.characters,
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
                      TransferUploadProgressList(states: _uploadStates!)
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
                    if (_codeValidated && _selectedFiles.isNotEmpty) ...[
                      Text(
                        'Keep the app open while uploading. Closing the app will stop the transfer.',
                        style: TextStyle(
                          color:
                              AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
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
                      color: _sending ? AppColors.outlineVariant : null,
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
          style:
              const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
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
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
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
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                    size: 18),
              ),
            ),
        ],
      ),
    );
  }
}
