part of '../main.dart';

extension _BackgroundWidgetsExtension on _MainScreenState {
  Widget _buildAppBackgroundFromPart(List<Color> colors,
      {bool signIn = false}) {
    final safe = _safeColors(colors);
    final glowOpacity = _glassMode == glassModePerformance ? 0.52 : 0.80;

    return Container(
      color: _bg,
      child: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF17171D),
                      Color.alphaBlend(safe[3].withOpacity(0.22), _bg),
                      Colors.black,
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_showBackgroundGlow) ...[
            Positioned(
                top: signIn ? -120 : -130,
                left: -130,
                child: ExcludeSemantics(
                  child: _buildBlob(safe[0], 360 * glowOpacity),
                )),
            Positioned(
                top: signIn ? 100 : 46,
                right: -150,
                child: ExcludeSemantics(
                  child: _buildBlob(safe[2], 310 * glowOpacity),
                )),
            Positioned(
                bottom: 90,
                right: -110,
                child: ExcludeSemantics(
                  child: _buildBlob(safe[1], 330 * glowOpacity),
                )),
            Positioned(
                bottom: -140,
                left: -130,
                child: ExcludeSemantics(
                  child: _buildBlob(safe[3], 320 * glowOpacity),
                )),
            if (_glassMode == glassModePretty)
              Positioned(
                  top: 260,
                  left: 36,
                  child: ExcludeSemantics(
                    child: _buildBlob(safe[1].withOpacity(0.8), 190),
                  )),
          ],
          Positioned.fill(
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(signIn ? 0.08 : 0.14),
                      Colors.black.withOpacity(0.22),
                      Colors.black.withOpacity(0.50),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlob(Color color, double size) {
    final opacity = _glassMode == glassModePerformance ? 0.18 : 0.28;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(opacity),
            color.withOpacity(opacity * 0.42),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}
