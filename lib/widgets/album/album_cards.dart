part of '../../main.dart';

class _ArtistChip extends StatelessWidget {
  final String name;
  final String count;
  final Color accent;
  final VoidCallback onTap;

  const _ArtistChip({
    required this.name,
    required this.count,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: Colors.white.withOpacity(0.075),
          border: Border.all(color: accent.withOpacity(0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_rounded, color: accent, size: 18),
            const SizedBox(width: 8),
            Text(
              name,
              style: GoogleFonts.inter(
                color: _textPri,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              count,
              style: GoogleFonts.inter(
                color: _textSub,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumGridCard extends StatelessWidget {
  final Key? key;
  final Map<String, String> album;
  final VoidCallback onTap;
  final bool isDarkMode;

  const _AlbumGridCard({
    this.key,
    required this.album,
    required this.onTap,
    required this.isDarkMode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final name = album['displayName'] ?? album['name'] ?? 'Album';
    final artist = album['artist'] ?? '';
    final year = album['year'] ?? '';
    final genre = album['genre'] ?? '';
    final coverUrl = album['cover'] ?? '';
    final gradient = getAlbumGradient(name);

    final glowColor = isDarkMode ? Colors.white : _lightAccentPink;

    return FadeSlideIn(
      key: ValueKey('album-grid-${album['id'] ?? name}'),
      child: RepaintBoundary(
        key: ValueKey(album['id'] ?? name),
        child: PressableScale(
          onTap: onTap,
          child: GlassyContainer(
            radius: 22,
            padding: const EdgeInsets.all(12),
            customColor: (isDarkMode ? _darkBg : _lightBg).withOpacity(0.065),
            customBorder: glowColor.withOpacity(0.10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(kArtworkRadius),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(kArtworkRadius),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradient,
                        ),
                      ),
                      child: coverUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(
                                kArtworkRadius,
                              ),
                              child: _coverImage(
                                coverUrl,
                                fit: BoxFit.cover,
                                cacheSize: 240,
                                errorBuilder: (_, __, ___) =>
                                    _AlbumFallbackCover(
                                  name: name,
                                  colors: gradient,
                                  radius: kArtworkRadius,
                                ),
                              ),
                            )
                          : _AlbumFallbackCover(
                              name: name,
                              colors: gradient,
                              radius: kArtworkRadius,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: glowColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  artist.isNotEmpty
                      ? artist
                      : year.isNotEmpty
                          ? year
                          : genre.isNotEmpty
                              ? genre
                              : 'Album',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: glowColor.withOpacity(0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

// â”€â”€â”€ Album Fallback Cover â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _AlbumFallbackCover extends StatelessWidget {
  final String name;
  final List<Color> colors;
  final double radius;
  final bool small;

  const _AlbumFallbackCover({
    required this.name,
    required this.colors,
    required this.radius,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final safe = _safeColors(colors);
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: safe,
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: GoogleFonts.inter(
            fontSize: small ? 24 : 54,
            fontWeight: FontWeight.w900,
            color: Colors.white.withOpacity(0.52),
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€ Track Tile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _TrackGlassTile extends StatefulWidget {
  final Key? key;
  final drive.File track;
  final List<drive.File> queue;
  final int index;
  final String? coverUrl;
  final String? durationText;
  final bool? isLiked;
  final VoidCallback onTap;
  final VoidCallback? onToggleLiked;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;
  final bool isDarkMode;

  const _TrackGlassTile({
    this.key,
    required this.track,
    required this.queue,
    required this.index,
    this.coverUrl,
    this.durationText,
    this.isLiked,
    required this.onTap,
    this.onToggleLiked,
    this.onPlayNext,
    this.onAddToQueue,
    required this.isDarkMode,
  }) : super(key: key);

  @override
  State<_TrackGlassTile> createState() => _TrackGlassTileState();
}

class _TrackGlassTileState extends State<_TrackGlassTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tapController;
  late final Animation<double> _scaleAnim;
  bool _tapped = false;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _tapController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    setState(() => _tapped = true);
    _tapController.forward().then((_) {
      _tapController.reverse();
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _nowPlaying,
      builder: (ctx, _) {
        final darkMode = widget.isDarkMode;
        final activeId = _nowPlaying.track == null
            ? null
            : DriveUtils.effectiveId(_nowPlaying.track!);
        final isActive = activeId != null &&
            activeId == DriveUtils.effectiveId(widget.track);
        final isLiked = widget.isLiked ?? false;
        final meta = DriveUtils.getTrackMeta(widget.track);
        final colors = _safeColors(_nowPlaying.dynamicColors);
        final glowColor = darkMode ? _neonPurple : _lightAccentPink;
        final titleColor =
            isActive ? glowColor : (darkMode ? Colors.white : _lightText);
        final subColor = isActive
            ? glowColor.withOpacity(0.82)
            : (darkMode ? _textSub : _lightSubtext);
        final baseRowColor = darkMode
            ? Colors.white.withOpacity(0.03)
            : Colors.black.withOpacity(0.03);

        return ScaleTransition(
          scale: _scaleAnim,
          child: GestureDetector(
            onTap: _handleTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isActive
                    ? glowColor.withOpacity(0.08)
                    : _tapped
                        ? glowColor.withOpacity(0.04)
                        : baseRowColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isActive
                      ? glowColor.withOpacity(0.25)
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          isActive ? glowColor.withOpacity(0.20) : _glassWhite,
                      borderRadius: BorderRadius.circular(kArtworkRadius),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(kArtworkRadius),
                      child: (widget.coverUrl != null &&
                              widget.coverUrl!.isNotEmpty)
                          ? _coverImage(
                              widget.coverUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _TrackIcon(
                                isActive: isActive,
                                colors: colors,
                              ),
                            )
                          : _TrackIcon(isActive: isActive, colors: colors),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                          ),
                          child: Text(
                            meta['title']!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta['artist']!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: subColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onToggleLiked != null)
                        IconButton(
                          tooltip: isLiked ? 'Unlike' : 'Like',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          splashRadius: 20,
                          icon: Icon(
                            isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isLiked ? _pink : subColor,
                            size: 20,
                          ),
                          onPressed: widget.onToggleLiked,
                        ),
                      if ((widget.durationText ?? '').isNotEmpty)
                        Text(
                          widget.durationText!,
                          style: GoogleFonts.inter(
                            color: isActive ? glowColor : subColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      if ((widget.onPlayNext != null) ||
                          (widget.onAddToQueue != null))
                        PopupMenuButton<int>(
                          tooltip: 'Track options',
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: subColor,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          splashRadius: 20,
                          color: const Color(0xFF1A1A22),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          onSelected: (value) {
                            if (value == 1) {
                              widget.onPlayNext?.call();
                            } else if (value == 2) {
                              widget.onAddToQueue?.call();
                            }
                          },
                          itemBuilder: (context) => [
                            if (widget.onPlayNext != null)
                              PopupMenuItem<int>(
                                value: 1,
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 18,
                                      color: _textPri,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Play Next',
                                      style: GoogleFonts.inter(
                                        color: _textPri,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (widget.onAddToQueue != null)
                              PopupMenuItem<int>(
                                value: 2,
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.queue_music_rounded,
                                      size: 18,
                                      color: _textPri,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Add to Queue',
                                      style: GoogleFonts.inter(
                                        color: _textPri,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AlbumActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final bool primary;

  const _AlbumActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary ? accent : Colors.white.withOpacity(0.080);
    final fg = primary ? Colors.black : accent;
    final border = primary ? Colors.transparent : accent.withOpacity(0.3);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: border),
          boxShadow: primary
              ? [
                  BoxShadow(
                    color: accent.withOpacity(0.24),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ]
              : const [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 21),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: fg,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackIcon extends StatelessWidget {
  final bool isActive;
  final List<Color> colors;

  const _TrackIcon({required this.isActive, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        isActive ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
        color: isActive ? Colors.white.withOpacity(0.92) : _textSub,
        size: isActive ? 22 : 19,
      ),
    );
  }
}

// â”€â”€â”€ Nav Bar Item â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
