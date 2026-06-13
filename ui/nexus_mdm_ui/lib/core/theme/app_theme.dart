import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: _colorScheme,
      textTheme: _textTheme,
      scaffoldBackgroundColor: AppColors.navyBackground,
      cardTheme: _cardTheme,
      appBarTheme: _appBarTheme,
      elevatedButtonTheme: _elevatedButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme,
      textButtonTheme: _textButtonTheme,
      inputDecorationTheme: _inputDecorationTheme,
      chipTheme: _chipTheme,
      dividerTheme: _dividerTheme,
      iconTheme: _iconTheme,
      listTileTheme: _listTileTheme,
      tabBarTheme: _tabBarTheme,
      navigationRailTheme: _navigationRailTheme,
      bottomNavigationBarTheme: _bottomNavTheme,
      tooltipTheme: _tooltipTheme,
      dialogTheme: _dialogTheme,
      snackBarTheme: _snackBarTheme,
      progressIndicatorTheme: _progressIndicatorTheme,
      floatingActionButtonTheme: _fabTheme,
      switchTheme: _switchTheme,
      checkboxTheme: _checkboxTheme,
      radioTheme: _radioTheme,
      sliderTheme: _sliderTheme,
      popupMenuTheme: _popupMenuTheme,
      dataTableTheme: _dataTableTheme,
    );
  }

  static ColorScheme get _colorScheme => const ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.primary,
        onPrimary: AppColors.navyBackground,
        primaryContainer: AppColors.darkGreen,
        onPrimaryContainer: AppColors.mintAccent,
        secondary: AppColors.aiPurple,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.aiPurpleDark,
        onSecondaryContainer: AppColors.aiPurpleLight,
        tertiary: AppColors.warning,
        onTertiary: AppColors.navyBackground,
        tertiaryContainer: Color(0xFF3D2000),
        onTertiaryContainer: AppColors.warning,
        error: AppColors.error,
        onError: Colors.white,
        errorContainer: Color(0xFF4D0015),
        onErrorContainer: AppColors.error,
        surface: AppColors.cardSurface,
        onSurface: AppColors.primaryText,
        surfaceContainerHighest: AppColors.elevatedCard,
        onSurfaceVariant: AppColors.secondaryText,
        outline: AppColors.divider,
        outlineVariant: AppColors.mutedText,
        shadow: Colors.black,
        scrim: Colors.black54,
        inverseSurface: AppColors.primaryText,
        onInverseSurface: AppColors.navyBackground,
        inversePrimary: AppColors.darkGreen,
      );

  static TextTheme get _textTheme => TextTheme(
        displayLarge: AppTextStyles.displayLarge,
        displayMedium: AppTextStyles.displayMedium,
        displaySmall: AppTextStyles.displaySmall,
        headlineLarge: AppTextStyles.headlineLarge,
        headlineMedium: AppTextStyles.headlineMedium,
        headlineSmall: AppTextStyles.headlineSmall,
        titleLarge: AppTextStyles.titleLarge,
        titleMedium: AppTextStyles.titleMedium,
        titleSmall: AppTextStyles.titleSmall,
        bodyLarge: AppTextStyles.bodyLarge,
        bodyMedium: AppTextStyles.bodyMedium,
        bodySmall: AppTextStyles.bodySmall,
        labelLarge: AppTextStyles.labelLarge,
        labelMedium: AppTextStyles.labelMedium,
        labelSmall: AppTextStyles.labelSmall,
      );

  static CardThemeData get _cardTheme => CardThemeData(
        color: AppColors.cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.divider, width: 1),
        ),
        margin: EdgeInsets.zero,
      );

  static AppBarTheme get _appBarTheme => AppBarTheme(
        backgroundColor: AppColors.cardSurface,
        foregroundColor: AppColors.primaryText,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTextStyles.titleMedium,
        iconTheme: const IconThemeData(color: AppColors.primaryText, size: 22),
        actionsIconTheme:
            const IconThemeData(color: AppColors.primaryText, size: 22),
        toolbarHeight: 64,
        shape: const Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      );

  static ElevatedButtonThemeData get _elevatedButtonTheme =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.navyBackground,
          disabledBackgroundColor: AppColors.mutedText,
          disabledForegroundColor: AppColors.secondaryText,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: AppTextStyles.buttonMedium.copyWith(
            color: AppColors.navyBackground,
          ),
          minimumSize: const Size(120, 44),
        ),
      );

  static OutlinedButtonThemeData get _outlinedButtonTheme =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          disabledForegroundColor: AppColors.mutedText,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: AppTextStyles.buttonMedium,
          minimumSize: const Size(120, 44),
        ),
      );

  static TextButtonThemeData get _textButtonTheme => TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          disabledForegroundColor: AppColors.mutedText,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: AppTextStyles.buttonMedium,
          minimumSize: const Size(80, 36),
        ),
      );

  static InputDecorationTheme get _inputDecorationTheme => InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFill,
        hoverColor: AppColors.cardSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.divider, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.divider, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.mutedText, width: 1),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: AppTextStyles.inputHint,
        labelStyle: AppTextStyles.labelMedium
            .copyWith(color: AppColors.secondaryText),
        floatingLabelStyle:
            AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
        errorStyle:
            AppTextStyles.bodySmall.copyWith(color: AppColors.error),
        prefixIconColor: AppColors.secondaryText,
        suffixIconColor: AppColors.secondaryText,
        iconColor: AppColors.secondaryText,
      );

  static ChipThemeData get _chipTheme => ChipThemeData(
        backgroundColor: AppColors.elevatedCard,
        disabledColor: AppColors.cardSurface,
        selectedColor: AppColors.darkGreen,
        secondarySelectedColor: AppColors.primary,
        labelStyle: AppTextStyles.chipLabel.copyWith(
          color: AppColors.primaryText,
        ),
        secondaryLabelStyle: AppTextStyles.chipLabel.copyWith(
          color: AppColors.navyBackground,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.divider),
        ),
        side: const BorderSide(color: AppColors.divider),
        elevation: 0,
        pressElevation: 0,
        checkmarkColor: AppColors.primary,
      );

  static DividerThemeData get _dividerTheme => const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      );

  static IconThemeData get _iconTheme => const IconThemeData(
        color: AppColors.secondaryText,
        size: 20,
      );

  static ListTileThemeData get _listTileTheme => ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: AppColors.sidebarSelected,
        iconColor: AppColors.secondaryText,
        textColor: AppColors.primaryText,
        selectedColor: AppColors.primary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        titleTextStyle: AppTextStyles.bodyMedium,
        subtitleTextStyle: AppTextStyles.bodySmall,
      );

  static TabBarThemeData get _tabBarTheme => TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.secondaryText,
        labelStyle: AppTextStyles.labelLarge,
        unselectedLabelStyle: AppTextStyles.labelLarge,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.divider,
      );

  static NavigationRailThemeData get _navigationRailTheme =>
      NavigationRailThemeData(
        backgroundColor: AppColors.sidebarBackground,
        selectedIconTheme: const IconThemeData(
          color: AppColors.primary,
          size: 22,
        ),
        unselectedIconTheme: const IconThemeData(
          color: AppColors.secondaryText,
          size: 22,
        ),
        selectedLabelTextStyle: AppTextStyles.sidebarItem.copyWith(
          color: AppColors.primary,
        ),
        unselectedLabelTextStyle: AppTextStyles.sidebarItem.copyWith(
          color: AppColors.secondaryText,
        ),
        indicatorColor: AppColors.darkGreen.withValues(alpha:0.3),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 0,
        useIndicator: true,
        labelType: NavigationRailLabelType.none,
        minWidth: 72,
        minExtendedWidth: 240,
      );

  static BottomNavigationBarThemeData get _bottomNavTheme =>
      const BottomNavigationBarThemeData(
        backgroundColor: AppColors.cardSurface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.secondaryText,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w400,
        ),
      );

  static TooltipThemeData get _tooltipTheme => TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.elevatedCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.divider),
        ),
        textStyle: AppTextStyles.bodySmall.copyWith(
          color: AppColors.primaryText,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      );

  static DialogThemeData get _dialogTheme => DialogThemeData(
        backgroundColor: AppColors.modalBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.divider),
        ),
        titleTextStyle: AppTextStyles.titleLarge,
        contentTextStyle: AppTextStyles.bodyMedium,
      );

  static SnackBarThemeData get _snackBarTheme => SnackBarThemeData(
        backgroundColor: AppColors.elevatedCard,
        contentTextStyle: AppTextStyles.bodyMedium,
        actionTextColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.divider),
        ),
        elevation: 4,
      );

  static ProgressIndicatorThemeData get _progressIndicatorTheme =>
      const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.divider,
        circularTrackColor: AppColors.divider,
        linearMinHeight: 4,
      );

  static FloatingActionButtonThemeData get _fabTheme =>
      FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.navyBackground,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      );

  static SwitchThemeData get _switchTheme => SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.navyBackground;
          }
          return AppColors.secondaryText;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.divider;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      );

  static CheckboxThemeData get _checkboxTheme => CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(AppColors.navyBackground),
        side: const BorderSide(color: AppColors.divider, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      );

  static RadioThemeData get _radioTheme => RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.secondaryText;
        }),
      );

  static SliderThemeData get _sliderTheme => const SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.divider,
        thumbColor: AppColors.primary,
        overlayColor: Color(0x2000C896),
        valueIndicatorColor: AppColors.darkGreen,
        valueIndicatorTextStyle: TextStyle(
          color: AppColors.primaryText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );

  static PopupMenuThemeData get _popupMenuTheme => PopupMenuThemeData(
        color: AppColors.elevatedCard,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.divider),
        ),
        textStyle: AppTextStyles.bodyMedium,
        labelTextStyle: WidgetStateProperty.all(AppTextStyles.bodyMedium),
      );

  static DataTableThemeData get _dataTableTheme => DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(AppColors.navyBackground),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.darkGreen.withValues(alpha:0.1);
          }
          if (states.contains(WidgetState.hovered)) {
            return AppColors.elevatedCard;
          }
          return Colors.transparent;
        }),
        headingTextStyle: AppTextStyles.tableHeader,
        dataTextStyle: AppTextStyles.tableCell,
        headingRowHeight: 48,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 64,
        columnSpacing: 24,
        dividerThickness: 1,
        decoration: const BoxDecoration(
          color: AppColors.cardSurface,
          border: Border.fromBorderSide(
            BorderSide(color: AppColors.divider),
          ),
        ),
      );
}
