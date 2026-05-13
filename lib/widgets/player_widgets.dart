part of '../main.dart';

// ─── Vinyl Disc ─────────────────────────────────────────────────────────────
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
    final centerSize = size * 0.24;

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
            _VinylRing(size: size * 0.92, opacity: 0.04),
            _VinylRing(size: size * 0.82, opacity: 0.05),
            _VinylRing(size: size * 0.72, opacity: 0.04),
            _VinylRing(size: size * 0.62, opacity: 0.05),
            _VinylRing(size: size * 0.52, opacity: 0.04),
            _VinylRing(size: size * 0.42, opacity: 0.05),
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
              border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: coverUrl != null && coverUrl!.isNotEmpty
                ? Image(
                    image: _coverProvider(coverUrl!)!,
                    fit: BoxFit.cover,
                    width: centerSize,
                    height: centerSize,
                  )
                : Icon(
                    Icons.music_note_rounded,
                    size: size * 0.18,
                    color: Colors.white.withOpacity(0.50),
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

  const _VinylRing({
    required this.size,
    this.opacity = 0.055,
  });

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

// ─── Interactive Cover Art with Vinyl Animation ───────────────────────────────
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

    _spinSpeedAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _vinylSlideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _coverSlideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
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
                  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
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
                final vinylSlideOffset = _vinylSlideAnimation.value * (widget.size * 0.35);
                return Transform.translate(
                  offset: Offset(vinylSlideOffset, 0),
                  child: Opacity(
                    opacity: _vinylSlideAnimation.value,
                    child: AnimatedBuilder(
                      animation: _spinController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _spinController.value * 6.283 * _spinSpeedAnimation.value,
                          child: child,
                        );
                      },
                      child: child,
                    ),
                  ),
                );
              },
              child: _VinylDisc(
                size: widget.size,
                coverUrl: widget.coverUrl,
                colors: widget.colors,
                showGrooves: true,
              ),
            ),
            AnimatedBuilder(
              animation: _slideController,
              builder: (context, child) {
                final coverSlideOffset = _coverSlideAnimation.value * (widget.size * -0.15);
                return Transform.translate(
                  offset: Offset(coverSlideOffset, 0),
                  child: child,
                );
              },
              child: coverLayer(),
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

// ─── Lyrics Sheet ───────────────────────────────────────────────────────────
class _LyricsResult {
  final String trackName;
  final String artistName;
  final String? plainLyrics;
  final String? syncedLyrics;

  const _LyricsResult({
    required this.trackName,
    required this.artistName,
    this.plainLyrics,
    this.syncedLyrics,
  });

  bool get hasSynced => syncedLyrics != null && syncedLyrics!.trim().isNotEmpty;
  bool get hasPlain => plainLyrics != null && plainLyrics!.trim().isNotEmpty;
}

class _LyricLine {
  final Duration time;
  final String text;

  const _LyricLine({required this.time, required this.text});
}

class _LyricsSheet extends StatefulWidget {
  final AudioPlayer player;
  final Map<String, String> meta;
  final List<Color> colors;

  const _LyricsSheet({
    required this.player,
    required this.meta,
    required this.colors,
  });

  @override
  State<_LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<_LyricsSheet> {
  late final Future<_LyricsResult?> _lyricsFuture;
  final ScrollController _scrollController = ScrollController();
  int _lastActiveLine = -1;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = _fetchLyrics();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<_LyricsResult?> _fetchLyrics() async {
    final title = (widget.meta['title'] ?? '').trim();
    final artist = (widget.meta['artist'] ?? '').trim();

    if (title.isEmpty) return null;

    final params = <String, String>{'track_name': title};

    if (artist.isNotEmpty && artist != 'Unknown Artist') {
      params['artist_name'] = artist;
    }

    Future<List<dynamic>> request(Uri uri) async {
      final res = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'InfameApp/1.0',
        },
      );

      if (res.statusCode != 200) return [];
      final decoded = json.decode(res.body);
      return decoded is List ? decoded : [];
    }

    List<dynamic> results = await request(Uri.https('lrclib.net', '/api/search', params));

    if (results.isEmpty) {
      final fallbackQuery = artist.isNotEmpty && artist != 'Unknown Artist'
          ? '$artist $title'
          : title;
      results = await request(Uri.https('lrclib.net', '/api/search', {'q': fallbackQuery}));
    }

    if (results.isEmpty) return null;

    Map<String, dynamic>? best;

    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;
      final synced = item['syncedLyrics'];
      if (synced is String && synced.trim().isNotEmpty) {
        best = item;
        break;
      }
      best ??= item;
    }

    if (best == null) return null;

    return _LyricsResult(
      trackName: (best['trackName'] ?? title).toString(),
      artistName: (best['artistName'] ?? artist).toString(),
      plainLyrics: best['plainLyrics']?.toString(),
      syncedLyrics: best['syncedLyrics']?.toString(),
    );
  }

  List<_LyricLine> _parseSyncedLyrics(String raw) {
    final lines = <_LyricLine>[];

    for (final rawLine in raw.split(String.fromCharCode(10))) {
      final line = rawLine.trim();
      if (!line.startsWith('[')) continue;

      final end = line.indexOf(']');
      if (end <= 1) continue;

      final stamp = line.substring(1, end);
      final text = line.substring(end + 1).trim();
      if (text.isEmpty) continue;

      final timeParts = stamp.split(':');
      if (timeParts.length != 2) continue;

      final minutes = int.tryParse(timeParts[0]) ?? 0;
      final secondParts = timeParts[1].split('.');
      final seconds = int.tryParse(secondParts[0]) ?? 0;
      final fraction = secondParts.length > 1 ? secondParts[1] : '0';
      final padded = fraction.padRight(3, '0');
      final millis = int.tryParse(padded.substring(0, 3)) ?? 0;

      lines.add(
        _LyricLine(
          time: Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
          text: text,
        ),
      );
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  int _activeLineIndex(List<_LyricLine> lines, Duration pos) {
    if (lines.isEmpty) return -1;

    int active = 0;
    for (int i = 0; i < lines.length; i++) {
      if (pos >= lines[i].time) {
        active = i;
      } else {
        break;
      }
    }

    return active;
  }

  void _scrollToActiveLine(int active) {
    if (active == _lastActiveLine || !_scrollController.hasClients) return;
    _lastActiveLine = active;

    final target = (active * 44.0).clamp(0.0, _scrollController.position.maxScrollExtent);

    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _safeColors(widget.colors);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: BoxDecoration(
          color: _bg.withOpacity(0.96),
          borderRadius: BorderRadius.zero,
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.12))),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors[0].withOpacity(0.34),
              _bg.withOpacity(0.98),
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 34),
                    ),
                    const Spacer(),
                    Text(
                      'Lyrics',
                      style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
                Text(
                  '${widget.meta['title'] ?? ''} • ${widget.meta['artist'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: _textSub,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: FutureBuilder<_LyricsResult?>(
                    future: _lyricsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Center(child: CircularProgressIndicator(color: colors[1]));
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Could not load lyrics.',
                            style: GoogleFonts.inter(color: _textSub, fontWeight: FontWeight.w700),
                          ),
                        );
                      }

                      final result = snapshot.data;
                      if (result == null || (!result.hasSynced && !result.hasPlain)) {
                        return Center(
                          child: Text(
                            'No lyrics found for this track.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: _textSub, fontWeight: FontWeight.w700),
                          ),
                        );
                      }

                      if (result.hasSynced) {
                        final lines = _parseSyncedLyrics(result.syncedLyrics!);

                        if (lines.isNotEmpty) {
                          return StreamBuilder<Duration>(
                            stream: widget.player.positionStream,
                            builder: (context, posSnap) {
                              final pos = posSnap.data ?? Duration.zero;
                              final active = _activeLineIndex(lines, pos);

                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _scrollToActiveLine(active);
                              });

                              return ListView.builder(
                                controller: _scrollController,
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.only(top: 80, bottom: 160),
                                itemCount: lines.length,
                                itemBuilder: (context, i) {
                                  final isActive = i == active;
                                  return AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOutCubic,
                                    style: GoogleFonts.inter(
                                      fontSize: isActive ? 23 : 19,
                                      height: 1.35,
                                      fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                                      color: isActive ? Colors.white : Colors.white.withOpacity(0.38),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Text(lines[i].text),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        }
                      }

                      final plain = result.plainLyrics ?? result.syncedLyrics ?? '';

                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Text(
                          plain,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            height: 1.55,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withOpacity(0.86),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Lyrics by LRCLIB',
                  style: GoogleFonts.inter(
                    color: _textSub,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Queue Sheet ────────────────────────────────────────────────────────────
class _QueueSheet extends StatelessWidget {
  final List<Color> colors;
  final Future<void> Function(drive.File track, int index) onPlayFromQueue;
  final Map<String, int> knownTrackDurationsMs;
  final Map<String, Duration> knownTrackDurations;

  const _QueueSheet({
    required this.colors,
    required this.onPlayFromQueue,
    required this.knownTrackDurationsMs,
    required this.knownTrackDurations,
  });

  @override
  Widget build(BuildContext context) {
    final safe = _safeColors(colors);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.78,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.zero,
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.12))),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              safe[0].withOpacity(0.30),
              _bg.withOpacity(0.98),
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 34),
                    ),
                    const Spacer(),
                    Text(
                      'Queue',
                      style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
                Text(
                  '${_nowPlaying.queue.length} tracks',
                  style: GoogleFonts.inter(
                    color: _textSub,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: ListenableBuilder(
                    listenable: _nowPlaying,
                    builder: (context, _) {
                      if (_nowPlaying.queue.isEmpty) {
                        return Center(
                          child: Text(
                            'Queue is empty.',
                            style: GoogleFonts.inter(color: _textSub, fontWeight: FontWeight.w700),
                          ),
                        );
                      }

                      return ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: _nowPlaying.queue.length,
                        itemBuilder: (context, i) {
                          final track = _nowPlaying.queue[i];
                          final meta = DriveUtils.getTrackMeta(track);
                          final isActive = i == _nowPlaying.queueIndex;
                          final trackKey = track.id ?? '';
                          
                          // Get duration from cache
                          Duration? duration;
                          final durationMs = knownTrackDurationsMs[trackKey];
                          if (durationMs != null && durationMs > 0) {
                            duration = Duration(milliseconds: durationMs);
                          } else {
                            duration = knownTrackDurations[trackKey];
                          }

                          return GestureDetector(
                            onTap: () async {
                              await onPlayFromQueue(track, i);
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: isActive ? Colors.white.withOpacity(0.11) : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isActive ? safe[1].withOpacity(0.40) : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '${i + 1}',
                                      style: GoogleFonts.inter(
                                        color: isActive ? safe[1] : _textSub,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          meta['title'] ?? 'Unknown',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            color: isActive ? safe[1] : _textPri,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          meta['artist'] ?? 'Unknown Artist',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            color: _textSub,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (duration != null)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Text(
                                        '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                                        style: GoogleFonts.inter(
                                          color: _textSub,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (isActive)
                                    Icon(Icons.graphic_eq_rounded, color: safe[1], size: 22),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Floating Player Bar ────────────────────────────────────────────────────
class _PlayerFloatingBar extends StatelessWidget {
  final AudioPlayer player;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final Future<void> Function(drive.File track, int index) onPlayFromQueue;
  final bool isDarkMode;
  final Map<String, int> knownTrackDurationsMs;
  final Map<String, Duration> knownTrackDurations;

  const _PlayerFloatingBar({
    required this.player,
    required this.onNext,
    required this.onPrev,
    required this.onPlayFromQueue,
    required this.isDarkMode,
    required this.knownTrackDurationsMs,
    required this.knownTrackDurations,
  });

  void _openFullScreenPlayer(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A0A0F),
      barrierColor: Colors.black.withOpacity(0.76),
      builder: (_) {
        return _FullScreenPlayerSheet(
          player: player,
          onNext: onNext,
          onPrev: onPrev,
          onPlayFromQueue: onPlayFromQueue,
          isDarkMode: isDarkMode,
          knownTrackDurationsMs: knownTrackDurationsMs,
          knownTrackDurations: knownTrackDurations,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _nowPlaying,
      builder: (ctx, _) {
        final track = _nowPlaying.track;
        if (track == null) return const SizedBox.shrink();

        final meta = DriveUtils.getTrackMeta(track);
        final coverUrl = _nowPlaying.currentCoverUrl;
        final colors = _safeColors(_nowPlaying.dynamicColors);

        return StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (_, stateSnap) {
            final state = stateSnap.data;
            final isPlaying = state?.playing ?? false;
            final isLoading = state?.processingState == ProcessingState.loading ||
                state?.processingState == ProcessingState.buffering;

            final glowColor = isDarkMode ? _neonPurple : _neonMagenta;
            final bgColor = isDarkMode ? _darkBg : _lightSurface;

            return GestureDetector(
              onTap: () => _openFullScreenPlayer(context),
              behavior: HitTestBehavior.opaque,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: Container(
                    height: 86,
                    decoration: BoxDecoration(
                      color: isDarkMode 
                          ? bgColor.withOpacity(0.40) 
                          : _lightSurface.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: glowColor.withOpacity(0.30), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: glowColor.withOpacity(0.18),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 11, 10, 13),
                          child: Row(
                            children: [
                              AspectRatio(
                                aspectRatio: 1.0,
                                child: _PremiumCoverArt(
                                  heroTag: 'now_playing_artwork',
                                  coverUrl: coverUrl,
                                  colors: colors,
                                  size: 62,
                                  radius: kArtworkRadius,
                                  shadow: false,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 240),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  child: Column(
                                    key: ValueKey('${track.id}_${meta['title']}_${meta['artist']}'),
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        meta['title'] ?? 'Unknown',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 15.5,
                                          height: 1.05,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: -0.35,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        meta['artist'] ?? 'Unknown Artist',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          height: 1.05,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white.withOpacity(0.70),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  if (isLoading) return;
                                  HapticFeedback.lightImpact();
                                  isPlaying ? player.pause() : player.play();
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.20),
                                    shape: BoxShape.circle,
                                  ),
                                  child: isLoading
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.3,
                                          ),
                                        )
                                      : Icon(
                                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  onNext();
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.20),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.skip_next_rounded, color: Colors.white, size: 29),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 5,
                          child: StreamBuilder<Duration>(
                            stream: player.positionStream,
                            builder: (_, posSnap) {
                              return StreamBuilder<Duration?>(
                                stream: player.durationStream,
                                builder: (_, durSnap) {
                                  final dur = durSnap.data ?? Duration.zero;
                                  final pos = posSnap.data ?? Duration.zero;
                                  final prog = dur.inMilliseconds > 0
                                      ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                                      : 0.0;
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      value: prog,
                                      minHeight: 3,
                                      backgroundColor: Colors.white.withOpacity(0.15),
                                      valueColor: AlwaysStoppedAnimation<Color>(glowColor.withOpacity(0.80)),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PremiumCoverArt extends StatelessWidget {
  final String? heroTag;
  final String? coverUrl;
  final List<Color> colors;
  final double size;
  final double radius;
  final bool shadow;

  const _PremiumCoverArt({
    this.heroTag,
    required this.coverUrl,
    required this.colors,
    required this.size,
    required this.radius,
    this.shadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final provider = _coverProvider(coverUrl);
    final safe = _safeColors(colors);

    Widget artwork = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [safe[0], safe[1], safe[2]],
        ),
        boxShadow: shadow
            ? [
                // Soft diffused drop-shadow using album colors
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
                // Dark muted lift from album
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
                  size: size * 0.32,
                ),
              )
            : Image(
                key: ValueKey(coverUrl),
                image: provider,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.high,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
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
                      size: size * 0.32,
                    ),
                  );
                },
              ),
      ),
    );

    if (heroTag != null) {
      artwork = Hero(tag: heroTag!, child: artwork);
    }

    return artwork;
  }
}

// ─── Fullscreen Player Sheet (Apple Music iOS 17 Style) ─────────────────────
class _FullScreenPlayerSheet extends StatefulWidget {
  final AudioPlayer player;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final Future<void> Function(drive.File track, int index) onPlayFromQueue;
  final bool isDarkMode;
  final Map<String, int> knownTrackDurationsMs;
  final Map<String, Duration> knownTrackDurations;

  const _FullScreenPlayerSheet({
    required this.player,
    required this.onNext,
    required this.onPrev,
    required this.onPlayFromQueue,
    required this.isDarkMode,
    required this.knownTrackDurationsMs,
    required this.knownTrackDurations,
  });

  @override
  State<_FullScreenPlayerSheet> createState() => _FullScreenPlayerSheetState();
}

class _FullScreenPlayerSheetState extends State<_FullScreenPlayerSheet> {
  String _formatTime(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(hours > 0 ? 2 : 1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  void _openLyricsSheet(
    BuildContext context,
    Map<String, String> meta,
    List<Color> colors,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.70),
      builder: (_) {
        return _LyricsSheet(
          player: widget.player,
          meta: meta,
          colors: colors,
        );
      },
    );
  }

  void _openQueueSheet(BuildContext context, List<Color> colors) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.70),
      builder: (_) {
        return _QueueSheet(
          colors: colors,
          onPlayFromQueue: widget.onPlayFromQueue,
          knownTrackDurationsMs: widget.knownTrackDurationsMs,
          knownTrackDurations: widget.knownTrackDurations,
        );
      },
    );
  }

  void _openMoreActions(
    BuildContext context,
    Map<String, String> meta,
    List<Color> colors,
  ) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (sheetContext) {
        final safe = _safeColors(colors);
        final accent = safe[1];
        Widget action({
          required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap,
        }) {
          return ListTile(
            leading: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.07),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            title: Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: GoogleFonts.inter(
                color: Colors.white.withOpacity(0.48),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: onTap,
          );
        }

        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF101012),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.44),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                action(
                  icon: Icons.lyrics_rounded,
                  title: 'Lyrics',
                  subtitle: 'Open synced or plain lyrics',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openLyricsSheet(context, meta, colors);
                  },
                ),
                action(
                  icon: Icons.queue_music_rounded,
                  title: 'Queue',
                  subtitle: 'View upcoming tracks',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openQueueSheet(context, colors);
                  },
                ),
                action(
                  icon: Icons.album_rounded,
                  title: 'Sleeve mode',
                  subtitle: 'Coming later as a player style',
                  onTap: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _nowPlaying,
      builder: (context, _) {
        final track = _nowPlaying.track;
        if (track == null) return const SizedBox.shrink();

        final meta = DriveUtils.getTrackMeta(track);
        final coverUrl = _nowPlaying.currentCoverUrl;
        final colors = _safeColors(_nowPlaying.dynamicColors);
        final provider = _coverProvider(coverUrl);
        final media = MediaQuery.of(context);
        final width = media.size.width;
        final height = media.size.height;
        final artworkSize = math.min(width - 64, height * 0.38);

        return StreamBuilder<PlayerState>(
          stream: widget.player.playerStateStream,
          builder: (context, stateSnap) {
            final state = stateSnap.data;
            final isPlaying = state?.playing ?? false;
            final isLoading = state?.processingState == ProcessingState.loading ||
                state?.processingState == ProcessingState.buffering;

            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: widget.isDarkMode ? const Color(0xFF050508) : _lightBg,
                      child: widget.isDarkMode
                          ? _NeonBlobBackground(isDarkMode: true)
                          : _NeonBlobBackground(isDarkMode: false),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: widget.isDarkMode
                              ? [
                                  Colors.black.withOpacity(0.10),
                                  Colors.black.withOpacity(0.42),
                                ]
                              : [
                                  _lightSurface.withOpacity(0.0),
                                  _lightSurface.withOpacity(0.0),
                                ],
                        ),
                      ),
                    ),
                  ),
                  if (provider != null)
                    Positioned.fill(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 160, sigmaY: 160),
                        child: Opacity(
                          opacity: widget.isDarkMode ? 0.12 : 0.08,
                          child: Transform.scale(
                            scale: 2.0,
                            child: Image(
                              image: provider,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: widget.isDarkMode
                              ? [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.24),
                                  Colors.black.withOpacity(0.72),
                                ]
                              : [
                                  Colors.transparent,
                                  _lightBg.withOpacity(0.0),
                                  _lightBg.withOpacity(0.0),
                                ],
                          stops: const [0.0, 0.35, 1.0],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: height * 0.96,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          26,
                          12,
                          26,
                          math.max(22, media.padding.bottom + 6),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 42,
                              height: 5,
                              decoration: BoxDecoration(
                                color: widget.isDarkMode ? Colors.white.withOpacity(0.34) : _lightAccentPink.withOpacity(0.34),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => Navigator.maybePop(context),
                                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: widget.isDarkMode ? Colors.white.withOpacity(0.88) : _lightText.withOpacity(0.88), size: 34),
                                ),
                                const Spacer(),
                                Text(
                                  'NOW PLAYING',
                                  style: GoogleFonts.inter(
                                    color: widget.isDarkMode ? Colors.white.withOpacity(0.46) : _lightSubtext.withOpacity(0.60),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _openMoreActions(context, meta, colors),
                                  icon: Icon(Icons.more_horiz_rounded, color: widget.isDarkMode ? Colors.white.withOpacity(0.88) : _lightText.withOpacity(0.88), size: 30),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Expanded(
                              flex: 8,
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: 1.0,
                                  child: _InteractiveCoverArt(
                                    key: ValueKey('full_cover_$coverUrl'),
                                    heroTag: 'now_playing_artwork',
                                    coverUrl: coverUrl,
                                    colors: colors,
                                    size: math.min(artworkSize + 18, width - 48),
                                    shadow: true,
                                    isPlaying: isPlaying,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            Column(
                              children: [
                                Text(
                                  meta['title'] ?? 'Unknown',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 28,
                                    height: 1.05,
                                    fontWeight: FontWeight.w900,
                                    color: widget.isDarkMode ? Colors.white.withOpacity(0.95) : _lightText,
                                    letterSpacing: -0.85,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  meta['artist'] ?? 'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: widget.isDarkMode ? Colors.white.withOpacity(0.60) : _lightSubtext,
                                    letterSpacing: -0.15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            StreamBuilder<Duration>(
                              stream: widget.player.positionStream,
                              builder: (_, posSnap) {
                                return StreamBuilder<Duration?>(
                                  stream: widget.player.durationStream,
                                  builder: (_, durSnap) {
                                    final pos = posSnap.data ?? Duration.zero;
                                    final dur = durSnap.data ?? Duration.zero;
                                    final max = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
                                    final value = pos.inMilliseconds.toDouble().clamp(0.0, max);
                                    final remaining = dur > pos ? dur - pos : Duration.zero;

                                    return Column(
                                      children: [
                                        Slider(
                                          value: value,
                                          max: max,
                                          activeColor: widget.isDarkMode ? Colors.white.withOpacity(0.88) : _lightAccentPink,
                                          inactiveColor: widget.isDarkMode ? Colors.white.withOpacity(0.14) : _lightAccentPink.withOpacity(0.15),
                                          onChanged: (v) {
                                            widget.player.seek(Duration(milliseconds: v.toInt()));
                                          },
                                        ),
                                        Transform.translate(
                                          offset: const Offset(0, -7),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _formatTime(pos),
                                                style: GoogleFonts.inter(color: widget.isDarkMode ? Colors.white.withOpacity(0.52) : _lightSubtext, fontSize: 11.5, fontWeight: FontWeight.w700),
                                              ),
                                              Text(
                                                '-${_formatTime(remaining)}',
                                                style: GoogleFonts.inter(color: widget.isDarkMode ? Colors.white.withOpacity(0.52) : _lightSubtext, fontSize: 11.5, fontWeight: FontWeight.w700),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.skip_previous_rounded, size: 54, color: widget.isDarkMode ? Colors.white.withOpacity(0.92) : _lightAccentPink.withOpacity(0.92)),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    widget.onPrev();
                                  },
                                ),
                                const SizedBox(width: 28),
                                GestureDetector(
                                  onTap: () {
                                    if (isLoading) return;
                                    HapticFeedback.mediumImpact();
                                    isPlaying ? widget.player.pause() : widget.player.play();
                                  },
                                  behavior: HitTestBehavior.opaque,
                                  child: Container(
                                    width: 86,
                                    height: 86,
                                    decoration: BoxDecoration(
                                      color: widget.isDarkMode ? Colors.white.withOpacity(0.12) : _lightAccentPink.withOpacity(0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: isLoading
                                          ? const SizedBox(
                                              width: 48,
                                              height: 48,
                                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.8),
                                            )
                                          : Icon(
                                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                              color: widget.isDarkMode ? Colors.white : _lightAccentPink,
                                              size: 72,
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 28),
                                IconButton(
                                  icon: Icon(Icons.skip_next_rounded, size: 54, color: widget.isDarkMode ? Colors.white.withOpacity(0.92) : _lightAccentPink.withOpacity(0.92)),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    widget.onNext();
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _SystemVolumeSlider(isDarkMode: widget.isDarkMode),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _PremiumActionButton(
                                  icon: Icons.chat_bubble_outline_rounded,
                                  label: 'Lyrics',
                                  onTap: () => _openLyricsSheet(context, meta, colors),
                                  colors: colors,
                                  isDarkMode: widget.isDarkMode,
                                ),
                                _PremiumActionButton(
                                  icon: Icons.format_list_bulleted_rounded,
                                  label: 'Queue',
                                  onTap: () => _openQueueSheet(context, colors),
                                  colors: colors,
                                  isDarkMode: widget.isDarkMode,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _PremiumActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final List<Color> colors;
  final bool isDarkMode;

  const _PremiumActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withOpacity(0.10) : _lightSurface.withOpacity(0.60),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDarkMode ? Colors.white.withOpacity(0.08) : _lightAccentPink.withOpacity(0.20),
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: isDarkMode ? Colors.white.withOpacity(0.92) : _lightAccentPink, size: 22),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: isDarkMode ? Colors.white.withOpacity(0.70) : _lightText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioQualityBadge extends StatelessWidget {
  final drive.File track;
  final Duration? duration;
  final Color accent;

  const _AudioQualityBadge({
    required this.track,
    required this.duration,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final label = DriveUtils.audioQualityLabel(track, duration)
        .replaceAll(' • ', '  •  ')
        .toUpperCase();

    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        color: Colors.white.withOpacity(0.58),
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ─── System Volume Slider ───────────────────────────────────────────────────
class _SystemVolumeSlider extends StatefulWidget {
  final bool isDarkMode;
  const _SystemVolumeSlider({this.isDarkMode = true});

  @override
  State<_SystemVolumeSlider> createState() => _SystemVolumeSliderState();
}

class _SystemVolumeSliderState extends State<_SystemVolumeSlider> {
  double _volume = 0.5;

  @override
  void initState() {
    super.initState();
    VolumeController.instance.showSystemUI = false;
    VolumeController.instance.getVolume().then((vol) {
      if (mounted) setState(() => _volume = vol);
    });
    VolumeController.instance.addListener((vol) {
      if (mounted) setState(() => _volume = vol);
    }, fetchInitialVolume: true);
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: _volume,
      activeColor: widget.isDarkMode ? Colors.white.withOpacity(0.64) : _lightAccentPink,
      inactiveColor: widget.isDarkMode ? Colors.white.withOpacity(0.12) : _lightAccentPink.withOpacity(0.15),
      onChanged: (v) {
        VolumeController.instance.setVolume(v);
        setState(() => _volume = v);
      },
    );
  }
}
