import 'package:equatable/equatable.dart';

enum TenantPlan {
  starter,
  professional,
  enterprise,
  unlimited,
}

class TenantLimits extends Equatable {
  final int maxEntities;
  final int maxUsers;
  final int maxSources;
  final int maxApiCallsPerDay;
  final bool aiPrismEnabled;
  final bool advancedAnalyticsEnabled;
  final bool customRulesEnabled;

  const TenantLimits({
    required this.maxEntities,
    required this.maxUsers,
    required this.maxSources,
    required this.maxApiCallsPerDay,
    required this.aiPrismEnabled,
    required this.advancedAnalyticsEnabled,
    required this.customRulesEnabled,
  });

  factory TenantLimits.fromJson(Map<String, dynamic> json) => TenantLimits(
        maxEntities: json['max_entities'] as int,
        maxUsers: json['max_users'] as int,
        maxSources: json['max_sources'] as int,
        maxApiCallsPerDay: json['max_api_calls_per_day'] as int,
        aiPrismEnabled: json['ai_copilot_enabled'] as bool? ?? false,
        advancedAnalyticsEnabled:
            json['advanced_analytics_enabled'] as bool? ?? false,
        customRulesEnabled:
            json['custom_rules_enabled'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'max_entities': maxEntities,
        'max_users': maxUsers,
        'max_sources': maxSources,
        'max_api_calls_per_day': maxApiCallsPerDay,
        'ai_copilot_enabled': aiPrismEnabled,
        'advanced_analytics_enabled': advancedAnalyticsEnabled,
        'custom_rules_enabled': customRulesEnabled,
      };

  @override
  List<Object?> get props => [maxEntities, maxUsers, maxSources];
}

class Tenant extends Equatable {
  final String id;
  final String name;
  final String slug;
  final String? logoUrl;
  final TenantPlan plan;
  final TenantLimits limits;
  final bool isActive;
  final DateTime createdAt;
  final int currentEntityCount;
  final int currentUserCount;
  final Map<String, dynamic> settings;

  const Tenant({
    required this.id,
    required this.name,
    required this.slug,
    this.logoUrl,
    required this.plan,
    required this.limits,
    required this.isActive,
    required this.createdAt,
    required this.currentEntityCount,
    required this.currentUserCount,
    this.settings = const {},
  });

  String get planDisplayName {
    switch (plan) {
      case TenantPlan.starter:
        return 'Starter';
      case TenantPlan.professional:
        return 'Professional';
      case TenantPlan.enterprise:
        return 'Enterprise';
      case TenantPlan.unlimited:
        return 'Unlimited';
    }
  }

  double get entityUsagePercent =>
      currentEntityCount / limits.maxEntities;

  factory Tenant.fromJson(Map<String, dynamic> json) => Tenant(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        logoUrl: json['logo_url'] as String?,
        plan: TenantPlan.values.firstWhere(
          (p) => p.name == (json['plan'] as String? ?? 'professional'),
          orElse: () => TenantPlan.professional,
        ),
        limits: TenantLimits.fromJson(
            json['limits'] as Map<String, dynamic>),
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
        currentEntityCount: json['current_entity_count'] as int? ?? 0,
        currentUserCount: json['current_user_count'] as int? ?? 0,
        settings:
            json['settings'] as Map<String, dynamic>? ?? const {},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'logo_url': logoUrl,
        'plan': plan.name,
        'limits': limits.toJson(),
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'current_entity_count': currentEntityCount,
        'current_user_count': currentUserCount,
        'settings': settings,
      };

  static Tenant get demo => Tenant(
        id: 'tenant-001',
        name: 'Azile Demo Org',
        slug: 'azile-demo',
        plan: TenantPlan.enterprise,
        limits: const TenantLimits(
          maxEntities: 1000000,
          maxUsers: 50,
          maxSources: 20,
          maxApiCallsPerDay: 500000,
          aiPrismEnabled: true,
          advancedAnalyticsEnabled: true,
          customRulesEnabled: true,
        ),
        isActive: true,
        createdAt: DateTime(2023, 6, 1),
        currentEntityCount: 247583,
        currentUserCount: 12,
      );

  @override
  List<Object?> get props => [id, name, slug, plan, isActive];
}
