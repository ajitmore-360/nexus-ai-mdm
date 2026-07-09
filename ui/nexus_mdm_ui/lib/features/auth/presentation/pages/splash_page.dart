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
      duration: const Duration(milliseconds: 2000),
    );
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _progressController, curve: Curves.easeInOut),
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
          // Animated graph background
          const AnimatedGraphBackground(
            nodeCount: 25,
            opacity: 0.08,
          ),

          // Radial gradient overlay
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  Color(0x3000C896),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                const AzileLogo(
                  size: 80,
                  shouldPulse: true,
                )
                    .animate()
                    .fadeIn(duration: const Duration(milliseconds: 600))
                    .scaleXY(
                        begin: 0.6,
                        end: 1.0,
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.elasticOut),

                const SizedBox(height: 48),

                // Tagline
                Text(
                  AppConstants.appTagline,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.secondaryText,
                    letterSpacing: 0.5,
                  ),
                )
                    .animate(delay: const Duration(milliseconds: 400))
                    .fadeIn(duration: const Duration(milliseconds: 600)),

                const SizedBox(height: 64),

                // Loading bar
                AnimatedBuilder(
                  animation: _progressAnimation,
                  builder: (context, child) {
                    return Column(
                      children: [
                        SizedBox(
                          width: 200,
                          height: 3,
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.divider,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: _progressAnimation.value,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    borderRadius: BorderRadius.circular(2),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            AppColors.primary.withValues(alpha:0.5),
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
                          _getLoadingMessage(_progressAnimation.value),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.mutedText,
                          ),
                        ),
                      ],
                    );
                  },
                )
                    .animate(delay: const Duration(milliseconds: 500))
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
                color: AppColors.mutedText.withValues(alpha:0.6),
              ),
              textAlign: TextAlign.center,
            )
                .animate(delay: const Duration(milliseconds: 800))
                .fadeIn(duration: const Duration(milliseconds: 400)),
          ),
        ],
      ),
    );
  }

  String _getLoadingMessage(double progress) {
    if (progress < 0.33) return 'Initializing AI engines...';
    if (progress < 0.66) return 'Loading data connections...';
    if (progress < 0.9) return 'Preparing your workspace...';
    return 'Almost ready...';
  }
}
