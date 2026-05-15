part of '../main.dart';

const _neonPurple = Color(0xFF4B118C);
const _neonMagenta = Color(0xFFEE09A5);

// Artwork radius for album/song covers (sharp look like real album artwork)
const double kArtworkRadius = 8.0;

// Light Mode
const _lightBg = Color(0xFFFFFBFF);
const _lightSurface = Color(0xFFFFFFFF);
const _lightSurfaceSoft = Color(0xFFFFF1F8);
const _lightGlassBase = Color(0xFFF0EAF1);
const _lightAccentPink = Color(0xFFFF4FA3);
const _lightNavIconPink = Color(0xFFFF4FA3);
const _lightAccentPurple = Color(0xFF9B5CFF);
const _lightAccentMagenta = Color(0xFFE94DFF);
const _lightText = Color(0xFF20151E);
const _lightSubtext = Color(0xFF76616F);
const _lightTextPri = Color(0xFF1A1A1A);
const _lightTextSub = Color(0xFF666666);

// Dark Mode
const _darkBg = Color(0xFF0D0D11);
const _darkTextPri = Color(0xFFFFFFFF);
const _darkTextSub = Color(0xFFA0A0B0);

// Legacy colors for compatibility (will be phased out)
const _bg = Color(0xFF101014);
const _pink = Color(0xFFFF2A7A);
const _accentWhite = Color(0xFFEDEDED);
const _accentChampagne = Color(0xFFE6C8A0);
const _accentBlue = Color(0xFF8EA7FF);
const _accentPink = Color(0xFFFF4D8D);
const _accentDefault = _accentWhite;
const _cyan = Color(0xFF00E5FF);
const _purple = Color(0xFF7C4DFF);
const _textPri = Color(0xFFFFFFFF);
const _textSub = Color(0xFFA0A0B0);
const _glassWhite = Color(0x15FFFFFF);
const glassBorder = Color(0x30FFFFFF);

final List<Color> _defaultDynamicColors = [
  const Color(0xFF1C1C22),
  _accentPink,
  _accentBlue,
  _accentWhite,
];

