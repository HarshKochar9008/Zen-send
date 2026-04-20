import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'transfer_service.dart';

/// Shared upload progress UI for send and receive flows.
class TransferUploadProgressList extends StatelessWidget {
  final List<FileUploadProgress> states;
  /// When set, shown before the "n / m uploaded" segment (e.g. "Live from sender").
  final String? headerPrefix;

  const TransferUploadProgressList({
    super.key,
    required this.states,
    this.headerPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final completed =
        states.where((s) => s.status == FileUploadStatus.completed).length;
    final tail = '$completed / ${states.length} uploaded';
    final header =
        headerPrefix != null ? '$headerPrefix · $tail' : tail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                header,
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
              child: TransferFileProgressTile(state: s),
            )),
      ],
    );
  }
}

class TransferFileProgressTile extends StatelessWidget {
  final FileUploadProgress state;
  const TransferFileProgressTile({super.key, required this.state});

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
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.onSurface),
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
