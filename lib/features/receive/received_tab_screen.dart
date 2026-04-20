import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide UserIdentity;

import '../../core/network/connection_status.dart';
import '../../core/theme.dart';
import '../identity/identity_service.dart';
import '../transfer/transfer_service.dart';
import 'receive_screen.dart';

class ReceivedTabScreen extends StatefulWidget {
  final UserIdentity identity;
  const ReceivedTabScreen({super.key, required this.identity});

  @override
  State<ReceivedTabScreen> createState() => _ReceivedTabScreenState();
}

class _ReceivedTabScreenState extends State<ReceivedTabScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>>? _transfers;
  bool _loading = true;
  String? _error;
  RealtimeChannel? _channel;
  Timer? _realtimeHealthTimer;
  DateTime _lastRealtimeSignalAt = DateTime.now().toUtc();
  late final VoidCallback _onConnectionChanged;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    _startRealtimeHealthChecks();
  }

  @override
  void dispose() {
    ConnectionStatus.instance.online.removeListener(_onConnectionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _realtimeHealthTimer?.cancel();
    if (_channel != null) TransferService.unsubscribe(_channel!);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ConnectionStatus.instance.refresh());
      _loadTransfers();
      _ensureRealtimeHealthy(forceResubscribe: true);
    }
  }

  void _subscribeToRealtime() {
    _lastRealtimeSignalAt = DateTime.now().toUtc();
    _channel = TransferService.subscribeToIncoming(
      userId: widget.identity.id,
      onTransferChange: (record, event) {
        _lastRealtimeSignalAt = DateTime.now().toUtc();
        _loadTransfers();
        if (!mounted) return;
        if (event == PostgresChangeEvent.insert) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Incoming transfer…'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.snackBarBg,
              duration: Duration(seconds: 3),
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
                    ? 'New files ready to download!'
                    : 'Some files are ready to download.',
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

  void _startRealtimeHealthChecks() {
    _realtimeHealthTimer?.cancel();
    _realtimeHealthTimer = Timer.periodic(
        const Duration(seconds: 45), (_) => _ensureRealtimeHealthy());
  }

  Future<void> _ensureRealtimeHealthy({bool forceResubscribe = false}) async {
    final staleFor = DateTime.now().toUtc().difference(_lastRealtimeSignalAt);
    final stale = staleFor > const Duration(minutes: 3);
    if (!forceResubscribe && !stale && _channel != null) return;

    final old = _channel;
    _channel = null;
    if (old != null) {
      await TransferService.unsubscribe(old);
    }
    if (!mounted) return;
    _subscribeToRealtime();
  }

  Future<void> _loadTransfers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final transfers = await TransferService.getIncomingTransfers(
        widget.identity.id,
        page: 0,
      );
      if (mounted) {
        final active = transfers
            .where((t) => (t['status'] ?? 'pending') != 'expired')
            .toList();
        setState(() {
          _transfers = active;
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
    final date = DateTime.tryParse(isoDate);
    if (date == null) return '';
    final diff = DateTime.now().toUtc().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  int _totalFiles() {
    if (_transfers == null) return 0;
    return _transfers!.length;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  'Received',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    letterSpacing: -0.4,
                  ),
                ),
                const Spacer(),
                if (_transfers != null && _transfers!.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_totalFiles()} active',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.refresh_rounded,
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
                  onPressed: _loadTransfers,
                ),
              ],
            ),
          ),
          if (_channel != null)
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Listening for incoming files',
                    style: TextStyle(
                      color: AppColors.success.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
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
                              itemCount: _transfers!.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final t = _transfers![index];
                                final senderCode =
                                    (t['sender'] as Map?)?['short_code'] ??
                                        '???';
                                final status =
                                    (t['status'] ?? 'pending') as String;
                                final createdAt =
                                    (t['created_at'] ?? '') as String;

                                return _ReceivedCard(
                                  senderCode: senderCode,
                                  status: status,
                                  timeAgo: _timeAgo(createdAt),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ReceiveScreen(
                                        transferId: t['id'] as String,
                                        senderCode: senderCode,
                                      ),
                                    ),
                                  ),
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
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.download_rounded,
                size: 36, color: AppColors.primary.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 20),
          const Text(
            'No active transfers',
            style: TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Files sent to you will appear here.\nShare your code so others can send files.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (_channel != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
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
        ],
      ),
    );
  }
}

class _ReceivedCard extends StatelessWidget {
  final String senderCode;
  final String status;
  final String timeAgo;
  final VoidCallback onTap;

  const _ReceivedCard({
    required this.senderCode,
    required this.status,
    required this.timeAgo,
    required this.onTap,
  });

  Color _statusColor() {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'uploading':
      case 'pending':
        return AppColors.warning;
      case 'partial':
      case 'failed':
        return AppColors.error;
      default:
        return AppColors.outlineVariant;
    }
  }

  String _statusLabel() {
    switch (status) {
      case 'completed':
        return 'Ready to download';
      case 'uploading':
        return 'Uploading…';
      case 'pending':
        return 'Pending';
      case 'partial':
        return 'Partial';
      case 'failed':
        return 'Failed';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: AppColors.cardBorder.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: status == 'completed'
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                status == 'completed'
                    ? Icons.download_done_rounded
                    : Icons.download_rounded,
                color: status == 'completed'
                    ? AppColors.success
                    : AppColors.primary,
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
                      color: AppColors.onSurface,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _statusColor(),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _statusLabel(),
                        style: TextStyle(
                          color:
                              AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant
                              .withValues(alpha: 0.35),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
