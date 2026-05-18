part of '../../main.dart';

class _PlayerFloatingBar extends StatelessWidget {
  final AudioPlayer player;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onOpenNowPlaying;
  final Future<void> Function(drive.File track, int index) onPlayFromQueue;
  final drive.File? Function() resolveMiniPlayerTrack;
  final bool isDarkMode;
  final Map<String, int> knownTrackDurationsMs;
  final Map<String, Duration> knownTrackDurations;

  const _PlayerFloatingBar({
    required this.player,
    required this.onNext,
    required this.onPrev,
    required this.onOpenNowPlaying,
    required this.onPlayFromQueue,
    required this.resolveMiniPlayerTrack,
    required this.isDarkMode,
    required this.knownTrackDurationsMs,
    required this.knownTrackDurations,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _nowPlaying,
      builder: (ctx, _) {
        final track = resolveMiniPlayerTrack();
        if (track == null) return const SizedBox.shrink();

        final meta = DriveUtils.getTrackMeta(track);
        final coverUrl = _nowPlaying.currentCoverUrl;
        final colors = _safeColors(_nowPlaying.dynamicColors);

        return StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (_, stateSnap) {
            final state = stateSnap.data;
            final isPlaying = state?.playing ?? false;
            final isLoading =
                state?.processingState == ProcessingState.loading ||
                    state?.processingState == ProcessingState.buffering;

            final glowColor = isDarkMode ? _neonPurple : _lightAccentPink;
            final bgColor = isDarkMode ? _darkBg : _lightGlassBase;

            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                debugPrint('MiniPlayer tapped -> opening Now Playing');
                onOpenNowPlaying();
              },
              behavior: HitTestBehavior.opaque,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: Container(
                    height: 82,
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? bgColor.withOpacity(0.40)
                          : _lightGlassBase.withOpacity(0.82),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: glowColor.withOpacity(0.30),
                        width: 1,
                      ),
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
                          padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                          child: Row(
                            children: [
                              AspectRatio(
                                aspectRatio: 1.0,
                                child: _PremiumCoverArt(
                                  heroTag: 'now_playing_artwork',
                                  coverUrl: coverUrl,
                                  colors: colors,
                                  size: 58,
                                  radius: kArtworkRadius,
                                  shadow: false,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 240),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  child: Column(
                                    key: ValueKey(
                                      '${track.id}_${meta['title']}_${meta['artist']}',
                                    ),
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        meta['title'] ?? 'Unknown',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          height: 1.05,
                                          fontWeight: FontWeight.w800,
                                          color: isDarkMode
                                              ? Colors.white
                                              : _lightText,
                                          letterSpacing: -0.35,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        meta['artist'] ?? 'Unknown Artist',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          height: 1.05,
                                          fontWeight: FontWeight.w600,
                                          color: isDarkMode
                                              ? Colors.white.withOpacity(0.70)
                                              : _lightSubtext,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  if (isLoading) return;
                                  HapticFeedback.lightImpact();
                                  isPlaying ? player.pause() : player.play();
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? Colors.white.withOpacity(0.20)
                                        : _lightAccentPink.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: AnimatedContentSwap(
                                    swapKey:
                                        'mini-action-$isLoading-$isPlaying',
                                    child: isLoading
                                        ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              color: isDarkMode
                                                  ? Colors.white
                                                  : _lightAccentPink,
                                              strokeWidth: 2.1,
                                            ),
                                          )
                                        : Icon(
                                            isPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            color: isDarkMode
                                                ? Colors.white
                                                : _lightAccentPink,
                                            size: 30,
                                          ),
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
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? Colors.white.withOpacity(0.20)
                                        : _lightAccentPink.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.skip_next_rounded,
                                    color: isDarkMode
                                        ? Colors.white
                                        : _lightAccentPink,
                                    size: 27,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 4,
                          child: StreamBuilder<Duration>(
                            stream: player.positionStream,
                            builder: (_, posSnap) {
                              return StreamBuilder<Duration?>(
                                stream: player.durationStream,
                                builder: (_, durSnap) {
                                  final dur = durSnap.data ?? Duration.zero;
                                  final pos = posSnap.data ?? Duration.zero;
                                  final prog = dur.inMilliseconds > 0
                                      ? (pos.inMilliseconds /
                                              dur.inMilliseconds)
                                          .clamp(0.0, 1.0)
                                      : 0.0;
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      value: prog,
                                      minHeight: 2.5,
                                      backgroundColor: isDarkMode
                                          ? Colors.white.withOpacity(0.15)
                                          : _lightAccentPink.withOpacity(0.10),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        glowColor.withOpacity(0.80),
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

// â”€â”€â”€ Fullscreen Player Sheet (Apple Music iOS 17 Style) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
