import 'package:flutter/material.dart';

/// Semantic colour tokens for HozaSend.
///
/// Dark is the reference palette; light is derived from it so the product keeps
/// one identity in both modes. Widgets read `context.colors` (see
/// `app_theme.dart`) instead of hardcoding a [Color].
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.backgroundTop,
    required this.backgroundTint,
    required this.backgroundGlow,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.border,
    required this.borderStrong,
    required this.primary,
    required this.primaryDeep,
    required this.primarySoft,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.danger,
    required this.dangerSoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.onBrand,
    required this.shadow,
  });

  /// Page background.
  final Color background;

  /// Top of the page gradient. A page falls from this to [background], which
  /// gives the app somewhere to sit: a single flat fill reads as a dead sheet,
  /// and every card on it looks pasted on rather than resting.
  final Color backgroundTop;

  /// Faint brand wash painted behind the page for depth.
  final Color backgroundTint;

  /// The cooler wash low on the page, opposite [backgroundTint]. Two lights
  /// from different corners is what stops a large dark surface reading as
  /// black cardboard.
  final Color backgroundGlow;

  final Color surface;
  final Color surfaceElevated;
  final Color surfaceMuted;
  final Color border;
  final Color borderStrong;

  final Color primary;
  final Color primaryDeep;

  /// Low-alpha primary, for tinted fills and halos.
  final Color primarySoft;

  final Color accent;
  final Color accentSoft;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color danger;
  final Color dangerSoft;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Text and icons drawn on top of [primary] or [accent].
  final Color onBrand;

  final Color shadow;

  static const AppColors dark = AppColors(
    // Deep midnight, but never flat black: the page falls from a lifted navy
    // at the top to the deepest tone at the bottom, and the surfaces sit
    // clearly above both so a card reads as a card without needing a heavy
    // border to prove it.
    background: Color(0xFF070B13),
    backgroundTop: Color(0xFF0E1626),
    backgroundTint: Color(0x1E3B72FF),
    backgroundGlow: Color(0x1435D6F0),
    surface: Color(0xFF111A2B),
    surfaceElevated: Color(0xFF18233A),
    surfaceMuted: Color(0xFF141E31),
    border: Color(0xFF22304A),
    borderStrong: Color(0xFF334564),
    primary: Color(0xFF3B72FF),
    primaryDeep: Color(0xFF1E4ED8),
    primarySoft: Color(0x1F3B72FF),
    accent: Color(0xFF35D6F0),
    accentSoft: Color(0x1F35D6F0),
    success: Color(0xFF34D399),
    successSoft: Color(0x2334D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0x23F87171),
    textPrimary: Color(0xFFF3F6FB),
    textSecondary: Color(0xFF9AA7BD),
    textTertiary: Color(0xFF64748B),
    onBrand: Color(0xFFFFFFFF),
    shadow: Color(0x66000000),
  );

  static const AppColors light = AppColors(
    background: Color(0xFFEDF2FA),
    backgroundTop: Color(0xFFFBFDFF),
    backgroundTint: Color(0x122158F0),
    backgroundGlow: Color(0x0C0EA5C4),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEDF2FA),
    border: Color(0xFFE3E9F3),
    borderStrong: Color(0xFFCBD6E6),
    primary: Color(0xFF2158F0),
    primaryDeep: Color(0xFF1740B8),
    primarySoft: Color(0x162158F0),
    accent: Color(0xFF0EA5C4),
    accentSoft: Color(0x160EA5C4),
    success: Color(0xFF0F9F6E),
    successSoft: Color(0x1A0F9F6E),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0x1ADC2626),
    textPrimary: Color(0xFF0B1220),
    textSecondary: Color(0xFF55637A),
    textTertiary: Color(0xFF8593A8),
    onBrand: Color(0xFFFFFFFF),
    shadow: Color(0x14101828),
  );

  /// Brand gradient: logo, primary buttons, progress fills.
  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[primary, accent],
      );

  /// Barely-there sheen that keeps large cards from reading flat.
  LinearGradient get surfaceGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[surfaceElevated, surface],
      );

  /// Resting shadow for cards.
  List<BoxShadow> get softShadow => <BoxShadow>[
        BoxShadow(color: shadow, blurRadius: 24, offset: const Offset(0, 8)),
      ];

  /// For elements that should read as lifted: buttons, sheets, dialogs.
  List<BoxShadow> get liftedShadow => <BoxShadow>[
        BoxShadow(color: shadow, blurRadius: 36, offset: const Offset(0, 14)),
      ];

  @override
  AppColors copyWith({
    Color? background,
    Color? backgroundTop,
    Color? backgroundTint,
    Color? backgroundGlow,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceMuted,
    Color? border,
    Color? borderStrong,
    Color? primary,
    Color? primaryDeep,
    Color? primarySoft,
    Color? accent,
    Color? accentSoft,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? danger,
    Color? dangerSoft,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? onBrand,
    Color? shadow,
  }) {
    return AppColors(
      background: background ?? this.background,
      backgroundTop: backgroundTop ?? this.backgroundTop,
      backgroundTint: backgroundTint ?? this.backgroundTint,
      backgroundGlow: backgroundGlow ?? this.backgroundGlow,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      primary: primary ?? this.primary,
      primaryDeep: primaryDeep ?? this.primaryDeep,
      primarySoft: primarySoft ?? this.primarySoft,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      onBrand: onBrand ?? this.onBrand,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      backgroundTop: Color.lerp(backgroundTop, other.backgroundTop, t)!,
      backgroundTint: Color.lerp(backgroundTint, other.backgroundTint, t)!,
      backgroundGlow: Color.lerp(backgroundGlow, other.backgroundGlow, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDeep: Color.lerp(primaryDeep, other.primaryDeep, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}