/// Calculates luminance for WCAG contrast ratio
double _calculateLuminance(Color color) {
  final r = color.red / 255;
  final g = color.green / 255;
  final b = color.blue / 255;

  final rr =
      r <= 0.03928 ? r / 12.92 : math.pow((r + 0.055) / 1.055, 2.4).toDouble();
  final gg =
      g <= 0.03928 ? g / 12.92 : math.pow((g + 0.055) / 1.055, 2.4).toDouble();
  final bb =
      b <= 0.03928 ? b / 12.92 : math.pow((b + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * rr + 0.7152 * gg + 0.0722 * bb;
}

/// Calculates contrast ratio between two colors (WCAG)
double _calculateContrastRatio(Color foreground, Color background) {
  final lum1 = _calculateLuminance(foreground);
  final lum2 = _calculateLuminance(background);
  final lighter = math.max(lum1, lum2);
  final darker = math.min(lum1, lum2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Darkens a color to meet WCAG AA contrast (4.5:1) against white
Color _darkenForAccessibility(Color color,
    {Color background = const Color(0xFFFFFFFF)}) {
  Color adjusted = color;
  int steps = 0;
  while (_calculateContrastRatio(adjusted, background) < 4.5 && steps < 100) {
    adjusted = Color.fromARGB(
      adjusted.alpha,
      (adjusted.red * 0.95).round(),
      (adjusted.green * 0.95).round(),
      (adjusted.blue * 0.95).round(),
    );
    steps++;
  }
  return adjusted;
}

/// Lightens a color to meet WCAG AA contrast (4.5:1) against dark background
Color _lightenForAccessibility(Color color,
    {Color background = const Color(0xFF0D0D11)}) {
  Color adjusted = color;
  int steps = 0;
  while (_calculateContrastRatio(adjusted, background) < 4.5 && steps < 100) {
    adjusted = Color.fromARGB(
      adjusted.alpha,
      math.min(255, (adjusted.red + (255 - adjusted.red) * 0.1).round()),
      math.min(255, (adjusted.green + (255 - adjusted.green) * 0.1).round()),
      math.min(255, (adjusted.blue + (255 - adjusted.blue) * 0.1).round()),
    );
    steps++;
  }
  return adjusted;
}

/// Generates a complete ColorScheme for Neon-Blob aesthetic
class NeonBlobColorScheme {
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color disabled;
  final Color onDisabled;
  final Color hover;
  final Color pressed;

  const NeonBlobColorScheme({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.disabled,
    required this.onDisabled,
    required this.hover,
    required this.pressed,
  });

  /// Generate Light Mode ColorScheme
  factory NeonBlobColorScheme.light() {
    // Darken purple and magenta for text on white
    final primary = _darkenForAccessibility(_neonPurple);
    final secondary = _darkenForAccessibility(_neonMagenta);
    final tertiary = _darkenForAccessibility(_neonPurple.withOpacity(0.8));

    return NeonBlobColorScheme(
      primary: primary,
      onPrimary: _lightBg,
      primaryContainer: primary.withOpacity(0.12),
      onPrimaryContainer: primary,
      secondary: secondary,
      onSecondary: _lightBg,
      secondaryContainer: secondary.withOpacity(0.12),
      onSecondaryContainer: secondary,
      tertiary: tertiary,
      onTertiary: _lightBg,
      surface: _lightBg,
      onSurface: _lightTextPri,
      onSurfaceVariant: _lightTextSub,
      outline: primary.withOpacity(0.2),
      outlineVariant: secondary.withOpacity(0.15),
      disabled: Color.lerp(primary, const Color(0xFF808080), 0.5)!,
      onDisabled: _lightTextSub.withOpacity(0.5),
      hover: primary.withOpacity(0.08),
      pressed: primary.withOpacity(0.15),
    );
  }

  /// Generate Dark Mode ColorScheme
  factory NeonBlobColorScheme.dark() {
    // Lighten purple and magenta for text on dark
    final primary = _lightenForAccessibility(_neonPurple);
    final secondary = _lightenForAccessibility(_neonMagenta);
    final tertiary = _lightenForAccessibility(_neonPurple.withOpacity(0.8));

    return NeonBlobColorScheme(
      primary: primary,
      onPrimary: _darkBg,
      primaryContainer: primary.withOpacity(0.15),
      onPrimaryContainer: primary,
      secondary: secondary,
      onSecondary: _darkBg,
      secondaryContainer: secondary.withOpacity(0.15),
      onSecondaryContainer: secondary,
      tertiary: tertiary,
      onTertiary: _darkBg,
      surface: _darkBg,
      onSurface: _darkTextPri,
      onSurfaceVariant: _darkTextSub,
      outline: primary.withOpacity(0.3),
      outlineVariant: secondary.withOpacity(0.2),
      disabled: Color.lerp(primary, const Color(0xFF404040), 0.6)!,
      onDisabled: _darkTextSub.withOpacity(0.4),
      hover: primary.withOpacity(0.12),
      pressed: primary.withOpacity(0.22),
    );
  }
}

bool _isValidGlassMode(String mode) {
  return mode == glassModePerformance ||
      mode == _glassModeBalanced ||
      mode == glassModePretty;
}

bool _isValidAccentMode(String mode) {
  return mode == _accentModeWhite ||
      mode == _accentModeChampagne ||
      mode == _accentModeBlue ||
      mode == _accentModePink;
}

Color _accentColorForMode(String mode) {
  if (mode == _accentModeWhite) return _accentWhite;
  if (mode == _accentModeBlue) return _accentBlue;
  if (mode == _accentModePink) return _accentPink;
  return _accentChampagne;
}

String _accentModeLabelForMode(String mode) {
  if (mode == _accentModeWhite) return 'White';
  if (mode == _accentModeBlue) return 'Soft Blue';
  if (mode == _accentModePink) return 'Pink';
  return 'Champagne';
}

List<Color> getAlbumGradient(String name) {
  int hash = 0;
  for (int i = 0; i < name.length; i++) {
    hash = name.codeUnitAt(i) + ((hash << 5) - hash);
  }

  final base = (hash % 360).abs().toDouble();

  return [
    HSLColor.fromAHSL(1.0, base, 0.46, 0.30).toColor(),
    HSLColor.fromAHSL(1.0, (base + 42) % 360, 0.52, 0.44).toColor(),
    HSLColor.fromAHSL(1.0, (base + 120) % 360, 0.38, 0.34).toColor(),
    HSLColor.fromAHSL(1.0, (base + 210) % 360, 0.34, 0.24).toColor(),
  ];
}

List<Color> _safeColors(List<Color> colors) {
  if (colors.length >= 4) return colors;
  return _defaultDynamicColors;
}

String _colorToHex(Color color) {
  return color.value.toRadixString(16).padLeft(8, '0');
}

Color? _colorFromHex(String value) {
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}
