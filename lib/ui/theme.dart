import 'package:material_ui/material_ui.dart';

import '../data/models/txn.dart';
import 'icons.dart';

const _seed = Color(0xFF00897B);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  const radius = BorderRadius.all(Radius.circular(12));
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6), space: 1),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    // Back and close buttons in app bars use the same icon set as the rest.
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const AppIcon(AppIcons.back),
      closeButtonIconBuilder: (_) => const AppIcon(AppIcons.close),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
  );
}

/// Colours that mean the same thing everywhere in the app.
class MoneyColors {
  static Color income(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0);

  static Color expense(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828);

  static Color neutral(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;

  static Color forType(BuildContext context, TxnType type) => switch (type) {
    TxnType.income => income(context),
    TxnType.expense => expense(context),
    TxnType.transfer => neutral(context),
  };

  static Color forSigned(BuildContext context, int value) =>
      value < 0 ? expense(context) : (value > 0 ? income(context) : neutral(context));
}

/// The theme gives cards a 16px radius with no border, which also strips the
/// border from Card.outlined. Outlined cards pass this shape instead.
ShapeBorder outlinedCardShape(BuildContext context) => RoundedRectangleBorder(
  borderRadius: const BorderRadius.all(Radius.circular(16)),
  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
);
