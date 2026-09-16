/// MoaV design system for the Deploy app.
///
/// Tokens mirror `docs/stylesheets/blog.css` on moav-site so the app and the
/// site read as one product: near-black backgrounds with a faint radial glow
/// at the top, white / grey text ramps, a cyan→purple accent gradient, Inter
/// for prose and JetBrains Mono for anything that is a value (hosts, keys,
/// metrics, code). Fonts are bundled in `assets/fonts` and never fetched.
library;

import 'package:flutter/material.dart';

import '../core/moav_controller.dart' show CheckResult;

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

abstract final class MoavColors {
  static const bg = Color(0xFF0A0A0F);
  static const bgSecondary = Color(0xFF12121A);
  static const card = Color(0xFF15151F);
  static const cardRaised = Color(0xFF1B1B27);
  static const codeBg = Color(0xFF0D0D15);
  static const glowTop = Color(0xFF1A1A2E);

  static const text = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFA0A0B0);
  static const textMuted = Color(0xFF606070);
  static const codeText = Color(0xFFD7D7E0);

  static const cyan = Color(0xFF00D4FF);
  static const purple = Color(0xFF7B5CFF);

  /// Pass / warn / fail on dark; tuned for legibility against [card].
  static const pass = Color(0xFF3DDC97);
  static const warn = Color(0xFFFFB454);
  static const fail = Color(0xFFFF5C7A);

  /// rgba(255,255,255,.06) — hairline borders.
  static const border = Color(0x0FFFFFFF);
  static const borderStrong = Color(0x1FFFFFFF);
}

abstract final class MoavRadius {
  static const double lg = 12;
  static const double sm = 8;
  static final BorderRadius card = BorderRadius.circular(lg);
  static final BorderRadius control = BorderRadius.circular(sm);
}

abstract final class MoavFonts {
  static const sans = 'Inter';
  static const mono = 'JetBrains Mono';
}

abstract final class MoavGradients {
  /// `linear-gradient(135deg, cyan, purple)`.
  static const accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [MoavColors.cyan, MoavColors.purple],
  );

  /// `radial-gradient(ellipse at top, #1a1a2e 0%, #0a0a0f 55%)`.
  static const background = RadialGradient(
    center: Alignment(0, -1),
    radius: 1.25,
    colors: [MoavColors.glowTop, MoavColors.bg],
    stops: [0, 0.55],
  );
}

/// `0 0 24px rgba(0,212,255,.18)` by default.
List<BoxShadow> moavGlow({
  Color color = MoavColors.cyan,
  double blur = 24,
  double alpha = 0.18,
}) =>
    [BoxShadow(color: color.withValues(alpha: alpha), blurRadius: blur)];

