part of '../../main.dart';

class _HomeActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _HomeActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 152,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.white.withOpacity(0.070),
          border: Border.all(color: Colors.white.withOpacity(0.11)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withOpacity(0.15),
                border: Border.all(color: accent.withOpacity(0.22)),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: _textPri,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: _textSub,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HomeMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: _textPri,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: _textSub,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeAlbumCard extends StatefulWidget {
  final Key? key;
  final Map<String, String> info;
  final VoidCallback onTap;
  final bool isDarkMode;

  const _HomeAlbumCard({
    this.key,
    required this.info,
    required this.onTap,
    required this.isDarkMode,
  }) : super(key: key);

  @override
  State<_HomeAlbumCard> createState() => _HomeAlbumCardState();
}

class _HomeAlbumCardState extends State<_HomeAlbumCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final name = widget.info['displayName'] ?? widget.info['name'] ?? 'Album';
    final artist = widget.info['artist'] ?? 'Unknown Artist';
    final year = widget.info['year'] ?? '';
    final genre = widget.info['genre'] ?? '';
    final coverUrl = widget.info['coverUrl'] ?? widget.info['cover'] ?? '';
    final gradient = getAlbumGradient(name);

    final glowColor = widget.isDarkMode ? Colors.white : _lightAccentPink;

    return FadeSlideIn(
      key: ValueKey('home-album-${widget.info['id'] ?? name}'),
      child: RepaintBoundary(
        key: ValueKey(widget.info['id'] ?? name),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _isPressed ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeInOut,
            child: SizedBox(
              width: 138,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(kArtworkRadius),
                    child: Container(
                      width: 138,
                      height: 138,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(kArtworkRadius),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradient,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.isDarkMode
                                ? glowColor.withOpacity(0.15)
                                : _lightAccentPink.withOpacity(0.12),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: coverUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(
                                kArtworkRadius,
                              ),
                              child: _coverImage(
                                coverUrl,
                                fit: BoxFit.cover,
                                cacheSize: 160,
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
                  const SizedBox(height: 10),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: widget.isDarkMode ? glowColor : _lightText,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: widget.isDarkMode
                          ? glowColor.withOpacity(0.7)
                          : _lightSubtext,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _HomeSectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: _textPri,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: _textSub,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _HomeSpotlightCard extends StatelessWidget {
  final Map<String, String> info;
  final Color accent;
  final VoidCallback onTap;

  const _HomeSpotlightCard({
    required this.info,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = info['displayName'] ?? info['name'] ?? 'Album';
    final artist = info['artist'] ?? '';
    final cover = info['cover'] ?? '';
    final year = info['year'] ?? '';
    final genre = info['genre'] ?? '';
    final trackCount = info['trackCount'] ?? '';
    final gradient = getAlbumGradient(name);

    return PressableScale(
      onTap: onTap,
      child: GlassyContainer(
        radius: 30,
        padding: const EdgeInsets.all(16),
        customColor: Colors.white.withOpacity(0.075),
        customBorder: accent.withOpacity(0.20),
        child: Row(
          children: [
            Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kArtworkRadius),
                gradient: LinearGradient(colors: gradient),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: cover.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(kArtworkRadius),
                      child: _coverImage(
                        cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _AlbumFallbackCover(
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
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tonightâ€™s pick',
                    style: GoogleFonts.inter(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: _textPri,
                      fontSize: 23,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.7,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    artist.isNotEmpty ? artist : 'Drive album',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: _textSub,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (year.isNotEmpty)
                        _MiniInfoPill(label: year, accent: accent),
                      if (genre.isNotEmpty)
                        _MiniInfoPill(label: genre, accent: accent),
                      if (trackCount.isNotEmpty)
                        _MiniInfoPill(
                          label: '$trackCount tracks',
                          accent: accent,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniInfoPill extends StatelessWidget {
  final String label;
  final Color accent;

  const _MiniInfoPill({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: _textPri,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RecentTrackPill extends StatelessWidget {
  final Map<String, String> item;
  final Color accent;
  final VoidCallback onTap;

  const _RecentTrackPill({
    required this.item,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = item['title'] ?? 'Unknown';
    final artist = item['artist'] ?? 'Unknown Artist';
    final cover = item['cover'] ?? '';
    final albumName = item['albumName'] ?? title;
    final gradient = getAlbumGradient(albumName);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: GlassyContainer(
        radius: 22,
        padding: const EdgeInsets.all(10),
        customColor: Colors.white.withOpacity(0.070),
        customBorder: Colors.white.withOpacity(0.10),
        child: SizedBox(
          width: 260,
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kArtworkRadius),
                  gradient: LinearGradient(colors: gradient),
                ),
                child: cover.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(kArtworkRadius),
                        child: _coverImage(
                          cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _AlbumFallbackCover(
                            name: albumName,
                            colors: gradient,
                            radius: kArtworkRadius,
                            small: true,
                          ),
                        ),
                      )
                    : _AlbumFallbackCover(
                        name: albumName,
                        colors: gradient,
                        radius: kArtworkRadius,
                        small: true,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _textPri,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _textSub,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: accent.withOpacity(0.85),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  final Color accent;
  final VoidCallback onTap;

  const _DiscoveryCard({required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: GlassyContainer(
        radius: 26,
        padding: const EdgeInsets.all(16),
        customColor: Colors.white.withOpacity(0.070),
        customBorder: accent.withOpacity(0.18),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withOpacity(0.16),
              ),
              child: Icon(Icons.casino_rounded, color: accent, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Play something forgotten',
                    style: GoogleFonts.inter(
                      color: _textPri,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Shuffle from your Drive library when you do not know what to pick.',
                    style: GoogleFonts.inter(
                      color: _textSub,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.play_arrow_rounded, color: _textPri, size: 28),
          ],
        ),
      ),
    );
  }
}
