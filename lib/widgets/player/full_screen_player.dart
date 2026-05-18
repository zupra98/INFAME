part of '../../main.dart';

class _FullScreenPlayerSheet extends StatefulWidget {
  final AudioPlayer player;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final Future<void> Function(drive.File track, int index) onPlayFromQueue;
  final void Function(int index)? onRemoveQueueItemAt;
  final VoidCallback? onClearUpcomingQueue;
  final bool isDarkMode;
  final bool embedded;
  final String albumName;
  final bool isLiked;
  final VoidCallback onToggleLiked;
  final Map<String, int> knownTrackDurationsMs;
  final Map<String, Duration> knownTrackDurations;

  const _FullScreenPlayerSheet({
    required this.player,
    required this.onNext,
    required this.onPrev,
    required this.onPlayFromQueue,
    this.onRemoveQueueItemAt,
    this.onClearUpcomingQueue,
    required this.isDarkMode,
    this.embedded = false,
    this.albumName = '',
    required this.isLiked,
    required this.onToggleLiked,
    required this.knownTrackDurationsMs,
    required this.knownTrackDurations,
  });

  @override
  State<_FullScreenPlayerSheet> createState() => _FullScreenPlayerSheetState();
}

class _FullScreenPlayerSheetState extends State<_FullScreenPlayerSheet> {
  String _formatTime(Duration d) {
    final hours = d.inHours;
    final minutes =
        d.inMinutes.remainder(60).toString().padLeft(hours > 0 ? 2 : 1, '0');
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
        return _LyricsSheet(player: widget.player, meta: meta, colors: colors);
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
          onRemoveQueueItemAt: widget.onRemoveQueueItemAt,
          onClearUpcomingQueue: widget.onClearUpcomingQueue,
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
        if (track == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.music_note_rounded,
                    size: 44,
                    color: widget.isDarkMode
                        ? Colors.white.withOpacity(0.62)
                        : _lightAccentPink.withOpacity(0.72),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nothing playing',
                    style: GoogleFonts.inter(
                      color: widget.isDarkMode
                          ? Colors.white.withOpacity(0.9)
                          : _lightText,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pick something from Home or Library',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: widget.isDarkMode
                          ? Colors.white.withOpacity(0.55)
                          : _lightSubtext,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final meta = DriveUtils.getTrackMeta(track);
        final coverUrl = _nowPlaying.currentCoverUrl;
        final colors = _safeColors(_nowPlaying.dynamicColors);
        final provider = _coverProvider(coverUrl);
        final media = MediaQuery.of(context);
        final width = media.size.width;
        final height = media.size.height;
        final compact = height <= 780;
        final ultraCompact = height <= 700;
        final maxByHeight = compact ? height * 0.33 : height * 0.38;
        final artworkSize = math.min(math.min(width - 48, 320.0), maxByHeight);

        return StreamBuilder<PlayerState>(
          stream: widget.player.playerStateStream,
          builder: (context, stateSnap) {
            final state = stateSnap.data;
            final isPlaying = state?.playing ?? false;
            final isLoading =
                state?.processingState == ProcessingState.loading ||
                    state?.processingState == ProcessingState.buffering;

            return ClipRRect(
              borderRadius: widget.embedded
                  ? BorderRadius.zero
                  : const BorderRadius.vertical(top: Radius.circular(36)),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: widget.isDarkMode
                          ? const Color(0xFF050508)
                          : _lightBg,
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
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        22,
                        10,
                        22,
                        math.max(20, media.padding.bottom + 4),
                      ),
                      child: Column(
                        children: [
                          if (!widget.embedded) ...[
                            Container(
                              width: 42,
                              height: 5,
                              decoration: BoxDecoration(
                                color: widget.isDarkMode
                                    ? Colors.white.withOpacity(0.34)
                                    : _lightAccentPink.withOpacity(0.34),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ] else
                            const SizedBox(height: 14),
                          Row(
                            children: [
                              widget.embedded
                                  ? const SizedBox(width: 40)
                                  : IconButton(
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () =>
                                          Navigator.maybePop(context),
                                      icon: Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: widget.isDarkMode
                                            ? Colors.white.withOpacity(0.88)
                                            : _lightText.withOpacity(0.88),
                                        size: 32,
                                      ),
                                    ),
                              const Spacer(),
                              Text(
                                'NOW PLAYING',
                                style: GoogleFonts.inter(
                                  color: widget.isDarkMode
                                      ? Colors.white.withOpacity(0.46)
                                      : _lightSubtext.withOpacity(0.60),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    _openMoreActions(context, meta, colors),
                                icon: Icon(
                                  Icons.more_horiz_rounded,
                                  color: widget.isDarkMode
                                      ? Colors.white.withOpacity(0.88)
                                      : _lightText.withOpacity(0.88),
                                  size: 30,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 10 : 14),
                          SizedBox(
                            height: artworkSize,
                            child: Center(
                              child: SizedBox(
                                width: artworkSize,
                                height: artworkSize,
                                child: _InteractiveCoverArt(
                                  key: ValueKey('full_cover_$coverUrl'),
                                  heroTag: 'now_playing_artwork',
                                  coverUrl: coverUrl,
                                  colors: colors,
                                  size: artworkSize,
                                  shadow: true,
                                  isPlaying: isPlaying,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 12 : 18),
                          _NowPlayingMetaBlock(
                            meta: {
                              ...meta,
                              if (widget.albumName.isNotEmpty)
                                'album': widget.albumName,
                            },
                            isDarkMode: widget.isDarkMode,
                            compact: compact,
                          ),
                          SizedBox(height: compact ? 12 : 18),
                          SizedBox(
                            height: compact ? 56 : 62,
                            child: StreamBuilder<Duration>(
                              stream: widget.player.positionStream,
                              builder: (_, posSnap) {
                                return StreamBuilder<Duration?>(
                                  stream: widget.player.durationStream,
                                  builder: (_, durSnap) {
                                    final pos = posSnap.data ?? Duration.zero;
                                    final dur = durSnap.data ?? Duration.zero;
                                    final max = dur.inMilliseconds > 0
                                        ? dur.inMilliseconds.toDouble()
                                        : 1.0;
                                    final value = pos.inMilliseconds
                                        .toDouble()
                                        .clamp(0.0, max);
                                    final remaining =
                                        dur > pos ? dur - pos : Duration.zero;

                                    return Column(
                                      children: [
                                        SizedBox(
                                          height: compact ? 22 : 24,
                                          child: SliderTheme(
                                            data: SliderTheme.of(context)
                                                .copyWith(
                                              trackHeight: compact ? 2.2 : 2.4,
                                              thumbShape:
                                                  const RoundSliderThumbShape(
                                                enabledThumbRadius: 4.8,
                                              ),
                                              overlayShape:
                                                  const RoundSliderOverlayShape(
                                                overlayRadius: 9,
                                              ),
                                            ),
                                            child: Slider(
                                              value: value,
                                              max: max,
                                              activeColor: widget.isDarkMode
                                                  ? Colors.white.withOpacity(
                                                      0.88,
                                                    )
                                                  : _lightAccentPink,
                                              inactiveColor: widget.isDarkMode
                                                  ? Colors.white.withOpacity(
                                                      0.14,
                                                    )
                                                  : _lightAccentPink
                                                      .withOpacity(0.15),
                                              onChanged: (v) {
                                                widget.player.seek(
                                                  Duration(
                                                    milliseconds: v.toInt(),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: compact ? 12 : 14,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _formatTime(pos),
                                                style: GoogleFonts.inter(
                                                  color: widget.isDarkMode
                                                      ? Colors.white
                                                          .withOpacity(0.52)
                                                      : _lightSubtext,
                                                  fontSize: compact ? 11 : 11.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                '-${_formatTime(remaining)}',
                                                style: GoogleFonts.inter(
                                                  color: widget.isDarkMode
                                                      ? Colors.white
                                                          .withOpacity(0.52)
                                                      : _lightSubtext,
                                                  fontSize: compact ? 11 : 11.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
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
                          ),
                          SizedBox(height: ultraCompact ? 2 : 6),
                          SizedBox(
                            height: compact ? 74 : 82,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.skip_previous_rounded,
                                    size: compact ? 36 : 40,
                                    color: widget.isDarkMode
                                        ? Colors.white.withOpacity(0.90)
                                        : _lightAccentPink.withOpacity(0.90),
                                  ),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    widget.onPrev();
                                  },
                                ),
                                SizedBox(width: compact ? 16 : 24),
                                GestureDetector(
                                  onTap: () {
                                    if (isLoading) return;
                                    HapticFeedback.mediumImpact();
                                    isPlaying
                                        ? widget.player.pause()
                                        : widget.player.play();
                                  },
                                  behavior: HitTestBehavior.opaque,
                                  child: Container(
                                    width: compact ? 62 : 68,
                                    height: compact ? 62 : 68,
                                    decoration: BoxDecoration(
                                      color: widget.isDarkMode
                                          ? Colors.white.withOpacity(0.10)
                                          : _lightAccentPink.withOpacity(0.10),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: AnimatedContentSwap(
                                        swapKey:
                                            'full-action-$isLoading-$isPlaying',
                                        child: isLoading
                                            ? SizedBox(
                                                width: 30,
                                                height: 30,
                                                child:
                                                    CircularProgressIndicator(
                                                  color: widget.isDarkMode
                                                      ? Colors.white
                                                      : _lightAccentPink,
                                                  strokeWidth: 2.0,
                                                ),
                                              )
                                            : Icon(
                                                isPlaying
                                                    ? Icons.pause_rounded
                                                    : Icons.play_arrow_rounded,
                                                color: widget.isDarkMode
                                                    ? Colors.white
                                                    : _lightAccentPink,
                                                size: compact ? 44 : 48,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: compact ? 16 : 24),
                                IconButton(
                                  icon: Icon(
                                    Icons.skip_next_rounded,
                                    size: compact ? 36 : 40,
                                    color: widget.isDarkMode
                                        ? Colors.white.withOpacity(0.90)
                                        : _lightAccentPink.withOpacity(0.90),
                                  ),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    widget.onNext();
                                  },
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: ultraCompact ? 2 : 6),
                          _SystemVolumeSlider(isDarkMode: widget.isDarkMode),
                          SizedBox(height: ultraCompact ? 8 : 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _PremiumActionButton(
                                icon: widget.isLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                label: 'Liked',
                                onTap: widget.onToggleLiked,
                                colors: colors,
                                isDarkMode: widget.isDarkMode,
                              ),
                              _PremiumActionButton(
                                icon: Icons.chat_bubble_outline_rounded,
                                label: 'Lyrics',
                                onTap: () =>
                                    _openLyricsSheet(context, meta, colors),
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
                ],
              ),
            );
          },
        );
      },
    );
  }
}
