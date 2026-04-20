import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/connection_status.dart';
import '../../core/native/native_share.dart';
import '../../core/theme.dart';
import '../identity/identity_service.dart';
import '../send/send_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserIdentity identity;
  const HomeScreen({super.key, required this.identity});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isOnline = true;
  late final VoidCallback _onConnectionChanged;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ConnectionStatus.instance.ensureStarted();
    _isOnline = ConnectionStatus.instance.online.value;
    _onConnectionChanged = () {
      final next = ConnectionStatus.instance.online.value;
      if (!mounted || next == _isOnline) return;
      setState(() => _isOnline = next);
    };
    ConnectionStatus.instance.online.addListener(_onConnectionChanged);
    unawaited(ConnectionStatus.instance.refresh());
  }

  @override
  void dispose() {
    ConnectionStatus.instance.online.removeListener(_onConnectionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ConnectionStatus.instance.refresh());
    }
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.identity.shortCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Code copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.snackBarBg,
      ),
    );
  }

  void _shareCode() {
    NativeShareService.shareText(
      'Send me files on ZenSend using my code: ${widget.identity.shortCode}',
      subject: 'ZenSend invite',
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 28),
            _buildIdentitySection(),
            const SizedBox(height: 20),
            _buildSessionCodeCard(),
            const SizedBox(height: 24),
            _buildSendButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset('assets/logo.png', width: 32, height: 32),
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
      ],
    );
  }

  Widget _buildIdentitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'IDENTITY ANCHOR',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Personal Short-code',
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isOnline
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _isOnline ? AppColors.primary : AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isOnline ? 'Ready to Receive' : 'Offline',
                    style: TextStyle(
                      color: _isOnline ? AppColors.primary : AppColors.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSessionCodeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color.fromARGB(255, 83, 109, 255).withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Active Session ID',
            style: TextStyle(
              color: AppColors.cardTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              widget.identity.shortCode,
              style: const TextStyle(
                color: AppColors.cardText,
                fontSize: 42,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: _copyCode,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3366FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _shareCode,
                    icon: Icon(Icons.share_rounded,
                        size: 16, color: AppColors.cardText),
                    label: Text(
                      'Share',
                      style: TextStyle(color: AppColors.cardText),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: const Color.fromARGB(255, 70, 131, 252), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryContainer],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SendScreen(identity: widget.identity),
            ),
          ),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('Send Files'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
