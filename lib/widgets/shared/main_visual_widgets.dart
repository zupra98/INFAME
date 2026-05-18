part of '../../main.dart';

class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HitTestBehavior behavior;
  final double pressedScale;
  final Duration duration;
  final Curve curve;
  final bool enableHaptics;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.behavior = HitTestBehavior.opaque,
    this.pressedScale = 0.97,
    this.duration = const Duration(milliseconds: 120),
    this.curve = Curves.easeOutCubic,
    this.enableHaptics = true,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final duration = _reduceMotion ? Duration.zero : widget.duration;
    final scale = _reduceMotion ? 1.0 : (_pressed ? widget.pressedScale : 1.0);

    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: widget.onTap == null
          ? null
          : (_) {
              _setPressed(true);
            },
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              _setPressed(false);
            },
      onTapCancel: widget.onTap == null
          ? null
          : () {
              _setPressed(false);
            },
      onLongPress: widget.onLongPress,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.enableHaptics) {
                HapticFeedback.selectionClick();
              }
              widget.onTap?.call();
            },
      child: AnimatedScale(
        scale: scale,
        duration: duration,
        curve: widget.curve,
        child: widget.child,
      ),
    );
  }
}

class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final Offset beginOffset;
  final bool enabled;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 180),
    this.delay = Duration.zero,
    this.curve = Curves.easeOutCubic,
    this.beginOffset = const Offset(0, 0.04),
    this.enabled = true,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> {
  bool _visible = false;
  bool _scheduled = false;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(covariant FadeSlideIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _visible = false;
      _scheduled = false;
      _scheduleReveal();
    }
  }

  void _scheduleReveal() {
    if (!widget.enabled || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _visible) return;
      if (widget.delay > Duration.zero) {
        await Future<void>.delayed(widget.delay);
        if (!mounted) return;
      }
      setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion || !widget.enabled) return widget.child;

    final duration = widget.duration;
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: duration,
      curve: widget.curve,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : widget.beginOffset,
        duration: duration,
        curve: widget.curve,
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}

class AnimatedContentSwap extends StatelessWidget {
  final Object? swapKey;
  final Widget child;
  final Duration duration;
  final Curve switchInCurve;
  final Curve switchOutCurve;

  const AnimatedContentSwap({
    super.key,
    required this.swapKey,
    required this.child,
    this.duration = const Duration(milliseconds: 180),
    this.switchInCurve = Curves.easeOutCubic,
    this.switchOutCurve = Curves.easeInCubic,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : duration,
      switchInCurve: switchInCurve,
      switchOutCurve: switchOutCurve,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      child: KeyedSubtree(
        key: ValueKey(swapKey ?? child.key ?? child.hashCode),
        child: child,
      ),
    );
  }
}

extension _MainVisualWidgetsExtension on _MainScreenState {
  void _showSuccessFromPart(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.inter(
            color: Colors.black,
            fontWeight: FontWeight.w900,
          ),
        ),
        backgroundColor: _accentDefault,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorFromPart(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: _textPri)),
        backgroundColor: _pink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showCoverZoomFromPart(
    String heroTag,
    String coverUrl,
    List<Color> gradient,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.86),
        pageBuilder: (BuildContext context, _, __) {
          return GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Center(
              child: Hero(
                tag: heroTag,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.86,
                  height: MediaQuery.of(context).size.width * 0.86,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kArtworkRadius),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: gradient[0].withOpacity(0.50),
                        blurRadius: 45,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: coverUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(kArtworkRadius),
                          child: _coverImage(
                            coverUrl,
                            fit: BoxFit.cover,
                            cacheSize: _coverLargeDecodeSize,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGradientTextFromPart(
    String text, {
    required double size,
    double spacing = 0,
  }) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w900,
        color: _textPri,
        letterSpacing: spacing,
      ),
    );
  }
}
