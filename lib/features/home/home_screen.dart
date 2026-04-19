import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../features/identity/identity_service.dart';
import '../../features/send/send_screen.dart';
import '../../features/receive/receive_screen.dart';
import '../transfer/transfer_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  UserIdentity? _identity;
  bool _loading = true;
  String? _error;
  bool _isOnline = true;
  List<Map<String, dynamic>>? _sentHistory;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkConnectivity();
    _loadIdentity();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkConnectivity();
      if (_identity != null) _loadSentHistory();
    }
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (mounted) {
        setState(() {
          _isOnline = !result.contains(ConnectivityResult.none);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadIdentity() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final identity = await IdentityService.initialize();
      if (mounted) {
        setState(() {
          _identity = identity;
          _loading = false;
        });
        _loadSentHistory();
      }
    } on AuthFailedException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not connect. Check your internet and try again.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadSentHistory() async {
    if (_identity == null) return;
    try {
      final history =
          await TransferService.getSentTransfers(_identity!.id, page: 0);
      if (mounted) {
        setState(() => _sentHistory = history);
      }
    } catch (_) {}
  }

  void _copyCode() {
    if (_identity == null) return;
    Clipboard.setData(ClipboardData(text: _identity!.shortCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Code copied'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceContainerHigh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const _LoadingView()
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _loadIdentity)
                : _HomeBody(
                    identity: _identity!,
                    onCopyCode: _copyCode,
                    isOnline: _isOnline,
                    sentHistory: _sentHistory,
                  ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Setting up...',
            style: TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 14,
              letterSpacing: -0.02,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 48, color: AppColors.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  final UserIdentity identity;
  final VoidCallback onCopyCode;
  final bool isOnline;
  final List<Map<String, dynamic>>? sentHistory;

  const _HomeBody({
    required this.identity,
    required this.onCopyCode,
    required this.isOnline,
    this.sentHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/logo.png', width: 28, height: 28),
              ),
              const SizedBox(width: 10),
              const Text(
                'ZenSend',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                  letterSpacing: -0.4,
                ),
              ),
              const Spacer(),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isOnline ? AppColors.success : AppColors.error,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),

          const SizedBox(height: 36),

          // ── Share code card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF1E2A3E),
                  Color(0xFF172030),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your share code',
                  style: TextStyle(
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      identity.shortCode,
                      style: const TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onCopyCode,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.copy_rounded,
                            color: AppColors.primary.withValues(alpha: 0.7),
                            size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Share this code so others can send you files',
                  style: TextStyle(
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 36),

          // ── Action cards
          _ActionTile(
            icon: Icons.arrow_upward_rounded,
            title: 'Send Files',
            subtitle: 'Enter a code and send media',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SendScreen(identity: identity),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.arrow_downward_rounded,
            title: 'Incoming Files',
            subtitle: 'View files sent to your code',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReceiveScreen(identity: identity),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── Sent history
          if (sentHistory != null && sentHistory!.isNotEmpty) ...[
            Text(
              'Recent',
              style: TextStyle(
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: sentHistory!.length > 5 ? 5 : sentHistory!.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final t = sentHistory![index];
                  final receiverCode =
                      (t['receiver'] as Map?)?['short_code'] ?? '???';
                  final status = (t['status'] ?? 'pending') as String;
                  final createdAt = (t['created_at'] ?? '') as String;
                  return _SentHistoryTile(
                    receiverCode: receiverCode,
                    status: status,
                    timeAgo: _timeAgo(createdAt),
                  );
                },
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
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
}

class _SentHistoryTile extends StatelessWidget {
  final String receiverCode;
  final String status;
  final String timeAgo;

  const _SentHistoryTile({
    required this.receiverCode,
    required this.status,
    required this.timeAgo,
  });

  Color get _statusColor {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'partial':
        return AppColors.error;
      case 'failed':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 4,
            decoration:
                BoxDecoration(color: _statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(
            'To $receiverCode',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            status,
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
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: AppColors.onSurface,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.outlineVariant.withValues(alpha: 0.5), size: 20),
          ],
        ),
      ),
    );
  }
}
