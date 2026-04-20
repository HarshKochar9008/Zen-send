import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide UserIdentity;

import '../../core/constants.dart';
import '../../core/network/connection_status.dart';
import '../../core/theme.dart';
import '../identity/identity_service.dart';
import '../transfer/transfer_service.dart';

enum _HistoryFilter { all, received, sent }

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
  _HistoryFilter _filter = _HistoryFilter.all;
  late final VoidCallback _onConnectionChanged;

  @override
  void initState() {
    super.initState();
    ConnectionStatus.instance.ensureStarted();
    _onConnectionChanged = () {
      if (!ConnectionStatus.instance.online.value) return;
      if (_error != null && mounted) {
        _loadTransfers();
      }
    };
    ConnectionStatus.instance.online.addListener(_onConnectionChanged);
    _loadTransfers();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    ConnectionStatus.instance.online.removeListener(_onConnectionChanged);
    if (_channel != null) TransferService.unsubscribe(_channel!);
    super.dispose();
  }

  void _subscribeToRealtime() {
    _channel = TransferService.subscribeToIncoming(
      userId: widget.identity.id,
      onTransferChange: (record, event) {
        _loadTransfers();
        if (!mounted) return;
        if (event == PostgresChangeEvent.insert) {
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
          return;
        }
        final status = record['status'] as String? ?? 'pending';
        if (status == 'completed' || status == 'partial') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                status == 'completed'
                    ? 'Transfer ready — files available for download!'
                    : 'Some files from a transfer are ready to download.',
              ),
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
      final incoming = await TransferService.getIncomingTransfers(
        widget.identity.id,
        page: 0,
      );
      final sent = await TransferService.getSentTransfers(
        widget.identity.id,
        page: 0,
      );
      final transfers = _mergeAndSortTransfers(incoming, sent);
      if (mounted) {
        setState(() {
          _transfers = transfers;
          _loading = false;
          _hasMore = incoming.length >= AppConstants.transfersPageSize ||
              sent.length >= AppConstants.transfersPageSize;
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
      final moreIncoming = await TransferService.getIncomingTransfers(
        widget.identity.id,
        page: nextPage,
      );
      final moreSent = await TransferService.getSentTransfers(
        widget.identity.id,
        page: nextPage,
      );
      final more = _mergeAndSortTransfers(moreIncoming, moreSent);
      if (mounted) {
        setState(() {
          _transfers = _mergeAndSortExistingWithMore(_transfers ?? [], more);
          _currentPage = nextPage;
          _hasMore = moreIncoming.length >= AppConstants.transfersPageSize ||
              moreSent.length >= AppConstants.transfersPageSize;
        });
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _mergeAndSortTransfers(
    List<Map<String, dynamic>> incoming,
    List<Map<String, dynamic>> sent,
  ) {
    final normalizedIncoming = incoming.map((t) {
      final senderCode = (t['sender'] as Map?)?['short_code'] ?? '???';
      return {
        ...t,
        '_direction': 'received',
        '_counterpartyCode': senderCode,
      };
    });
    final normalizedSent = sent.map((t) {
      final receiverCode = (t['receiver'] as Map?)?['short_code'] ?? '???';
      return {
        ...t,
        '_direction': 'sent',
        '_counterpartyCode': receiverCode,
      };
    });
    final all = [...normalizedIncoming, ...normalizedSent];
    all.sort((a, b) {
      final aDate = DateTime.tryParse((a['created_at'] ?? '').toString());
      final bDate = DateTime.tryParse((b['created_at'] ?? '').toString());
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return all;
  }

  List<Map<String, dynamic>> _mergeAndSortExistingWithMore(
    List<Map<String, dynamic>> existing,
    List<Map<String, dynamic>> more,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final t in [...existing, ...more]) {
      final id = (t['id'] ?? '').toString();
      if (id.isNotEmpty) byId[id] = t;
    }
    final merged = byId.values.toList();
    merged.sort((a, b) {
      final aDate = DateTime.tryParse((a['created_at'] ?? '').toString());
      final bDate = DateTime.tryParse((b['created_at'] ?? '').toString());
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return merged;
  }

  List<Map<String, dynamic>> _applyFilter(
      List<Map<String, dynamic>> transfers) {
    switch (_filter) {
      case _HistoryFilter.sent:
        return transfers.where((t) => t['_direction'] == 'sent').toList();
      case _HistoryFilter.received:
        return transfers.where((t) => t['_direction'] == 'received').toList();
      case _HistoryFilter.all:
        return transfers;
    }
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
                  child: Image.asset('assets/logo.png', width: 32, height: 32),
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
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
                  onPressed: _loadTransfers,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == _HistoryFilter.all,
                  onSelected: (_) =>
                      setState(() => _filter = _HistoryFilter.all),
                ),
                ChoiceChip(
                  label: const Text('Received'),
                  selected: _filter == _HistoryFilter.received,
                  onSelected: (_) =>
                      setState(() => _filter = _HistoryFilter.received),
                ),
                ChoiceChip(
                  label: const Text('Sent'),
                  selected: _filter == _HistoryFilter.sent,
                  onSelected: (_) =>
                      setState(() => _filter = _HistoryFilter.sent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

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
                    : _transfers == null || _applyFilter(_transfers!).isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _loadTransfers,
                            color: AppColors.primary,
                            child: Builder(builder: (context) {
                              final visibleTransfers =
                                  _applyFilter(_transfers!);
                              return ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                itemCount: visibleTransfers.length +
                                    (_hasMore ? 1 : 0),
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  if (index == visibleTransfers.length) {
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

                                  final t = visibleTransfers[index];
                                  final direction =
                                      (t['_direction'] ?? 'received')
                                          .toString();
                                  final counterpartyCode =
                                      (t['_counterpartyCode'] ?? '???')
                                          .toString();
                                  final status =
                                      (t['status'] ?? 'pending').toString();
                                  final createdAt =
                                      (t['created_at'] ?? '').toString();
                                  final isExpired = status == 'expired';
                                  return _TransferCard(
                                    direction: direction,
                                    counterpartyCode: counterpartyCode,
                                    status: status,
                                    timeAgo: _timeAgo(createdAt),
                                    isExpired: isExpired,
                                  );
                                },
                              );
                            }),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final title = switch (_filter) {
      _HistoryFilter.sent => 'No files sent yet',
      _HistoryFilter.received => 'No files received yet',
      _HistoryFilter.all => 'No transfers yet',
    };
    final subtitle = switch (_filter) {
      _HistoryFilter.sent => 'Send files to see them here',
      _HistoryFilter.received => 'Share your code so others can send you files',
      _HistoryFilter.all => 'Your sent and received files will appear here',
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded,
              size: 48,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.15)),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
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
  final String direction;
  final String counterpartyCode;
  final String status;
  final String timeAgo;
  final bool isExpired;

  const _TransferCard({
    required this.direction,
    required this.counterpartyCode,
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
          border: Border.all(
              color: const Color.fromARGB(255, 135, 175, 255)
                  .withValues(alpha: 0.6)),
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
                isExpired ? Icons.timer_off_rounded : _directionIcon(),
                color: isExpired ? AppColors.outlineVariant : AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${direction == 'sent' ? 'To' : 'From'} $counterpartyCode',
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
                        isExpired
                            ? 'Expired'
                            : '${direction == 'sent' ? 'Sent' : 'Received'} · $status',
                        style: TextStyle(
                          color:
                              AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          color:
                              AppColors.onSurfaceVariant.withValues(alpha: 0.3),
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

  IconData _directionIcon() {
    return direction == 'sent'
        ? Icons.north_east_rounded
        : Icons.south_west_rounded;
  }
}
