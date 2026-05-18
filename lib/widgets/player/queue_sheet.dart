part of '../../main.dart';

class _QueueSheet extends StatelessWidget {
  final List<Color> colors;
  final Future<void> Function(drive.File track, int index) onPlayFromQueue;
  final void Function(int index)? onRemoveQueueItemAt;
  final VoidCallback? onClearUpcomingQueue;
  final Map<String, int> knownTrackDurationsMs;
  final Map<String, Duration> knownTrackDurations;

  const _QueueSheet({
    required this.colors,
    required this.onPlayFromQueue,
    this.onRemoveQueueItemAt,
    this.onClearUpcomingQueue,
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
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
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
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 34,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Queue',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
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
                            style: GoogleFonts.inter(
                              color: _textSub,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }

                      final queue = _nowPlaying.queue;
                      final activeIndex = _nowPlaying.queueIndex.clamp(
                        0,
                        queue.length - 1,
                      );
                      final currentTrack = queue[activeIndex];
                      final upcomingTracks = queue.sublist(activeIndex + 1);

                      return ListView(
                        physics: const BouncingScrollPhysics(),
                        children: [
                          Text(
                            'Now Playing',
                            style: GoogleFonts.inter(
                              color: _textSub,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildQueueRow(
                            context,
                            track: currentTrack,
                            index: activeIndex,
                            isActive: true,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Text(
                                'Up Next',
                                style: GoogleFonts.inter(
                                  color: _textSub,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const Spacer(),
                              if (upcomingTracks.isNotEmpty &&
                                  onClearUpcomingQueue != null)
                                TextButton(
                                  onPressed: onClearUpcomingQueue,
                                  child: Text(
                                    'Clear Queue',
                                    style: GoogleFonts.inter(
                                      color: safe[1],
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (upcomingTracks.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'No upcoming songs.',
                                style: GoogleFonts.inter(
                                  color: _textSub,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          for (var i = activeIndex + 1; i < queue.length; i++)
                            _buildQueueRow(
                              context,
                              track: queue[i],
                              index: i,
                              isActive: false,
                              allowRemove: onRemoveQueueItemAt != null,
                            ),
                        ],
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

  Widget _buildQueueRow(
    BuildContext context, {
    required drive.File track,
    required int index,
    required bool isActive,
    bool allowRemove = false,
  }) {
    final safe = _safeColors(colors);
    final meta = DriveUtils.getTrackMeta(track);
    final trackKey = track.id ?? '';

    Duration? duration;
    final durationMs = knownTrackDurationsMs[trackKey];
    if (durationMs != null && durationMs > 0) {
      duration = Duration(milliseconds: durationMs);
    } else {
      duration = knownTrackDurations[trackKey];
    }

    return GestureDetector(
      onTap: () async {
        await onPlayFromQueue(track, index);
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
                '${index + 1}',
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
            if (!isActive && allowRemove)
              IconButton(
                onPressed: () => onRemoveQueueItemAt?.call(index),
                icon: Icon(
                  Icons.close_rounded,
                  color: _textSub.withOpacity(0.9),
                  size: 20,
                ),
                splashRadius: 18,
              ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€ Floating Player Bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
