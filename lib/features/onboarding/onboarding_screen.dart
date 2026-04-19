import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    widget.onComplete();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 16),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    _currentPage == 2 ? '' : 'Skip',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: const [
                  _SlideSecureTransfer(),
                  _SlideSelectAssets(),
                  _SlideFeatures(),
                ],
              ),
            ),

            // Dots + button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Row(
                children: [
                  // Dot indicators
                  Row(
                    children: List.generate(3, (i) {
                      final isActive = i == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        margin: const EdgeInsets.only(right: 8),
                        width: isActive ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.primary
                              : AppColors.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const Spacer(),
                  // Next / Get Started
                  FilledButton(
                    onPressed: () {
                      if (_currentPage < 2) {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        _finish();
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentPage == 2 ? 'Get Started' : 'Next',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
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

// ─── Slide 1: Secure Transfer ─────────────────────────────────────────────────

class _SlideSecureTransfer extends StatelessWidget {
  const _SlideSecureTransfer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 1),

          // Illustration card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                // Lock icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  'ACTIVE SECURITY SESSION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 20),

                // Code display
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      '8 F T Y 3 X',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8,
                        color: AppColors.primaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Timer row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: AppColors.primary.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Expires in ',
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    const _CountdownTimer(
                      startMinutes: 8,
                      startSeconds: 42,
                    ),
               
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Transfer ready badge
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transfer Ready',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        'Encrypted stream open',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const Spacer(flex: 1),

          // Title + subtitle
          const Text(
            'Secure\nShort-Code Sharing',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.5,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Ephemeral 6-digit codes that rotate\nautomatically. No accounts needed.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),

          const Spacer(flex: 1),
        ],
      ),
    );
  }
}

// ─── Slide 2: Select Assets ───────────────────────────────────────────────────

class _SlideSelectAssets extends StatefulWidget {
  const _SlideSelectAssets();

  @override
  State<_SlideSelectAssets> createState() => _SlideSelectAssetsState();
}

class _SlideSelectAssetsState extends State<_SlideSelectAssets> {
  int _activeTab = 0;

  static const _tabs = ['Images', 'Videos', 'Audio', 'Documents'];

  static const _tabIcons = [
    Icons.image_rounded,
    Icons.videocam_rounded,
    Icons.headphones_rounded,
    Icons.description_rounded,
  ];

  static const _gridData = <List<_ThumbItem>>[
    // Images
    [
      _ThumbItem(Color(0xFF5C6BC0), Icons.camera_alt_rounded, true),
      _ThumbItem(Color(0xFF2E7D32), Icons.forest_rounded, true),
      _ThumbItem(Color(0xFF00838F), Icons.waves_rounded, false),
      _ThumbItem(Color(0xFFBF360C), Icons.landscape_rounded, true),
      _ThumbItem(Color(0xFF4527A0), Icons.filter_hdr_rounded, false),
      _ThumbItem(Color(0xFF37474F), Icons.photo_rounded, false),
    ],
    // Videos
    [
      _ThumbItem(Color(0xFFC62828), Icons.movie_rounded, true),
      _ThumbItem(Color(0xFF1565C0), Icons.slow_motion_video_rounded, false),
      _ThumbItem(Color(0xFF2E7D32), Icons.videocam_rounded, true),
      _ThumbItem(Color(0xFF6A1B9A), Icons.animation_rounded, false),
      _ThumbItem(Color(0xFFE65100), Icons.play_circle_rounded, true),
      _ThumbItem(Color(0xFF00695C), Icons.video_library_rounded, false),
    ],
    // Audio
    [
      _ThumbItem(Color(0xFFAD1457), Icons.music_note_rounded, true),
      _ThumbItem(Color(0xFF283593), Icons.audiotrack_rounded, false),
      _ThumbItem(Color(0xFF00695C), Icons.mic_rounded, true),
      _ThumbItem(Color(0xFFE65100), Icons.graphic_eq_rounded, false),
      _ThumbItem(Color(0xFF4527A0), Icons.headset_rounded, false),
      _ThumbItem(Color(0xFF1B5E20), Icons.podcasts_rounded, true),
    ],
    // Documents
    [
      _ThumbItem(Color(0xFF1565C0), Icons.picture_as_pdf_rounded, true),
      _ThumbItem(Color(0xFF2E7D32), Icons.table_chart_rounded, false),
      _ThumbItem(Color(0xFF4527A0), Icons.slideshow_rounded, true),
      _ThumbItem(Color(0xFFBF360C), Icons.article_rounded, false),
      _ThumbItem(Color(0xFF00838F), Icons.code_rounded, false),
      _ThumbItem(Color(0xFF37474F), Icons.folder_zip_rounded, true),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final items = _gridData[_activeTab];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 1),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Select Assets',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Tabs
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(_tabs.length, (i) {
                      final isActive = i == _activeTab;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setState(() => _activeTab = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppColors.primary
                                  : AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isActive) ...[
                                  Icon(_tabIcons[i],
                                      size: 14, color: Colors.white),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  _tabs[i],
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isActive
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: isActive
                                        ? Colors.white
                                        : AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 16),

                // Grid
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: GridView.count(
                    key: ValueKey(_activeTab),
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    children: List.generate(items.length, (i) {
                      final item = items[i];
                      return _AssetThumb(
                        color: item.color,
                        icon: item.icon,
                        selected: item.selected,
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(flex: 1),

          const Text(
            'Pick Any\nFile Type Instantly',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.5,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Images, videos, audio, documents —\nselect and send in one tap.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),

          const Spacer(flex: 1),
        ],
      ),
    );
  }
}

class _ThumbItem {
  final Color color;
  final IconData icon;
  final bool selected;
  const _ThumbItem(this.color, this.icon, this.selected);
}

class _AssetThumb extends StatefulWidget {
  final Color color;
  final IconData icon;
  final bool selected;

  const _AssetThumb({
    required this.color,
    required this.icon,
    required this.selected,
  });

  @override
  State<_AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<_AssetThumb> {
  late bool _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selected;
  }

  @override
  void didUpdateWidget(_AssetThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _selected = widget.selected;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _selected = !_selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: _selected
              ? Border.all(color: AppColors.primary, width: 2.5)
              : Border.all(color: Colors.transparent, width: 2.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              widget.color,
              widget.color.withValues(alpha: 0.65),
            ],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(
                widget.icon,
                size: 28,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _selected ? AppColors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _selected
                        ? AppColors.primary
                        : Colors.white.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: _selected
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Slide 3: Features ────────────────────────────────────────────────────────

class _SlideFeatures extends StatelessWidget {
  const _SlideFeatures();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),

          // Label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'NEW STANDARD',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          RichText(
            textAlign: TextAlign.center,
            text: const TextSpan(
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.2,
                letterSpacing: -0.5,
                color: AppColors.onSurface,
              ),
              children: [
                TextSpan(text: 'Experience frictionless\n'),
                TextSpan(
                  text: 'digital sovereignty.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Feature rows
          _FeatureRow(
            icon: Icons.person_off_rounded,
            title: 'No Signups Required',
            description:
                'Identity is a burden. Share securely without accounts, passwords, or persistent tracking.',
          ),
          const SizedBox(height: 24),
          _FeatureRow(
            icon: Icons.pin_rounded,
            title: 'Secure Short-Codes',
            description:
                'Our 6-digit liquid codes are ephemeral, rotating automatically to ensure your bridge is always fresh.',
          ),
          const SizedBox(height: 24),
          _FeatureRow(
            icon: Icons.devices_rounded,
            title: 'Cross-Device Magic',
            description:
                'Desktop to mobile, or screen to screen. Movement so fluid, it feels like an extension of your mind.',
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 22,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Countdown Timer ──────────────────────────────────────────────────────────

class _CountdownTimer extends StatefulWidget {
  final int startMinutes;
  final int startSeconds;

  const _CountdownTimer({
    required this.startMinutes,
    required this.startSeconds,
  });

  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.startMinutes * 60 + widget.startSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining > 0) {
        setState(() => _remaining--);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mins = (_remaining ~/ 60).toString().padLeft(2, '0');
    final secs = (_remaining % 60).toString().padLeft(2, '0');
    return Text(
      '$mins:${secs}s',
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
    );
  }
}
