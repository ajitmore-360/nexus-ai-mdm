import '../network/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LicenseTierInfo
// ─────────────────────────────────────────────────────────────────────────────

class LicenseTierInfo {
  final String tier;          // 'essentials' | 'professional' | 'enterprise'
  final String status;        // 'active' | 'suspended' | 'expired' | 'trial'
  final int maxDomains;       // -1 = unlimited
  final int maxRecords;       // -1 = unlimited
  final int maxStewards;      // -1 = unlimited
  final Map<String, bool> features;
  final DateTime? expiresAt;

  const LicenseTierInfo({
    required this.tier,
    required this.status,
    required this.maxDomains,
    required this.maxRecords,
    required this.maxStewards,
    required this.features,
    this.expiresAt,
  });

  factory LicenseTierInfo.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['features'] as Map<String, dynamic>? ?? {};
    return LicenseTierInfo(
      tier:        json['tier'] as String? ?? 'essentials',
      status:      json['status'] as String? ?? 'active',
      maxDomains:  json['max_domains'] as int? ?? 1,
      maxRecords:  json['max_records'] as int? ?? 500000,
      maxStewards: json['max_stewards'] as int? ?? 5,
      features:    rawFeatures.map((k, v) => MapEntry(k, v == true)),
      expiresAt:   json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
    );
  }

  bool hasFeature(String key) => features[key] == true;

  bool get isEnterprise   => tier == 'enterprise';
  bool get isProfessional => tier == 'professional' || tier == 'enterprise';
  bool get isEssentials   => true; // always true

  String get tierLabel =>
      tier.isNotEmpty ? tier[0].toUpperCase() + tier.substring(1) : tier;
}

// ─────────────────────────────────────────────────────────────────────────────
// UsageInfo
// ─────────────────────────────────────────────────────────────────────────────

class UsageInfo {
  final int goldenRecords;
  final int activeDomains;
  final int activeStewards;

  const UsageInfo({
    required this.goldenRecords,
    required this.activeDomains,
    required this.activeStewards,
  });

  factory UsageInfo.fromJson(Map<String, dynamic> json) {
    return UsageInfo(
      goldenRecords:  json['golden_records'] as int? ?? 0,
      activeDomains:  json['active_domains'] as int? ?? 0,
      activeStewards: json['active_stewards'] as int? ?? 0,
    );
  }

  double recordsUsageRatio(int maxRecords) =>
      maxRecords == -1 ? 0.0 : goldenRecords / maxRecords;

  double domainsUsageRatio(int maxDomains) =>
      maxDomains == -1 ? 0.0 : activeDomains / maxDomains;

  double stewardsUsageRatio(int maxStewards) =>
      maxStewards == -1 ? 0.0 : activeStewards / maxStewards;
}

// ─────────────────────────────────────────────────────────────────────────────
// LicenseRepository
// ─────────────────────────────────────────────────────────────────────────────

class LicenseRepository {
  final ApiClient _client;

  LicenseRepository({required ApiClient client}) : _client = client;

  /// Fetches the tenant's license and current usage from the server.
  Future<(LicenseTierInfo, UsageInfo)> getMyLicense() async {
    final resp = await _client.get<Map<String, dynamic>>('/v1/license');
    final data = resp.data!;
    return (
      LicenseTierInfo.fromJson(data['license'] as Map<String, dynamic>),
      UsageInfo.fromJson(data['usage'] as Map<String, dynamic>),
    );
  }

  /// Validates [key] server-side and activates the corresponding license tier
  /// for the current tenant. Returns the activated [LicenseTierInfo] on success.
  /// Throws a [LicenseActivationException] with a user-facing message on failure.
  Future<LicenseTierInfo> activateLicenseKey(String key) async {
    final resp = await _client.post<Map<String, dynamic>>(
      '/v1/license/activate',
      data: {'key': key.trim()},
    );
    final data = resp.data!;
    if (data['success'] != true) {
      throw LicenseActivationException(
        data['error'] as String? ?? 'License key rejected by server.',
      );
    }
    // Reload the full license after activation so we get all fields.
    return (await getMyLicense()).$1;
  }
}

class LicenseActivationException implements Exception {
  final String message;
  const LicenseActivationException(this.message);
  @override
  String toString() => message;
}
