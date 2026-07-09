import 'package:equatable/equatable.dart';

enum UserRole {
  productAdmin,  // AZILE platform staff â€” bypasses all license checks
  admin,         // Tenant administrator â€” full access within tenant
  businessAdmin, // Business administrator â€” org setup + data governance; no direct data entry
  steward,       // Data steward â€” entity CRUD, merges, match approvals
  analyst,       // Data analyst â€” match jobs and analytics
  viewer,        // Read-only
}

// Maps backend role strings (snake_case) to Flutter enum values.
UserRole _parseRole(String role) {
  switch (role) {
    case 'super_admin':    return UserRole.productAdmin;
    case 'admin':          return UserRole.admin;
    case 'business_admin': return UserRole.businessAdmin;
    case 'steward':        return UserRole.steward;
    case 'analyst':        return UserRole.analyst;
    case 'viewer':         return UserRole.viewer;
    default:               return UserRole.viewer;
  }
}

class User extends Equatable {
  final String id;
  final String email;
  final String name;
  final String? avatarUrl;
  final UserRole role;
  final String tenantId;
  final String tenantName;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final bool isActive;
  final Map<String, dynamic> preferences;

  const User({
    required this.id,
    required this.email,
    required this.name,
    this.avatarUrl,
    required this.role,
    required this.tenantId,
    required this.tenantName,
    required this.createdAt,
    this.lastLoginAt,
    this.isActive = true,
    this.preferences = const {},
  });

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  String get roleDisplayName {
    switch (role) {
      case UserRole.productAdmin:  return 'Product Admin';
      case UserRole.admin:         return 'Administrator';
      case UserRole.businessAdmin: return 'Business Admin';
      case UserRole.steward:       return 'Data Steward';
      case UserRole.analyst:       return 'Data Analyst';
      case UserRole.viewer:        return 'Viewer';
    }
  }

  bool get isProductAdmin    => role == UserRole.productAdmin;

  /// Can create / edit entity records directly.
  bool get canEdit  => role == UserRole.productAdmin || role == UserRole.admin || role == UserRole.steward;

  /// Can perform entity merges.
  bool get canMerge => role == UserRole.productAdmin || role == UserRole.admin || role == UserRole.steward;

  /// Can approve or reject match candidates (governance oversight).
  bool get canApprove =>
      role == UserRole.productAdmin ||
      role == UserRole.admin        ||
      role == UserRole.businessAdmin||
      role == UserRole.steward;

  /// Can access org setup: user management, entity types, source systems, policies.
  bool get canManageSettings =>
      role == UserRole.productAdmin ||
      role == UserRole.admin        ||
      role == UserRole.businessAdmin;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      role: _parseRole(json['role'] as String? ?? 'viewer'),
      tenantId: json['tenant_id'] as String,
      tenantName: json['tenant_name'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? true,
      preferences:
          json['preferences'] as Map<String, dynamic>? ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'avatar_url': avatarUrl,
        'role': role.name,
        'tenant_id': tenantId,
        'tenant_name': tenantName,
        'created_at': createdAt.toIso8601String(),
        'last_login_at': lastLoginAt?.toIso8601String(),
        'is_active': isActive,
        'preferences': preferences,
      };

  User copyWith({
    String? id,
    String? email,
    String? name,
    String? avatarUrl,
    UserRole? role,
    String? tenantId,
    String? tenantName,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    bool? isActive,
    Map<String, dynamic>? preferences,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      tenantId: tenantId ?? this.tenantId,
      tenantName: tenantName ?? this.tenantName,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      isActive: isActive ?? this.isActive,
      preferences: preferences ?? this.preferences,
    );
  }

  static User get demo => User(
        id: 'demo-user-001',
        email: 'admin@azilemdm.io',
        name: 'Alex Chen',
        role: UserRole.admin,
        tenantId: 'tenant-001',
        tenantName: 'Azile Demo Org',
        createdAt: DateTime(2024, 1, 15),
        lastLoginAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

  @override
  List<Object?> get props => [
        id,
        email,
        name,
        avatarUrl,
        role,
        tenantId,
        tenantName,
        createdAt,
        lastLoginAt,
        isActive,
      ];
}
