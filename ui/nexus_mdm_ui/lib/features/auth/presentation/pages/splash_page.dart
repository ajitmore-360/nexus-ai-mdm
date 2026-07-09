import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/auth/auth_manager.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/azile_logo.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );
    _progressController.forward();
    _startNavigation();
  }

  Future<void> _startNavigation() async {
    await Future.delayed(AppConstants.splashDuration);
    if (!mounted || _isNavigating) return;
    _isNavigating = true;

    bool loggedIn = false;
    try {
      loggedIn = await AuthManager.isLoggedIn();
    } catch (e) {
      debugPrint('AZILE SPLASH ERROR: $e');
    }

    if (!mounted) return;
    if (loggedIn) {
      context.go('/dashboard');
    } else {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyBackground,
      body: Stack(
        children: [
          // Subtle floating node network — sage-tinted
          const AnimatedGraphBackground(
            nodeCount: 20,
            color: AppColors.primary,
            opacity: 0.07,
          ),

          // Radial sage glow from center
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  Color(0x28599B81),  // brand sage at ~16%
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Center content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo lockup: mark | rule | wordmark ──────────────────
                const _SplashLockup()
                    .animate()
                    .fadeIn(duration: const Duration(milliseconds: 500))
                    .slideY(
                      begin: 0.18,
                      end: 0,
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOut,
                    ),

                const SizedBox(height: 40),

                // Tagline
                Text(
                  'Your data. Unified. Trusted.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w300,
                  ),
                )
                    .animate(delay: const Duration(milliseconds: 600))
                    .fadeIn(duration: const Duration(milliseconds: 600)),

                const SizedBox(height: 72),

                // Loading bar
                AnimatedBuilder(
                  animation: _progressAnimation,
                  builder: (context, child) {
                    return Column(
                      children: [
                        SizedBox(
                          width: 196,
                          height: 1.5,
                          child: Stack(
                            children: [
                              Container(color: AppColors.divider),
                              FractionallySizedBox(
                                widthFactor: _progressAnimation.value,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.45),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _loadingMessage(_progressAnimation.value),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.mutedText,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    );
                  },
                )
                    .animate(delay: const Duration(milliseconds: 700))
                    .fadeIn(duration: const Duration(milliseconds: 400)),
              ],
            ),
          ),

          // Version
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Text(
              'v${AppConstants.appVersion}',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.mutedText.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            )
                .animate(delay: const Duration(milliseconds: 900))
                .fadeIn(duration: const Duration(milliseconds: 400)),
          ),
        ],
      ),
    );
  }

  String _loadingMessage(double progress) {
    if (progress < 0.33) return 'Initializing AI engines...';
    if (progress < 0.66) return 'Loading data connections...';
    if (progress < 0.90) return 'Preparing your workspace...';
    return 'Almost ready...';
  }
}

// ── Splash lockup: mark | vertical rule | wordmark ──────────────────────────
//
// Mirrors the HTML splash screen design: geometric A mark on the left,
// a thin fading vertical rule as a separator, the AZILE wordmark on the right.
// "A" is rendered in brand sage; "ZILE" in off-white light weight.
// ─────────────────────────────────────────────────────────────────────────────

class _SplashLockup extends StatelessWidget {
  const _SplashLockup();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Mark only — animates in, then apex pulses
        const AzileLogo(
          size: 72,
          showText: false,
          animateIn: true,
          shouldPulse: true,
        ),

        // Vertical rule
        Container(
          width: 1,
          height: 52,
          margin: const EdgeInsets.symmetric(horizontal: 22),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Color(0x44599B81),  // sage at 27%
                Color(0x44599B81),
                Colors.transparent,
              ],
              stops: [0.0, 0.3, 0.7, 1.0],
            ),
          ),
        )
            .animate(delay: const Duration(milliseconds: 300))
            .fadeIn(duration: const Duration(milliseconds: 400)),

        // Wordmark: "A" + "ZILE" + subtitle
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'A',
                    style: AppTextStyles.displaySmall.copyWith(
                      color: AppColors.primary,
                      letterSpacing: 9,
                      fontSize: 48,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                  TextSpan(
                    text: 'ZILE',
                    style: AppTextStyles.displaySmall.copyWith(
                      color: AppColors.primaryText,
                      letterSpacing: 9,
                      fontSize: 48,
                      fontWeight: FontWeight.w300,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'AI · MASTER DATA MANAGEMENT',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.secondaryText,
                letterSpacing: 4.2,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        )
            .animate(delay: const Duration(milliseconds: 400))
            .fadeIn(duration: const Duration(milliseconds: 500))
            .slideX(
              begin: 0.12,
              end: 0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
            ),
      ],
    );
  }
}
