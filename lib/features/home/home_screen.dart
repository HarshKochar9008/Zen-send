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
    } catch (_) {
      // Connectivity check failed, assume online
    }
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
    } catch (_) {
      // Non-critical — silently ignore
    }
  }

  void _copyCode() {
    if (_identity == null) return;
    Clipboard.setData(ClipboardData(text: _identity!.shortCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
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

// ── Loading ─────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Setting up your identity...'),
        ],
      ),
    );
  }
}

// ── Error ────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ── Main body ────────────────────────────────────────────────────────────────

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
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/logo.png',
                  width: 36,
                  height: 36,
                ),
              ),
              const SizedBox(width: 10),
              Text('ZenShare',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              // Connectivity indicator
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOnline
                      ? AppColors.success.withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isOnline
                            ? AppColors.success
                            : Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        color: isOnline
                            ? AppColors.success
                            : Colors.redAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Your code card ───────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your share code',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      identity.shortCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 6,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onCopyCode,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.copy_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Share this code so others can send you files',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Action buttons ───────────────────────────────────────
          const Text('ACTIONS',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          _ActionTile(
            icon: Icons.upload_rounded,
            iconColor: AppColors.primary,
            title: 'Send Files',
            subtitle: 'Enter a code and send media',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SendScreen(identity: identity),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.download_rounded,
            iconColor: AppColors.primaryDark,
            title: 'Incoming Files',
            subtitle: 'View files sent to your code',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReceiveScreen(identity: identity),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // ── Sent history ────────────────────────────────────────
          if (sentHistory != null && sentHistory!.isNotEmpty) ...[
            const Text('RECENT SENDS',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
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

// ── Sent history tile ────────────────────────────────────────────────────────

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
        return Colors.redAccent;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.send_rounded, size: 16, color: _statusColor),
          const SizedBox(width: 10),
          Text(
            'To $receiverCode',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: _statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(status,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(width: 8),
          Text(timeAgo,
              style: const TextStyle(color: Colors.white24, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Action tile ──────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white24, size: 22),
          ],
        ),
      ),
    );
  }
}
