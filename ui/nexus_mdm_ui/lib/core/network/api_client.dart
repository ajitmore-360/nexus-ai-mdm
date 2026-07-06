import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../auth/auth_manager.dart';
import '../constants/app_constants.dart';
import '../security/secure_storage.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout:
          const Duration(milliseconds: AppConstants.connectTimeout),
      receiveTimeout:
          const Duration(milliseconds: AppConstants.receiveTimeout),
      sendTimeout:
          const Duration(milliseconds: AppConstants.sendTimeout),
      headers: {
        'Content-Type': AppConstants.contentTypeJson,
        'Accept': AppConstants.contentTypeJson,
      },
    ));

    _setupInterceptors();
  }

  void _setupInterceptors() {
    _dio.interceptors.addAll([
      _AuthInterceptor(),
      _LoggingInterceptor(),
      _RetryInterceptor(dio: _dio),
    ]);
  }

  Dio get dio => _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    return _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  void updateBaseUrl(String baseUrl) {
    _dio.options.baseUrl = baseUrl;
  }

  void setAuthToken(String token) {
    _dio.options.headers[AppConstants.authHeaderKey] =
        '${AppConstants.authHeaderPrefix}$token';
  }

  void setTenantId(String tenantId) {
    _dio.options.headers[AppConstants.tenantHeaderKey] = tenantId;
  }

  void clearAuth() {
    _dio.options.headers.remove(AppConstants.authHeaderKey);
    _dio.options.headers.remove(AppConstants.tenantHeaderKey);
  }
}

/// Injects auth token and tenant ID from encrypted secure storage on every request.
/// Uses [SecureStorage] (Keychain/Keystore) — never plaintext SharedPreferences.
class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // Auth token — read independently so a storage failure here does not
    // prevent the tenant header from being set below.
    try {
      final token = await SecureStorage.read(AppConstants.storageAccessToken);
      if (token != null && token.isNotEmpty) {
        options.headers[AppConstants.authHeaderKey] =
            '${AppConstants.authHeaderPrefix}$token';
      }
    } catch (_) {}

    // Tenant ID — read from secure storage; omit header when absent so the
    // backend correctly returns 401 rather than routing to the demo tenant.
    try {
      final tenantId = await AuthManager.getTenantId();
      if (tenantId != null && tenantId.isNotEmpty) {
        options.headers[AppConstants.tenantHeaderKey] = tenantId;
      }
    } catch (_) {}

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // Token expired — attempt silent refresh using secure-stored refresh token
      try {
        final refreshToken = await SecureStorage.read(AppConstants.storageRefreshToken);
        if (refreshToken != null && refreshToken.isNotEmpty) {
          final dio = Dio(BaseOptions(baseUrl: AppConstants.baseUrl));
          final response = await dio.post(
            AppConstants.refreshTokenPath,
            data: {'refresh_token': refreshToken},
          );
          final data = response.data['data'] as Map<String, dynamic>?
              ?? response.data as Map<String, dynamic>? ?? {};
          final newToken    = data['access_token']  as String?;
          final newRefresh  = data['refresh_token'] as String?;
          if (newToken != null) {
            await SecureStorage.write(AppConstants.storageAccessToken, newToken);
            // Persist the rotated refresh token so the next silent refresh works.
            if (newRefresh != null && newRefresh.isNotEmpty) {
              await SecureStorage.write(AppConstants.storageRefreshToken, newRefresh);
            }
            err.requestOptions.headers[AppConstants.authHeaderKey] =
                '${AppConstants.authHeaderPrefix}$newToken';
            final clonedRequest = await Dio().fetch(err.requestOptions);
            return handler.resolve(clonedRequest);
          }
        }
      } catch (_) {
        // Refresh failed — clear all auth tokens then kick user to login.
        await SecureStorage.clearAuth();
        AuthManager.onUnauthorized?.call();
        return; // don't propagate — the redirect will rebuild the widget tree
      }
    }
    handler.next(err);
  }
}

class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) {
    assert(() {
      debugPrint('[API] ${options.method} ${options.uri}');
      debugPrint('[API HEADERS] ${options.headers}');
      return true;
    }());
    handler.next(options);
  }

  @override
  void onResponse(
      Response response, ResponseInterceptorHandler handler) {
    assert(() {
      debugPrint(
          '[API] ${response.statusCode} ${response.requestOptions.path}');
      return true;
    }());
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    assert(() {
      debugPrint(
          '[API ERROR] ${err.response?.statusCode} ${err.requestOptions.path}: ${err.message}');
      return true;
    }());
    handler.next(err);
  }
}

class _RetryInterceptor extends Interceptor {
  final Dio dio;
  static const int maxRetries = 3;
  static const List<int> retryStatusCodes = [500, 502, 503, 504];

  _RetryInterceptor({required this.dio});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;
    final retryCount = extra['retry_count'] as int? ?? 0;

    if (retryCount < maxRetries &&
        (err.type == DioExceptionType.connectionError ||
            err.type == DioExceptionType.receiveTimeout ||
            (err.response?.statusCode != null &&
                retryStatusCodes
                    .contains(err.response!.statusCode)))) {
      err.requestOptions.extra['retry_count'] = retryCount + 1;
      await Future.delayed(
          Duration(milliseconds: 300 * (retryCount + 1)));
      try {
        final response = await dio.fetch(err.requestOptions);
        return handler.resolve(response);
      } catch (e) {
        return handler.next(err);
      }
    }
    handler.next(err);
  }
}

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final dynamic data;

  const ApiException({
    this.statusCode,
    required this.message,
    this.data,
  });

  factory ApiException.fromDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    String message;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        message = 'Connection timeout. Please check your network.';
        break;
      case DioExceptionType.receiveTimeout:
        message = 'Request timed out. Please try again.';
        break;
      case DioExceptionType.sendTimeout:
        message = 'Failed to send request. Please try again.';
        break;
      case DioExceptionType.badResponse:
        message = e.response?.data?['message'] as String? ??
            e.response?.data?['error'] as String? ??
            'Server error: $statusCode';
        break;
      case DioExceptionType.connectionError:
        message =
            'Cannot connect to server. Please check your network connection.';
        break;
      case DioExceptionType.cancel:
        message = 'Request cancelled.';
        break;
      default:
        message = e.message ?? 'An unexpected error occurred.';
    }

    return ApiException(
      statusCode: statusCode,
      message: message,
      data: e.response?.data,
    );
  }

  @override
  String toString() =>
      'ApiException(statusCode: $statusCode, message: $message)';
}
