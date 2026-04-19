import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide UserIdentity;

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../identity/identity_service.dart';
import '../transfer/transfer_service.dart';

class HistoryScreen extends StatefulWidget {
  final UserIdentity identity;
  const HistoryScreen({super.key, required this.identity});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
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
              backgroundColor: AppColors.snackBarBg,
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
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child:
                      Image.asset('assets/logo.png', width: 32, height: 32),
                ),
                const SizedBox(width: 10),
                const Text(
                  'History',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    letterSpacing: -0.4,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.refresh_rounded,
                      color: AppColors.onSurfaceVariant
                          .withValues(alpha: 0.5)),
                  onPressed: _loadTransfers,
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 8),
                              itemCount:
                                  _transfers!.length + (_hasMore ? 1 : 0),
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
                                          color: AppColors.primary
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                final t = _transfers![index];
                                final senderCode =
                                    (t['sender'] as Map?)?['short_code'] ??
                                        '???';
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
                                );
                              },
                            ),
                          ),
          ),
        ],
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

  const _TransferCard({
    required this.senderCode,
    required this.status,
    required this.timeAgo,
    this.isExpired = false,
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
    return Opacity(
      opacity: isExpired ? 0.45 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color.fromARGB(255, 135, 175, 255).withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isExpired
                    ? Icons.timer_off_rounded
                    : Icons.person_rounded,
                color: isExpired
                    ? AppColors.outlineVariant
                    : AppColors.primary,
                size: 20,
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
                      fontSize: 14,
                      color: AppColors.onSurface,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: _statusColor(),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isExpired ? 'Expired' : status,
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant
                              .withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant
                              .withValues(alpha: 0.3),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
