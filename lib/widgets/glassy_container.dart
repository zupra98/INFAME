import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

const String glassModePerformance = 'performance';
const String glassModeBalanced = 'balanced';
const String glassModePretty = 'pretty';

final ValueNotifier<String> glassModeNotifier =
    ValueNotifier<String>(glassModeBalanced);

final Color glassBorder = Colors.white.withOpacity(0.12);

// Light mode colors
const Color _lightBg = Color(0xFFFFFBFF);
const Color _lightSurface = Color(0xFFFFFFFF);
const Color _lightSurfaceSoft = Color(0xFFFFF1F8);
const Color _lightAccentPink = Color(0xFFFF4FA3);
const Color _lightAccentPurple = Color(0xFF9B5CFF);
const Color _lightAccentMagenta = Color(0xFFE94DFF);
const Color _lightText = Color(0xFF20151E);
const Color _lightSubtext = Color(0xFF76616F);

// Dark mode colors
const Color _darkBg = Color(0xFF0D0D11);

class GlassyContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double blur;
  final double borderWidth;
  final Color? customBorder;
  final Color? customColor;
  final bool allowRealBlur;

  const GlassyContainer({
    super.key,
    required this.child,
    this.radius = 16,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.blur = 14,
    this.borderWidth = 1,
    this.customBorder,
    this.customColor,
    this.allowRealBlur = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: margin,
      child: ValueListenableBuilder<String>(
        valueListenable: glassModeNotifier,
        builder: (context, mode, _) {
          final useRealBlur = allowRealBlur && mode != glassModePerformance;
          final effectiveBlur =
              mode == glassModePretty ? blur : math.min(blur, 10).toDouble();

          final effectiveColor = customColor ??
              (mode == glassModePerformance
                  ? (isDarkMode ? Colors.white.withOpacity(0.055) : _lightSurface.withOpacity(0.55))
                  : (isDarkMode ? Colors.white.withOpacity(0.075) : _lightSurface.withOpacity(0.72)));

          final effectiveBorder = customBorder ??
              (mode == glassModePretty
                  ? (isDarkMode ? Colors.white.withOpacity(0.18) : _lightAccentPink.withOpacity(0.22))
                  : (isDarkMode ? glassBorder : _lightAccentPink.withOpacity(0.18)));

          final shadowColor = isDarkMode ? Colors.black.withOpacity(0.16) : _lightAccentPink.withOpacity(0.12);

          final decorated = Container(
            padding: padding,
            decoration: BoxDecoration(
              color: effectiveColor,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: effectiveBorder, width: borderWidth),
              boxShadow: mode == glassModePerformance
                  ? const []
                  : [
                      BoxShadow(
                        color: shadowColor,
                        blurRadius: mode == glassModePretty ? 24 : 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: child,
          );

          if (!useRealBlur) return decorated;

          return ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: effectiveBlur,
                sigmaY: effectiveBlur,
              ),
              child: decorated,
            ),
          );
        },
      ),
    );
  }
}