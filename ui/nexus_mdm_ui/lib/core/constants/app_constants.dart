class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'Nexus AI MDM';
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

  // API Paths — must match api-gateway routes exactly
  static const String authPath           = '/auth';
  static const String loginPath          = '/auth/login';
  static const String refreshTokenPath   = '/auth/refresh';
  static const String mePath             = '/auth/me';
  // Entity & MDM
  static const String entitiesPath       = '/entities';
  static const String matchPath          = '/match';
  static const String mergePath          = '/merge';
  static const String goldenRecordsPath  = '/golden-records';
  // Review queue (via mdm-core match queue)
  static const String matchQueuePath     = '/match';
  // AI
  static const String aiCopilotPath      = '/copilot';
  static const String aiWeightsPath      = '/weights/recommend';
  static const String aiAnomaliesPath    = '/anomalies';
  // Search
  static const String searchPath         = '/search';
  static const String autocompletePath   = '/search/autocomplete';
  // Policy
  static const String policyEvalPath     = '/policy/evaluate';
  static const String policyRulesPath    = '/policy/rules';
  static const String gdprErasurePath    = '/policy/gdpr/erasure';
  static const String gdprAccessPath     = '/policy/gdpr/access';
  // Ingest
  static const String ingestBatchPath    = '/ingest/batch';
  static const String ingestEntitiesPath = '/ingest/entities';
  // Distribution
  static const String distributionPath   = '/distribution/jobs';
  // Metrics & health
  static const String metricsPath        = '/metrics';
  // Dashboard — dedicated aggregate endpoints on mdm-core
  static const String dashboardStatsPath = '/dashboard/stats';
  static const String activityPath       = '/dashboard/activity';
  // Governance, analytics, settings (served by policy/search services)
  static const String dataQualityPath    = '/anomalies';
  static const String lineagePath        = '/search';
  static const String governancePath     = '/policy/rules';
  static const String analyticsPath      = '/search';
  static const String settingsPath       = '/policy/weights';

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

  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;
  static const int defaultPage = 1;

  // Entity Types — must match the backend EntityType enum in shared/contracts
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

  // AI Copilot
  static const String aiModelName = 'Nexus AI v2.1';
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
