import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:get_it/get_it.dart';
import 'core/auth/auth_manager.dart';
import 'core/branding/branding_manager.dart';
import 'core/network/api_client.dart';
import 'core/router/app_router.dart';
import 'core/di/service_locator.dart';

void main() {
  // Use clean path-based URLs (no # hash) so deep links like /activate?token=xxx work.
  usePathUrlStrategy();
  runZonedGuarded(_main, (error, stack) {
    debugPrint('NEXUS FATAL: $error\n$stack');
  });
}

Future<void> _main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('NEXUS: binding ready');

  FlutterError.onError = (details) {
    debugPrint('NEXUS FLUTTER ERROR: ${details.exceptionAsString()}');
    debugPrint(details.stack.toString());
  };

  // setPreferredOrientations is a no-op on web; skip to avoid plugin errors
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0A1628),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  // Initialize service locator
  debugPrint('NEXUS: starting service locator');
  try {
    await setupServiceLocator()
        .timeout(const Duration(seconds: 10), onTimeout: () {
      debugPrint('NEXUS WARNING: setupServiceLocator timed out after 10s');
    });
  } catch (e) {
    debugPrint('NEXUS ERROR: setupServiceLocator failed: $e');
  }
  debugPrint('NEXUS: service locator ready, calling runApp');

  // When a token refresh fails, clear auth and send the user back to login.
  AuthManager.onUnauthorized = () => AppRouter.router.go('/login');

  // Pre-populate auth headers from storage so the first API call after a
  // page refresh has the correct Authorization and X-Tenant-ID headers
  // without relying solely on the async interceptor.
  try {
    final token    = await AuthManager.getToken();
    final tenantId = await AuthManager.getTenantId();
    final client   = GetIt.instance<ApiClient>();
    if (token != null && token.isNotEmpty) {
      client.setAuthToken(token);
    }
    if (tenantId != null && tenantId.isNotEmpty) {
      client.setTenantId(tenantId);
    }
  } catch (e) {
    debugPrint('NEXUS: could not pre-populate auth headers: $e');
  }

  // Enable hot-reload restart of animations during development
  Animate.restartOnHotReload = true;

  runApp(const NexusMdmApp());
  debugPrint('NEXUS: runApp complete');
}

class NexusMdmApp extends StatelessWidget {
  const NexusMdmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeData>(
      valueListenable: BrandingManager.themeNotifier,
      builder: (context, theme, _) => MaterialApp.router(
        title: BrandingManager.productName,
        debugShowCheckedModeBanner: false,
        theme: theme,
        darkTheme: theme,
        themeMode: ThemeMode.dark,
        routerConfig: AppRouter.router,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.4),
              ),
            ),
            child: child!,
          );
        },
      ),
    );
  }
}
