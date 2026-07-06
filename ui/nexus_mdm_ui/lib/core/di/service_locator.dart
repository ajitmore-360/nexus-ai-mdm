import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../branding/branding_manager.dart';
import '../license/license_manager.dart';
import '../network/api_client.dart';
import '../network/websocket_client.dart';
import '../../features/entities/data/entity_repository.dart';
import '../../features/match_queue/data/match_repository.dart';
import '../../features/golden_records/data/golden_records_repository.dart';
import '../../features/distribution/data/distribution_repository.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../features/admin/data/admin_repository.dart';
import '../../features/admin/data/entity_type_repository.dart';
import '../../features/admin/data/source_systems_repository.dart';
import '../../features/analytics/data/analytics_repository.dart';

final GetIt sl = GetIt.instance;

Future<void> setupServiceLocator() async {
  // External — idempotent so hot-restart doesn't crash with duplicate registration
  if (!sl.isRegistered<SharedPreferences>()) {
    final sharedPreferences = await SharedPreferences.getInstance();
    sl.registerSingleton<SharedPreferences>(sharedPreferences);
  }

  // Network
  if (!sl.isRegistered<ApiClient>()) {
    sl.registerLazySingleton<ApiClient>(() => ApiClient());
  }

  // Static managers that need an ApiClient — safe to call multiple times
  // (both are idempotent: they just replace the repository reference).
  final client = sl<ApiClient>();
  LicenseManager.init(client);
  BrandingManager.init(client);

  if (!sl.isRegistered<WebSocketClient>()) {
    sl.registerLazySingleton<WebSocketClient>(() => WebSocketClient());
  }

  // Repositories
  if (!sl.isRegistered<EntityRepository>()) {
    sl.registerLazySingleton<EntityRepository>(() => EntityRepository(sl<ApiClient>()));
  }
  if (!sl.isRegistered<MatchRepository>()) {
    sl.registerLazySingleton<MatchRepository>(() => MatchRepository(sl<ApiClient>()));
  }
  if (!sl.isRegistered<GoldenRecordsRepository>()) {
    sl.registerLazySingleton<GoldenRecordsRepository>(
        () => GoldenRecordsRepository(sl<ApiClient>()));
  }
  if (!sl.isRegistered<DistributionRepository>()) {
    sl.registerLazySingleton<DistributionRepository>(
        () => DistributionRepository(sl<ApiClient>()));
  }
  if (!sl.isRegistered<DashboardRepository>()) {
    sl.registerLazySingleton<DashboardRepository>(
        () => DashboardRepository(sl<ApiClient>()));
  }
  if (!sl.isRegistered<AdminRepository>()) {
    sl.registerLazySingleton<AdminRepository>(
        () => AdminRepository(sl<ApiClient>()));
  }
  if (!sl.isRegistered<EntityTypeRepository>()) {
    sl.registerLazySingleton<EntityTypeRepository>(
        () => EntityTypeRepository(sl<ApiClient>()));
  }
  if (!sl.isRegistered<SourceSystemsRepository>()) {
    sl.registerLazySingleton<SourceSystemsRepository>(
        () => SourceSystemsRepository(sl<ApiClient>()));
  }
  if (!sl.isRegistered<AnalyticsRepository>()) {
    sl.registerLazySingleton<AnalyticsRepository>(
        () => AnalyticsRepository(sl<ApiClient>()));
  }
}
