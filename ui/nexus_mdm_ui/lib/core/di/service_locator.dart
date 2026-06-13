import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
import '../network/websocket_client.dart';

final GetIt sl = GetIt.instance;

Future<void> setupServiceLocator() async {
  // External
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerSingleton<SharedPreferences>(sharedPreferences);

  // Network
  sl.registerLazySingleton<ApiClient>(() => ApiClient());
  sl.registerLazySingleton<WebSocketClient>(() => WebSocketClient());

  // Services would be registered here when implemented
  // sl.registerLazySingleton<AuthService>(() => AuthService(sl<ApiClient>()));
  // sl.registerLazySingleton<EntityService>(() => EntityService(sl<ApiClient>()));
  // sl.registerLazySingleton<MatchService>(() => MatchService(sl<ApiClient>()));
}
