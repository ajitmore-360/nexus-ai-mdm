class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'Azile AI MDM';
  static const String appVersion = '1.0.0';
  static const String appTagline = 'Intelligent Master Data Management';

  // API Configuration
  static const String baseUrl = 'http://localhost:8080';
  static const String mdmServiceUrl = 'http://localhost:8081';
  static const String wsBaseUrl = 'ws://localhost:8080';
  static const String wsNotificationsPath = '/ws/notifications';

  // API Timeouts (milliseconds)
  static const int connectTimeout = 30000;
  static const int receiveTimeout = 60000;
  static const int sendTimeout = 30000;

  // API Paths â€” must match api-gateway routes exactly
  // Auth routes are served at root (no /v1 prefix) by the gateway.
  static const String authPath           = '/auth';
  static const String loginPath          = '/auth/login';
  static const String refreshTokenPath   = '/auth/refresh';
  static const String mePath             = '/auth/me';
  static const String acceptInvitePath   = '/auth/accept-invite';
  // Entity & MDM
  static const String entitiesPath       = '/v1/entities';
  static const String matchPath          = '/v1/match';
  static const String mergePath          = '/v1/merge';
  static const String goldenRecordsPath  = '/v1/golden-records';
  // Review queue (via mdm-core match queue)
  static const String matchQueuePath     = '/v1/match';
  static const String queueMetricsPath   = '/v1/match/queue-metrics';
  // AI
  static const String aiPrismPath       = '/v1/prism';
  static const String aiPrismStreamPath = '/v1/prism/stream';
  static const String aiWeightsPath      = '/v1/weights/recommend';
  static const String aiAnomaliesPath    = '/v1/anomalies';
  // Search
  static const String searchPath         = '/v1/search';
  static const String autocompletePath   = '/v1/search/autocomplete';
  // Policy
  static const String policyEvalPath     = '/v1/policy/evaluate';
  static const String policyRulesPath    = '/v1/policy/rules';
  static const String gdprErasurePath    = '/v1/policy/gdpr/erasure';
  static const String gdprAccessPath     = '/v1/policy/gdpr/access';
  // Consent
  static const String consentPath        = '/v1/consent';
  // Ingest
  static const String ingestBatchPath    = '/ingest/batch';
  static const String ingestEntitiesPath = '/v1/ingest/entities';
  static const String ingestCsvPath      = '/v1/ingest/csv';
  // Distribution
  static const String distributionPath   = '/v1/distribution/jobs';
  // Metrics & health
  static const String metricsPath        = '/metrics';
  // Dashboard â€” dedicated aggregate endpoints on mdm-core
  static const String dashboardStatsPath         = '/v1/dashboard/stats';
  static const String activityPath               = '/v1/dashboard/activity';
  static const String stewardPerformancePath           = '/v1/dashboard/steward-performance';
  static const String qualityDimensionsPath            = '/v1/dashboard/quality-dimensions';
  static const String survivorshipSuggestionsPath      = '/v1/policy/survivorship-suggestions';
  static const String gdprRequestsPath                 = '/v1/policy/gdpr/requests';
  // Audit
  static const String auditEventsPath    = '/v1/audit/events';
  // Admin
  static const String entityTypesPath    = '/v1/entity-types';
  static const String sourceSystemsPath  = '/v1/admin/source-systems';
  static const String adminPath          = '/v1/admin';
  // Governance, analytics, settings (served by policy/search services)
  static const String dataQualityPath    = '/v1/anomalies';
  static const String lineagePath        = '/v1/lineage';
  static const String lineageStatsPath   = '/v1/lineage/stats';
  static const String governancePath     = '/v1/policy/rules';
  static const String analyticsPath      = '/v1/search';
  static const String settingsPath       = '/v1/policy/weights';
  // Quality rules engine
  static const String qualityRulesPath      = '/v1/admin/quality-rules';
  static const String qualityViolationsPath = '/v1/admin/quality-violations';
  // AI suggestions (approval-gated LLM proposals)
  static const String aiSuggestionsPath     = '/v1/ai-suggestions';
  // Notifications & webhooks
  static const String notificationsPath  = '/v1/notifications';
  static const String webhooksPath       = '/v1/webhooks';
  // Phase 1/2 feature paths
  static const String xrefsPath              = '/v1/entities';   // + /:id/xrefs
  static const String commentsPath           = '/v1/entities';   // + /:id/comments
  static const String temporalHistoryPath    = '/v1/entities';   // + /:id/history
  static const String hierarchyPath         = '/v1/entities';    // + /:id/children|ancestors
  static const String hierarchyRootsPath    = '/v1/entities/hierarchy/roots';
  static const String unmergeBasePath       = '/v1/entities';    // + /:id/unmerge
  static const String bulkStatusPath        = '/v1/entities/bulk/status';
  static const String bulkExportPath        = '/v1/entities/bulk/export';
  static const String bulkTagPath           = '/v1/entities/bulk/tag';
  static const String qualityTrendsPath     = '/v1/analytics/quality-trends';
  static const String qualityDimensionPath  = '/v1/analytics/quality-dimensions';
  static const String sourceQualityPath     = '/v1/analytics/source-quality';
  static const String dataProfilingBase     = '/v1/data-profiling';  // + /:entity_type
  static const String tasksPath             = '/v1/tasks';
  static const String refDataPath           = '/v1/reference-data';
  static const String transformationRulesPath = '/v1/transformation-rules';
  static const String partyRolesBase        = '/v1/entities';    // + /:id/roles
  // License & domain management
  static const String licensePath        = '/v1/license';
  static const String brandingPath       = '/v1/tenant/branding';
  static const String domainPoliciesPath = '/v1/domain-policies';
  static const String relationshipTypesPath = '/v1/relationship-types';

  // SSO / OAuth2 PKCE (web redirect flow â€” S256 code challenge)
  // Client IDs are injected at build time via --dart-define:
  //   flutter build web --dart-define=GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com
  //   flutter build web --dart-define=AZURE_CLIENT_ID=yyy --dart-define=AZURE_TENANT_ID=zzz
  //   flutter build web --dart-define=OKTA_CLIENT_ID=aaa --dart-define=OKTA_ISSUER=https://xxx.okta.com
  // The app redirects the browser to the provider's auth URL and receives the
  // authorization code at /auth-callback, which exchanges it for tokens.
  static const String ssoExchangePath  = '/auth/sso-exchange';
  static const String authCallbackPath  = '/auth-callback';
  static const String googleAuthUrl     = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const String googleTokenUrl    = 'https://oauth2.googleapis.com/token';
  static const String googleClientId    = String.fromEnvironment('GOOGLE_CLIENT_ID',  defaultValue: '');
  static const String azureClientId     = String.fromEnvironment('AZURE_CLIENT_ID',   defaultValue: '');
  static const String azureTenantId     = String.fromEnvironment('AZURE_TENANT_ID',   defaultValue: 'common');
  static const String oktaClientId      = String.fromEnvironment('OKTA_CLIENT_ID',    defaultValue: '');
  static const String oktaIssuer        = String.fromEnvironment('OKTA_ISSUER',       defaultValue: '');

  // Auth Headers
  static const String authHeaderKey = 'Authorization';
  static const String authHeaderPrefix = 'Bearer ';
  static const String tenantHeaderKey = 'X-Tenant-ID';
  static const String requestIdHeaderKey = 'X-Request-ID';
  static const String contentTypeJson = 'application/json';

  // Storage Keys
  static const String storageAccessToken = 'access_token';
  static const String storageRefreshToken = 'refresh_token';
  static const String storageTenantId = 'tenant_id';
  static const String storageUserId = 'user_id';
  static const String storageUserEmail = 'user_email';
  static const String storageUserName = 'user_name';
  static const String storageUserRole = 'user_role';
  static const String storageThemeMode = 'theme_mode';
  static const String storageLastRoute = 'last_route';
  static const String storageOnboardingDone = 'onboarding_done';
  static const String storageLicenseKey          = 'license_key';
  static const String storageTenantName          = 'tenant_name';
  // Comma-separated list of entity_type_codes the steward is assigned to (empty for other roles).
  static const String storageAssignedEntityTypes = 'assigned_entity_types';

  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;
  static const int defaultPage = 1;

  // Entity Types â€” must match the backend EntityType enum in shared/contracts
  static const String entityTypeCustomer     = 'Customer';
  static const String entityTypeVendor       = 'Vendor';
  static const String entityTypeMaterial     = 'Material';
  static const String entityTypeProduct      = 'Product';
  static const String entityTypeAccount      = 'Account';
  static const String entityTypeEmployee     = 'Employee';
  static const String entityTypeLocation     = 'Location';
  static const String entityTypeOrganization = 'Organization';
  static const String entityTypeAsset        = 'Asset';

  static const List<String> entityTypes = [
    entityTypeCustomer,
    entityTypeVendor,
    entityTypeMaterial,
    entityTypeProduct,
    entityTypeAccount,
    entityTypeEmployee,
    entityTypeLocation,
    entityTypeOrganization,
    entityTypeAsset,
  ];

  // Entity Statuses
  static const String statusActive = 'Active';
  static const String statusGolden = 'Golden';
  static const String statusReview = 'Review';
  static const String statusMerged = 'Merged';
  static const String statusInactive = 'Inactive';
  static const String statusPending = 'Pending';

  static const List<String> entityStatuses = [
    statusActive,
    statusGolden,
    statusReview,
    statusMerged,
    statusInactive,
    statusPending,
  ];

  // Match Priority
  static const String priorityCritical = 'Critical';
  static const String priorityHigh = 'High';
  static const String priorityNormal = 'Normal';
  static const String priorityLow = 'Low';

  // Trust Score Thresholds
  static const double trustScoreHigh = 0.85;
  static const double trustScoreMedium = 0.65;
  static const double trustScoreLow = 0.40;

  // Match Score Thresholds
  static const double matchScoreAutoMerge = 0.95;
  static const double matchScoreHighConfidence = 0.85;
  static const double matchScoreMediumConfidence = 0.70;
  static const double matchScoreLowConfidence = 0.55;
  static const double matchScoreNoMatch = 0.40;

  // AI Prism
  static const String aiModelName = 'Azile AI v2.1';
  static const int maxChatHistory = 50;
  static const int aiResponseStreamDelayMs = 30;

  static const List<String> aiSuggestedPrompts = [
    'Show me entities with low trust scores',
    'What are the top duplicate sources this month?',
    'Explain the match score for entity ID...',
    'Which golden records need review?',
    'Show data quality trends for the past 30 days',
    'Find all entities from source system SAP',
    'What is the current merge conflict rate?',
    'Summarize recent matching activity',
  ];

  // Animation Durations
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 500);
  static const Duration animVerySlow = Duration(milliseconds: 800);
  static const Duration splashDuration = Duration(milliseconds: 2500);

  // Layout
  static const double sidebarWidth = 240;
  static const double sidebarCollapsedWidth = 72;
  static const double topBarHeight = 64;
  static const double mobileBreakpoint = 768;
  static const double tabletBreakpoint = 1024;
  static const double desktopBreakpoint = 1440;
  static const double cardBorderRadius = 12;
  static const double cardPadding = 20;
  static const double pageHorizontalPadding = 24;
  static const double pageVerticalPadding = 24;
  static const double gridSpacing = 16;

  // Data Sources (demo)
  static const List<String> dataSources = [
    'Salesforce CRM',
    'SAP ERP',
    'Oracle DB',
    'HubSpot',
    'Marketo',
    'Workday HR',
    'ServiceNow',
    'Custom API',
    'Manual Entry',
    'CSV Import',
  ];
}
