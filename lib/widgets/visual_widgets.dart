part of '../main.dart';

class _NeonBlobBackground extends StatelessWidget {
  final bool isDarkMode;

  const _NeonBlobBackground({required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    final purpleOpacity = isDarkMode ? 0.8 : 0.6;
    final magentaOpacity = isDarkMode ? 0.7 : 0.5;

    return RepaintBoundary(
      child: Container(
        color: isDarkMode ? const Color(0xFF050508) : _lightBg,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Top Left Purple Blob
            Positioned(
              top: -130,
              left: -120,
              child: _BlurredBlob(
                size: 360,
                blur: 70,
                colors: isDarkMode
                    ? [
                        _neonPurple.withOpacity(purpleOpacity),
                        _neonMagenta.withOpacity(magentaOpacity * 0.5),
                        Colors.transparent,
                      ]
                    : [
                        _lightAccentPurple.withOpacity(purpleOpacity),
                        _lightAccentPink.withOpacity(magentaOpacity * 0.5),
                        Colors.transparent,
                      ],
              ),
            ),
            // Bottom Right Magenta Blob
            Positioned(
              bottom: -180,
              right: -160,
              child: _BlurredBlob(
                size: 420,
                blur: 85,
                colors: isDarkMode
                    ? [
                        _neonMagenta.withOpacity(magentaOpacity),
                        _neonPurple.withOpacity(purpleOpacity * 0.5),
                        Colors.transparent,
                      ]
                    : [
                        _lightAccentMagenta.withOpacity(magentaOpacity),
                        _lightAccentPurple.withOpacity(purpleOpacity * 0.5),
                        Colors.transparent,
                      ],
              ),
            ),
            // Bottom Left Purple Blob
            Positioned(
              bottom: -130,
              left: 20,
              child: _BlurredBlob(
                size: 380,
                blur: 75,
                colors: isDarkMode
                    ? [
                        _neonPurple.withOpacity(purpleOpacity * 0.6),
                        _neonMagenta.withOpacity(magentaOpacity * 0.4),
                        Colors.transparent,
                      ]
                    : [
                        _lightAccentPurple.withOpacity(purpleOpacity * 0.6),
                        _lightAccentPink.withOpacity(magentaOpacity * 0.4),
                        Colors.transparent,
                      ],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isDarkMode
                          ? [
                              Colors.black.withOpacity(0.10),
                              Colors.black.withOpacity(0.42),
                            ]
                          : [
                              Colors.white.withOpacity(0.10),
                              Colors.white.withOpacity(0.55),
                            ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlurredBlob extends StatelessWidget {
  final double size;
  final double blur;
  final List<Color> colors;

  const _BlurredBlob({
    required this.size,
    required this.blur,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: colors,
              stops: const [0.0, 0.48, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
