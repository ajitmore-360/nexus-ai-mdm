import 'package:flutter/material.dart';
import '../network/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class TenantBranding {
  final String? productName;
  final String? logoUrl;
  final String? faviconUrl;
  final Color? primaryColor;
  final Color? accentColor;
  final String? supportEmail;
  final String? supportUrl;

  const TenantBranding({
    this.productName,
    this.logoUrl,
    this.faviconUrl,
    this.primaryColor,
    this.accentColor,
    this.supportEmail,
    this.supportUrl,
  });

  factory TenantBranding.fromJson(Map<String, dynamic> json) {
    return TenantBranding(
      productName:  json['product_name'] as String?,
      logoUrl:      json['logo_url'] as String?,
      faviconUrl:   json['favicon_url'] as String?,
      primaryColor: _parseHex(json['primary_color'] as String?),
      accentColor:  _parseHex(json['accent_color'] as String?),
      supportEmail: json['support_email'] as String?,
      supportUrl:   json['support_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (productName != null)  'product_name':  productName,
    if (logoUrl != null)      'logo_url':       logoUrl,
    if (faviconUrl != null)   'favicon_url':    faviconUrl,
    if (primaryColor != null) 'primary_color':  _toHex(primaryColor!),
    if (accentColor != null)  'accent_color':   _toHex(accentColor!),
    if (supportEmail != null) 'support_email':  supportEmail,
    if (supportUrl != null)   'support_url':    supportUrl,
  };

  static Color? _parseHex(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final clean = hex.replaceFirst('#', '').trim();
    if (clean.length != 6) return null;
    final value = int.tryParse(clean, radix: 16);
    if (value == null) return null;
    return Color.fromARGB(255, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF);
  }

  static String _toHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Repository
// ─────────────────────────────────────────────────────────────────────────────

class BrandingRepository {
  final ApiClient _client;

  BrandingRepository({required ApiClient client}) : _client = client;

  Future<TenantBranding?> getBranding() async {
    try {
      final resp = await _client.get<Map<String, dynamic>>('/v1/tenant/branding');
      final data = resp.data;
      if (data == null) return null;
      return TenantBranding.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<TenantBranding> upsertBranding(TenantBranding branding) async {
    final resp = await _client.put<Map<String, dynamic>>(
      '/v1/tenant/branding',
      data: branding.toJson(),
    );
    return TenantBranding.fromJson(resp.data!);
  }
}
