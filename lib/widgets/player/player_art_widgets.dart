part of '../../main.dart';

class _VinylDisc extends StatelessWidget {
  final double size;
  final String? coverUrl;
  final List<Color> colors;
  final bool showGrooves;

  const _VinylDisc({
    required this.size,
    required this.coverUrl,
    required this.colors,
    this.showGrooves = true,
  });

  @override
  Widget build(BuildContext context) {
    final safe = _safeColors(colors);
    final centerSize = size * 0.22;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Main vinyl disc with realistic gradient
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: Alignment(-0.3, -0.3),
                radius: 1.2,
                colors: [
                  const Color(0xFF1a1a1a),
                  const Color(0xFF0d0d0d),
                  const Color(0xFF050505),
                  Colors.black,
                ],
                stops: const [0.0, 0.3, 0.7, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: safe[0].withOpacity(0.38),
                  blurRadius: size * 0.16,
                  spreadRadius: size * 0.018,
                  offset: Offset(0, size * 0.055),
                ),
              ],
            ),
          ),
          // Angled glare/reflection
          Positioned.fill(
            child: ClipOval(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.0),
                      Colors.white.withOpacity(0.0),
                      Colors.white.withOpacity(0.0),
                      Colors.white.withOpacity(0.08),
                      Colors.white.withOpacity(0.0),
                    ],
                    stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
                    transform: const GradientRotation(0.5),
                  ),
                ),
              ),
            ),
          ),
          if (showGrooves) ...[
            _VinylRing(size: size * 0.92, opacity: 0.03),
            _VinylRing(size: size * 0.82, opacity: 0.04),
            _VinylRing(size: size * 0.72, opacity: 0.035),
            _VinylRing(size: size * 0.62, opacity: 0.04),
            _VinylRing(size: size * 0.52, opacity: 0.035),
            _VinylRing(size: size * 0.42, opacity: 0.04),
          ],
          // Center label with album artwork
          Container(
            width: centerSize,
            height: centerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: safe,
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 0.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: (() {
              final provider = coverUrl != null && coverUrl!.isNotEmpty
                  ? _coverProvider(coverUrl!)
                  : null;
              if (provider != null) {
                return Image(
                  image: provider,
                  fit: BoxFit.cover,
                  width: centerSize,
                  height: centerSize,
                );
              }
              return Icon(
                Icons.music_note_rounded,
                size: size * 0.18,
                color: Colors.white.withOpacity(0.50),
              );
            })(),
          ),
        ],
      ),
    );
  }
}

class _NowPlayingMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double height;
  final double pixelsPerSecond;
  final Duration pauseStart;
  final Duration pauseEnd;
  final TextAlign textAlign;

  const _NowPlayingMarqueeText({
    required this.text,
    required this.style,
    required this.height,
    this.pixelsPerSecond = 32,
    this.pauseStart = const Duration(milliseconds: 900),
    this.pauseEnd = const Duration(milliseconds: 900),
    this.textAlign = TextAlign.left,
  });

  @override
  State<_NowPlayingMarqueeText> createState() => _NowPlayingMarqueeTextState();
}

