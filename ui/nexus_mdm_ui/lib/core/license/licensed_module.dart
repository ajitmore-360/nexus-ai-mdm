import 'package:flutter/material.dart';

enum LicensedModule {
  // Professional tier
  aiCopilot,
  dataQuality,
  analytics,
  governance,
  distribution,
  matchingSemantic,
  relationships,
  domainPolicies,
  // Essentials tier (always on â€” but still a trackable module)
  lineage,
  // Enterprise tier (future)
  whiteLabelBranding,
}

extension LicensedModuleX on LicensedModule {
  String get tier {
    switch (this) {
      case LicensedModule.aiPrism:
      case LicensedModule.dataQuality:
      case LicensedModule.analytics:
      case LicensedModule.governance:
      case LicensedModule.distribution:
      case LicensedModule.matchingSemantic:
      case LicensedModule.relationships:
      case LicensedModule.domainPolicies:
        return 'Professional';
      case LicensedModule.lineage:
        return 'Essentials';
      case LicensedModule.whiteLabelBranding:
        return 'Enterprise';
    }
  }

  IconData get icon {
    switch (this) {
      case LicensedModule.aiPrism:         return Icons.auto_awesome_outlined;
      case LicensedModule.dataQuality:       return Icons.verified_outlined;
      case LicensedModule.analytics:         return Icons.analytics_outlined;
      case LicensedModule.governance:        return Icons.shield_outlined;
      case LicensedModule.distribution:      return Icons.satellite_alt_outlined;
      case LicensedModule.matchingSemantic:  return Icons.psychology_outlined;
      case LicensedModule.relationships:     return Icons.share_outlined;
      case LicensedModule.domainPolicies:    return Icons.tune_outlined;
      case LicensedModule.lineage:           return Icons.account_tree_outlined;
      case LicensedModule.whiteLabelBranding: return Icons.palette_outlined;
    }
  }

  String get displayName {
    switch (this) {
      case LicensedModule.aiPrism:          return 'AI Prism';
      case LicensedModule.dataQuality:        return 'Data Quality';
      case LicensedModule.analytics:          return 'Analytics';
      case LicensedModule.governance:         return 'Governance';
      case LicensedModule.distribution:       return 'Distribution Monitor';
      case LicensedModule.matchingSemantic:   return 'Semantic Matching';
      case LicensedModule.relationships:      return 'Cross-Domain Relationships';
      case LicensedModule.domainPolicies:     return 'Domain Policies';
      case LicensedModule.lineage:            return 'Data Lineage';
      case LicensedModule.whiteLabelBranding: return 'White-Label Branding';
    }
  }

  String get description {
    switch (this) {
      case LicensedModule.aiPrism:
        return 'AI-powered data stewardship recommendations';
      case LicensedModule.dataQuality:
        return 'Advanced data quality rules and scoring';
      case LicensedModule.analytics:
        return 'Usage analytics and match insights';
      case LicensedModule.governance:
        return 'Policy management and compliance workflows';
      case LicensedModule.distribution:
        return 'Multi-system data distribution monitoring';
      case LicensedModule.matchingSemantic:
        return 'Vector-based semantic entity matching';
      case LicensedModule.relationships:
        return 'Cross-domain entity relationship graph';
      case LicensedModule.domainPolicies:
        return 'Per-domain matching policy configuration';
      case LicensedModule.lineage:
        return 'Entity data lineage tracking';
      case LicensedModule.whiteLabelBranding:
        return 'Custom branding and white-label deployment';
    }
  }

  /// Maps to the backend feature flag name in tenant_licenses.features.
  /// Returns null for always-on modules that have no backend gate (lineage).
  String? get featureKey {
    switch (this) {
      case LicensedModule.aiPrism:          return 'ai_copilot';
      case LicensedModule.dataQuality:        return 'data_quality';
      case LicensedModule.analytics:          return 'analytics';
      case LicensedModule.governance:         return 'governance';
      case LicensedModule.distribution:       return 'distribution';
      case LicensedModule.matchingSemantic:   return 'matching_semantic';
      case LicensedModule.relationships:      return 'relationships';
      case LicensedModule.domainPolicies:     return 'domain_policies';
      case LicensedModule.lineage:            return null; // always on
      case LicensedModule.whiteLabelBranding: return 'white_label';
    }
  }
}