/// Mono text style for values, keys, metrics and code.
TextStyle moavMono({
  double size = 13,
  FontWeight weight = FontWeight.w500,
  Color color = MoavColors.text,
  double? height,
  double? letterSpacing,
}) =>
    TextStyle(
      fontFamily: MoavFonts.mono,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Small uppercase mono label (section headers, pills, tile captions).
TextStyle moavLabel({
  double size = 11,
  Color color = MoavColors.textSecondary,
  FontWeight weight = FontWeight.w600,
}) =>
    TextStyle(
      fontFamily: MoavFonts.mono,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: 1.1,
    );

// ---------------------------------------------------------------------------
// ThemeData
// ---------------------------------------------------------------------------

const _scheme = ColorScheme(
  brightness: Brightness.dark,
  primary: MoavColors.cyan,
  onPrimary: MoavColors.bg,
  primaryContainer: Color(0xFF0E2B36),
  onPrimaryContainer: Color(0xFF9BE9FF),
  secondary: MoavColors.purple,
  onSecondary: MoavColors.text,
  secondaryContainer: Color(0xFF10262F),
  onSecondaryContainer: Color(0xFF9BE9FF),
  tertiary: MoavColors.pass,
  onTertiary: MoavColors.bg,
  tertiaryContainer: Color(0xFF0F2E24),
  onTertiaryContainer: Color(0xFFA6F2D2),
  error: MoavColors.fail,
  onError: MoavColors.bg,
  errorContainer: Color(0xFF3A1622),
  onErrorContainer: Color(0xFFFFB3C0),
  surface: MoavColors.bg,
  onSurface: MoavColors.text,
  surfaceDim: MoavColors.bg,
  surfaceBright: MoavColors.cardRaised,
  surfaceContainerLowest: MoavColors.codeBg,
  surfaceContainerLow: MoavColors.bgSecondary,
  surfaceContainer: MoavColors.card,
  surfaceContainerHigh: MoavColors.cardRaised,
  surfaceContainerHighest: Color(0xFF222230),
  onSurfaceVariant: MoavColors.textSecondary,
  outline: MoavColors.textMuted,
  outlineVariant: Color(0xFF1E1E2A),
  shadow: Colors.black,
  scrim: Colors.black,
  inverseSurface: MoavColors.text,
  onInverseSurface: MoavColors.bg,
  inversePrimary: MoavColors.purple,
  surfaceTint: Colors.transparent,
);

/// The one dark theme the app ships with.
ThemeData moavDarkTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _scheme,
    fontFamily: MoavFonts.sans,
    scaffoldBackgroundColor: MoavColors.bg,
    canvasColor: MoavColors.bg,
    splashFactory: InkSparkle.splashFactory,
  );
  final t = base.textTheme;
  final textTheme = t
      .copyWith(
        headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: t.bodyLarge?.copyWith(color: MoavColors.textSecondary),
        bodyMedium: t.bodyMedium?.copyWith(color: MoavColors.textSecondary),
        bodySmall: t.bodySmall?.copyWith(color: MoavColors.textMuted),
        labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      )
      .apply(
        fontFamily: MoavFonts.sans,
        bodyColor: MoavColors.text,
        displayColor: MoavColors.text,
      );

  final controlShape = RoundedRectangleBorder(borderRadius: MoavRadius.control);
  final cardShape = RoundedRectangleBorder(
    borderRadius: MoavRadius.card,
    side: const BorderSide(color: MoavColors.border),
  );

  return base.copyWith(
    textTheme: textTheme,
    iconTheme: const IconThemeData(color: MoavColors.textSecondary, size: 22),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: MoavColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 19),
      iconTheme: const IconThemeData(color: MoavColors.textSecondary),
      actionsIconTheme: const IconThemeData(color: MoavColors.textSecondary),
    ),
    cardTheme: CardThemeData(
      color: MoavColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: cardShape,
    ),
    dividerTheme: const DividerThemeData(
      color: MoavColors.border,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      // No explicit colours here: plain FilledButton takes primary/onPrimary
      // (cyan on dark) and FilledButton.tonal takes secondaryContainer.
      style: FilledButton.styleFrom(
        disabledBackgroundColor: MoavColors.cardRaised,
        disabledForegroundColor: MoavColors.textMuted,
        shape: controlShape,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MoavColors.text,
        disabledForegroundColor: MoavColors.textMuted,
        side: const BorderSide(color: MoavColors.borderStrong),
        shape: controlShape,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MoavColors.cyan,
        shape: controlShape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: MoavColors.textSecondary),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: MoavColors.cyan,
      foregroundColor: MoavColors.bg,
      elevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: MoavRadius.card),
      extendedTextStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        fontFamily: MoavFonts.sans,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MoavColors.bgSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: MoavRadius.control,
        borderSide: const BorderSide(color: MoavColors.borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: MoavRadius.control,
        borderSide: const BorderSide(color: MoavColors.borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: MoavRadius.control,
        borderSide: const BorderSide(color: MoavColors.cyan, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: MoavRadius.control,
        borderSide: const BorderSide(color: MoavColors.fail),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: MoavRadius.control,
        borderSide: const BorderSide(color: MoavColors.fail, width: 1.5),
      ),
      labelStyle: const TextStyle(color: MoavColors.textSecondary),
      floatingLabelStyle: const TextStyle(color: MoavColors.cyan),
      hintStyle: const TextStyle(color: MoavColors.textMuted),
      helperStyle: const TextStyle(color: MoavColors.textMuted),
      errorStyle: const TextStyle(color: MoavColors.fail),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorColor: MoavColors.cyan,
      indicatorSize: TabBarIndicatorSize.label,
      labelColor: MoavColors.text,
      unselectedLabelColor: MoavColors.textSecondary,
      dividerColor: MoavColors.border,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      labelStyle: const TextStyle(
        fontFamily: MoavFonts.sans,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: MoavFonts.sans,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: MoavColors.text,
      iconColor: MoavColors.textSecondary,
      subtitleTextStyle: TextStyle(
        color: MoavColors.textSecondary,
        fontSize: 13,
        fontFamily: MoavFonts.sans,
      ),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      iconColor: MoavColors.textSecondary,
      collapsedIconColor: MoavColors.textMuted,
      textColor: MoavColors.text,
      collapsedTextColor: MoavColors.text,
      shape: Border(),
      collapsedShape: Border(),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: MoavColors.cardRaised,
      contentTextStyle: const TextStyle(
        color: MoavColors.text,
        fontFamily: MoavFonts.sans,
      ),
      actionTextColor: MoavColors.cyan,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: MoavRadius.control,
        side: const BorderSide(color: MoavColors.borderStrong),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: MoavColors.card,
      surfaceTintColor: Colors.transparent,
      shape: cardShape,
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: MoavColors.cardRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: MoavRadius.control,
        side: const BorderSide(color: MoavColors.borderStrong),
      ),
      textStyle: textTheme.bodyMedium?.copyWith(color: MoavColors.text),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MoavColors.cyan,
      linearTrackColor: MoavColors.borderStrong,
      circularTrackColor: Colors.transparent,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: MoavColors.bgSecondary,
      side: const BorderSide(color: MoavColors.borderStrong),
      shape: controlShape,
      labelStyle: const TextStyle(color: MoavColors.textSecondary, fontSize: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(controlShape),
        side: const WidgetStatePropertyAll(
          BorderSide(color: MoavColors.borderStrong),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? MoavColors.cyan.withValues(alpha: 0.14)
              : MoavColors.bgSecondary,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? MoavColors.cyan
              : MoavColors.textSecondary,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? MoavColors.cyan
              : MoavColors.textSecondary,
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: MoavColors.cyan,
      selectionColor: Color(0x3300D4FF),
      selectionHandleColor: MoavColors.cyan,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: MoavColors.card,
      surfaceTintColor: Colors.transparent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: MoavColors.cardRaised,
        borderRadius: MoavRadius.control,
        border: Border.all(color: MoavColors.borderStrong),
      ),
      textStyle: const TextStyle(color: MoavColors.text, fontSize: 12),
    ),
  );
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

/// A [Scaffold] on the MoaV background (radial glow at the top). The app bar
/// is transparent so the glow reads through it.
class MoavScaffold extends StatelessWidget {
  const MoavScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset,
  });

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: MoavGradients.background),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      ),
    );
  }
}