class _NowPlayingMarqueeTextState extends State<_NowPlayingMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _availableWidth = 0;
  double _textWidth = 0;
  bool _scrolling = false;
  bool _measureScheduled = false;
  String _lastText = '';
  TextStyle? _lastStyle;
  TextDirection? _lastDirection;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _NowPlayingMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.height != widget.height ||
        oldWidget.pixelsPerSecond != widget.pixelsPerSecond ||
        oldWidget.pauseStart != widget.pauseStart ||
        oldWidget.pauseEnd != widget.pauseEnd) {
      _resetScroll();
      _scheduleMeasure(force: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _resetScroll() {
    _controller.stop();
    _controller.value = 0;
    _scrolling = false;
  }

  void _scheduleMeasure({bool force = false}) {
    if (_measureScheduled && !force) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      _measure();
    });
  }

  void _measure() {
    final direction = Directionality.of(context);
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: direction,
      maxLines: 1,
      ellipsis: null,
    )..layout();

    final availableWidth = _availableWidth;
    final textWidth = painter.width;
    final shouldScroll = textWidth > availableWidth + 1;

    final changed = _textWidth != textWidth ||
        _availableWidth != availableWidth ||
        _scrolling != shouldScroll ||
        _lastText != widget.text ||
        _lastStyle != widget.style ||
        _lastDirection != direction;

    if (!changed) return;

    setState(() {
      _textWidth = textWidth;
      _availableWidth = availableWidth;
      _scrolling = shouldScroll;
      _lastText = widget.text;
      _lastStyle = widget.style;
      _lastDirection = direction;
    });

    if (_scrolling) {
      final overflow = math.max(0.0, _textWidth - _availableWidth);
      final scrollMs = math.max(
        4000,
        ((overflow / widget.pixelsPerSecond) * 1000).round(),
      );
      _controller.duration = Duration(
        milliseconds: widget.pauseStart.inMilliseconds +
            scrollMs +
            widget.pauseEnd.inMilliseconds +
            scrollMs,
      );
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _resetScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        if (_availableWidth != availableWidth || _lastText != widget.text) {
          _availableWidth = availableWidth;
          _scheduleMeasure();
        }

        final textWidget = Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          textAlign: widget.textAlign,
          style: widget.style,
        );

        if (!_scrolling || _textWidth <= _availableWidth + 1) {
          return Align(
            alignment: widget.textAlign == TextAlign.center
                ? Alignment.center
                : Alignment.centerLeft,
            child: SizedBox(
              width: availableWidth,
              height: widget.height,
              child: textWidget,
            ),
          );
        }

        final overflow = math.max(0.0, _textWidth - _availableWidth);
        final pauseStartMs = widget.pauseStart.inMilliseconds;
        final pauseEndMs = widget.pauseEnd.inMilliseconds;
        final scrollMs = math.max(
          1,
          ((overflow / widget.pixelsPerSecond) * 1000).round(),
        );
        final scrollBackMs = scrollMs;

        return ClipRect(
          child: SizedBox(
            width: availableWidth,
            height: widget.height,
            child: AnimatedBuilder(
              animation: _controller,
              child: SizedBox(
                width: _textWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: textWidget,
                ),
              ),
              builder: (context, child) {
                final totalMs = _controller.duration?.inMilliseconds ??
                    (pauseStartMs + scrollMs + pauseEndMs + scrollBackMs);
                final elapsedMs = (_controller.value * totalMs).clamp(
                  0.0,
                  totalMs.toDouble(),
                );
                double offset = 0;
                if (elapsedMs <= pauseStartMs) {
                  offset = 0;
                } else if (elapsedMs <= pauseStartMs + scrollMs) {
                  final local = (elapsedMs - pauseStartMs) / scrollMs;
                  offset = -overflow *
                      Curves.easeInOutCubic.transform(local.clamp(0.0, 1.0));
                } else if (elapsedMs <= pauseStartMs + scrollMs + pauseEndMs) {
                  offset = -overflow;
                } else {
                  final local =
                      (elapsedMs - pauseStartMs - scrollMs - pauseEndMs) /
                          scrollBackMs;
                  offset = -overflow +
                      overflow *
                          Curves.easeInOutCubic.transform(
                            local.clamp(0.0, 1.0),
                          );
                }

                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _NowPlayingMetaBlock extends StatelessWidget {
  final Map<String, String> meta;
  final bool isDarkMode;
  final bool compact;

  const _NowPlayingMetaBlock({
    required this.meta,
    required this.isDarkMode,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = (meta['title'] ?? 'Unknown').trim();
    final artist = (meta['artist'] ?? 'Unknown Artist').trim();
    final album = (meta['album'] ?? '').trim();

    final titleStyle = GoogleFonts.inter(
      fontSize: compact ? 20 : 22,
      height: 1.06,
      fontWeight: FontWeight.w900,
      color: isDarkMode ? Colors.white.withOpacity(0.95) : _lightText,
      letterSpacing: -0.75,
    );
    final artistStyle = GoogleFonts.inter(
      fontSize: compact ? 13 : 14,
      height: 1.08,
      fontWeight: FontWeight.w600,
      color: isDarkMode ? Colors.white.withOpacity(0.60) : _lightSubtext,
      letterSpacing: -0.12,
    );
    final albumStyle = GoogleFonts.inter(
      fontSize: compact ? 11.5 : 12,
      height: 1.06,
      fontWeight: FontWeight.w700,
      color: isDarkMode
          ? Colors.white.withOpacity(0.42)
          : _lightSubtext.withOpacity(0.92),
      letterSpacing: -0.05,
    );

    return SizedBox(
      height: compact ? 66 : 72,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: compact ? 23 : 25,
            child: _NowPlayingMarqueeText(
              text: title,
              style: titleStyle,
              height: compact ? 23 : 25,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: compact ? 16 : 17,
            child: _NowPlayingMarqueeText(
              text: artist,
              style: artistStyle,
              height: compact ? 16 : 17,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: compact ? 14 : 15,
            child: _NowPlayingMarqueeText(
              text: album.isEmpty ? ' ' : album,
              style: albumStyle,
              height: compact ? 14 : 15,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _VinylRing extends StatelessWidget {
  final double size;
  final double opacity;

  const _VinylRing({required this.size, this.opacity = 0.055});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(opacity), width: 1),
      ),
    );
  }
}

// â”€â”€â”€ Interactive Cover Art with Vinyl Animation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _InteractiveCoverArt extends StatefulWidget {
  final String? heroTag;
  final String? coverUrl;
  final List<Color> colors;
  final double size;
  final bool shadow;
  final bool isPlaying;

  const _InteractiveCoverArt({
    super.key,
    this.heroTag,
    required this.coverUrl,
    required this.colors,
    required this.size,
    this.shadow = true,
    this.isPlaying = false,
  });

  @override
  State<_InteractiveCoverArt> createState() => _InteractiveCoverArtState();
}

class _InteractiveCoverArtState extends State<_InteractiveCoverArt>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _spinController;
  late Animation<double> _vinylSlideAnimation;
  late Animation<double> _coverSlideAnimation;
  late Animation<double> _spinSpeedAnimation;
  bool _vinylVisible = false;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _spinController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    );

    _spinSpeedAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _vinylSlideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _coverSlideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didUpdateWidget(_InteractiveCoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying && _vinylVisible) {
        _spinController.repeat();
      } else {
        _spinController.stop();
      }
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  void _toggleVinyl() {
    HapticFeedback.mediumImpact();
    setState(() {
      _vinylVisible = !_vinylVisible;
    });
    if (_vinylVisible) {
      _slideController.forward();
      if (widget.isPlaying) {
        _spinController.repeat();
      }
    } else {
      _slideController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final safe = _safeColors(widget.colors);
    final provider = _coverProvider(widget.coverUrl);

    Widget coverLayer() {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [safe[0], safe[1], safe[2]],
          ),
          boxShadow: widget.shadow
              ? [
                  BoxShadow(
                    color: safe[3].withOpacity(0.28),
                    blurRadius: 72,
                    spreadRadius: 4,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: safe[2].withOpacity(0.20),
                    blurRadius: 48,
                    spreadRadius: -8,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 32,
                    spreadRadius: -6,
                    offset: const Offset(0, 16),
                  ),
                ]
              : const [],
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: provider == null
              ? Center(
                  key: const ValueKey('empty_cover'),
                  child: Icon(
                    Icons.album_rounded,
                    color: Colors.white.withOpacity(0.42),
                    size: widget.size * 0.32,
                  ),
                )
              : Image(
                  key: ValueKey(widget.coverUrl),
                  image: provider,
                  width: widget.size,
                  height: widget.size,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.high,
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                    if (wasSynchronouslyLoaded) return child;
                    return AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      child: child,
                    );
                  },
                  errorBuilder: (_, __, ___) {
                    return Center(
                      child: Icon(
                        Icons.album_rounded,
                        color: Colors.white.withOpacity(0.42),
                        size: widget.size * 0.32,
                      ),
                    );
                  },
                ),
        ),
      );
    }

    Widget artwork = GestureDetector(
      onTap: _toggleVinyl,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedBuilder(
              animation: _slideController,
              builder: (context, child) {
                final vinylSlideOffset =
                    _vinylSlideAnimation.value * (widget.size * 0.27);
                return Transform.translate(
                  offset: Offset(vinylSlideOffset, 0),
                  child: Opacity(
                    opacity: _vinylSlideAnimation.value,
                    child: AnimatedBuilder(
                      animation: _spinController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _spinController.value *
                              6.283 *
                              _spinSpeedAnimation.value,
                          child: child,
                        );
                      },
                      child: child,
                    ),
                  ),
                );
              },
              child: _VinylDisc(
                size: widget.size * 0.95,
                coverUrl: widget.coverUrl,
                colors: widget.colors,
                showGrooves: true,
              ),
            ),
            AnimatedBuilder(
              animation: _slideController,
              builder: (context, child) {
                final coverSlideOffset =
                    _coverSlideAnimation.value * (widget.size * -0.09);
                return Transform.translate(
                  offset: Offset(coverSlideOffset, 0),
                  child: child,
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kArtworkRadius),
                child: coverLayer(),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.heroTag != null) {
      artwork = Hero(tag: widget.heroTag!, child: artwork);
    }

    return artwork;
  }
}

// â”€â”€â”€ Lyrics Sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