/// The `MoaV` wordmark in the accent gradient, with an optional plain suffix.
class MoavWordmark extends StatelessWidget {
  const MoavWordmark({super.key, this.suffix, this.size = 19});

  final String? suffix;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: MoavFonts.sans,
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GradientText('MoaV', style: style),
        if (suffix != null) ...[
          const SizedBox(width: 6),
          Text(suffix!, style: style.copyWith(fontWeight: FontWeight.w500)),
        ],
      ],
    );
  }
}

/// Text painted with the accent gradient.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => MoavGradients.accent.createShader(r),
      child: Text(text, style: (style ?? const TextStyle()).copyWith(color: Colors.white)),
    );
  }
}

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// Card surface: `bg-card`, 12 px radius, hairline border. `accent` draws a
/// 2 px gradient hairline along the top edge; `glow` adds the cyan glow.
class MoavCard extends StatelessWidget {
  const MoavCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.accent = false,
    this.glow = false,
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool accent;
  final bool glow;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    Widget body = Padding(padding: padding, child: child);
    if (onTap != null) {
      body = InkWell(
        onTap: onTap,
        borderRadius: MoavRadius.card,
        child: body,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: color ?? MoavColors.card,
        borderRadius: MoavRadius.card,
        border: Border.all(color: MoavColors.border),
        boxShadow: glow ? moavGlow() : null,
      ),
      child: ClipRRect(
        borderRadius: MoavRadius.card,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              body,
              if (accent)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: MoavGradients.accent),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uppercase mono section title with a small gradient tick.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.only(top: 20, bottom: 10),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              gradient: MoavGradients.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title.toUpperCase(), style: moavLabel())),
          ?trailing,
        ],
      ),
    );
  }
}

/// Mono block for keys, configs and logs.
class CodeBlock extends StatelessWidget {
  const CodeBlock(
    this.text, {
    super.key,
    this.selectable = true,
    this.maxLines,
    this.size = 12,
  });

  final String text;
  final bool selectable;
  final int? maxLines;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = moavMono(
      size: size,
      weight: FontWeight.w400,
      color: MoavColors.codeText,
      height: 1.45,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MoavColors.codeBg,
        borderRadius: MoavRadius.control,
        border: Border.all(color: MoavColors.border),
      ),
      child: selectable
          ? SelectableText(text, style: style, maxLines: maxLines)
          : Text(
              text,
              style: style,
              maxLines: maxLines,
              overflow: maxLines == null ? null : TextOverflow.ellipsis,
            ),
    );
  }
}

/// A rounded square icon tinted with the accent colour.
class IconBadge extends StatelessWidget {
  const IconBadge(
    this.icon, {
    super.key,
    this.size = 38,
    this.color = MoavColors.cyan,
    this.gradient = false,
  });

  final IconData icon;
  final double size;
  final Color color;

  /// Solid accent gradient instead of a tint (for primary/hero use).
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient ? MoavGradients.accent : null,
        color: gradient ? null : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: gradient ? null : Border.all(color: color.withValues(alpha: 0.28)),
        boxShadow: gradient ? moavGlow(blur: 16) : null,
      ),
      child: Icon(
        icon,
        size: size * 0.5,
        color: gradient ? MoavColors.bg : color,
      ),
    );
  }
}

/// Gradient circle with the first letter of a name.
class MoavAvatar extends StatelessWidget {
  const MoavAvatar(this.name, {super.key, this.size = 36});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: MoavGradients.accent,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: MoavFonts.sans,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: MoavColors.bg,
        ),
      ),
    );
  }
}

/// Centered icon + title + body for empty lists and idle states.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(icon, size: 64, gradient: true),
            const SizedBox(height: 20),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body!, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

enum StatusTone { pass, warn, fail, neutral, accent }

extension StatusToneX on StatusTone {
  Color get color => switch (this) {
        StatusTone.pass => MoavColors.pass,
        StatusTone.warn => MoavColors.warn,
        StatusTone.fail => MoavColors.fail,
        StatusTone.neutral => MoavColors.textSecondary,
        StatusTone.accent => MoavColors.cyan,
      };

  static StatusTone of(CheckResult r) => switch (r) {
        CheckResult.pass => StatusTone.pass,
        CheckResult.warn => StatusTone.warn,
        CheckResult.fail => StatusTone.fail,
        CheckResult.skip => StatusTone.neutral,
      };
}

/// Compact tinted pill: `● RUNNING`, `✓ PASS`, `! WARN`, `✗ FAIL`.
class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    super.key,
    this.tone = StatusTone.neutral,
    this.icon,
    this.dot = true,
  });

  /// Pill for a doctor / test result, with the icon the result implies.
  StatusPill.result(CheckResult result, {super.key, String? label})
      : label = label ?? result.name,
        tone = StatusToneX.of(result),
        dot = false,
        icon = switch (result) {
          CheckResult.pass => Icons.check_circle,
          CheckResult.warn => Icons.warning_amber,
          CheckResult.fail => Icons.cancel,
          CheckResult.skip => Icons.remove_circle_outline,
        };

  final String label;
  final StatusTone tone;
  final IconData? icon;

  /// Show a 6 px dot when no [icon] is given.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final c = tone.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 12, color: c)
          else if (dot)
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
          if (icon != null || dot) const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: moavLabel(size: 10, color: c).copyWith(letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------------

/// One headline number: caption, mono value with optional unit, optional
/// footnote and status pill. `accent` adds the gradient hairline.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.sub,
    this.pill,
    this.accent = false,
    this.tone,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final String? sub;
  final StatusPill? pill;
  final bool accent;

  /// Tints the value (e.g. warn/fail) instead of plain white.
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final valueColor = tone?.color ?? MoavColors.text;
    return MoavCard(
      accent: accent,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: MoavColors.cyan),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: moavLabel(size: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?pill,
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                text: value,
                style: moavMono(size: 24, weight: FontWeight.w600, color: valueColor, height: 1.1),
                children: [
                  if (unit != null)
                    TextSpan(
                      text: unit,
                      style: moavMono(size: 13, color: MoavColors.textSecondary),
                    ),
                ],
              ),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(
              sub!,
              style: moavMono(size: 11, weight: FontWeight.w400, color: MoavColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// `label · value` row in mono, for key/value summaries.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: moavMono(size: 12, weight: FontWeight.w400, color: MoavColors.textMuted)),
          ),
          Expanded(
            child: Text(
              value,
              style: moavMono(size: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// Primary action: accent gradient, cyan glow, dark label.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.glow = true,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: MoavGradients.accent,
            borderRadius: MoavRadius.control,
            boxShadow: enabled && glow ? moavGlow() : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: MoavRadius.control,
              onTap: enabled ? onPressed : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: MoavColors.bg,
                        ),
                      )
                    else if (icon != null)
                      Icon(icon, size: 18, color: MoavColors.bg),
                    if (busy || icon != null) const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily: MoavFonts.sans,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MoavColors.bg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating action button in the gradient + glow style.
class MoavFab extends StatelessWidget {
  const MoavFab({
    super.key,
    required this.onPressed,
    required this.label,
    required this.icon,
  });

  final VoidCallback onPressed;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: MoavGradients.accent,
        borderRadius: MoavRadius.card,
        boxShadow: moavGlow(blur: 28, alpha: 0.28),
      ),
      child: FloatingActionButton.extended(
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        foregroundColor: MoavColors.bg,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}
