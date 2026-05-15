part of '../main.dart';

class _MetadataStat extends StatelessWidget {
  final String label;
  final int value;
  final bool isDarkMode;

  const _MetadataStat({
    required this.label,
    required this.value,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final darkMode = isDarkMode;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.toString(),
            style: GoogleFonts.inter(
              color: darkMode ? _textPri : _lightText,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              color: darkMode ? _textSub : _lightSubtext,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  final String title;
  final bool isDarkMode;

  const _SettingsSectionTitle({
    required this.title,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final darkMode = isDarkMode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: GoogleFonts.inter(
          color: darkMode ? _textPri : _lightText,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

class _SettingsPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final bool destructive;
  final VoidCallback onTap;
  final bool isDarkMode;

  const _SettingsPrimaryButton({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.destructive = false,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final darkMode = isDarkMode;
    final background = destructive
        ? (darkMode
            ? Colors.white.withOpacity(0.12)
            : Colors.black.withOpacity(0.05))
        : accent;
    final foreground =
        destructive ? (darkMode ? _textPri : _lightText) : Colors.black;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: destructive
                ? Colors.white.withOpacity(0.15)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: GoogleFonts.inter(
                  color: foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool isDarkMode;

  const _SettingsInfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final darkMode = isDarkMode;
    return GlassyContainer(
      radius: 22,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      customColor: darkMode
          ? Colors.white.withOpacity(0.070)
          : _lightGlassBase.withOpacity(0.72),
      customBorder: darkMode
          ? Colors.white.withOpacity(0.12)
          : Colors.black.withOpacity(0.08),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.16),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: darkMode ? _textPri : _lightText,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: darkMode ? _textSub : _lightSubtext,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final Color accent;
  final ValueChanged<bool> onChanged;
  final bool isDarkMode;

  const _SettingsSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.accent,
    required this.onChanged,
    this.enabled = true,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final darkMode = isDarkMode;
    final effectiveAccent = enabled ? accent : _textSub;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassyContainer(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        customColor: darkMode
            ? Colors.white.withOpacity(0.065)
            : _lightGlassBase.withOpacity(0.72),
        customBorder: darkMode
            ? Colors.white.withOpacity(0.10)
            : Colors.black.withOpacity(0.08),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: effectiveAccent.withOpacity(0.14),
              ),
              child: Icon(icon, color: effectiveAccent, size: 21),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: enabled
                          ? (darkMode ? _textPri : _lightText)
                          : (darkMode ? _textSub : _lightSubtext),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: darkMode ? _textSub : _lightSubtext,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeColor: accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback? onTap;
  final bool destructive;
  final bool isDarkMode;

  const _SettingsActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.destructive = false,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final darkMode = isDarkMode;
    final enabled = onTap != null;
    final effectiveAccent = destructive ? Colors.redAccent : accent;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1.0 : 0.45,
        child: GlassyContainer(
          radius: 20,
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 10),
          customColor: darkMode
              ? Colors.white.withOpacity(0.065)
              : _lightGlassBase.withOpacity(0.72),
          customBorder: destructive
              ? Colors.redAccent.withOpacity(0.30)
              : (darkMode
                  ? Colors.white.withOpacity(0.11)
                  : Colors.black.withOpacity(0.08)),
          child: Row(
            children: [
              Icon(icon, color: effectiveAccent, size: 22),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: darkMode ? _textPri : _lightText,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: darkMode ? _textSub : _lightSubtext,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color:
                      (darkMode ? _textSub : _lightSubtext).withOpacity(0.8)),
            ],
          ),
        ),
      ),
    );
  }
}

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
                              borderRadius:
                                  BorderRadius.circular(kArtworkRadius),
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
                              radius: kArtworkRadius),
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
                      name: name, colors: gradient, radius: kArtworkRadius),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tonight’s pick',
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
                            label: '$trackCount tracks', accent: accent),
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
                        small: true),
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
              Icon(Icons.chevron_right_rounded,
                  color: accent.withOpacity(0.85)),
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

  const _AlbumGridCard(
      {this.key,
      required this.album,
      required this.onTap,
      required this.isDarkMode})
      : super(key: key);

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
                              borderRadius:
                                  BorderRadius.circular(kArtworkRadius),
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
                              radius: kArtworkRadius),
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
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Album Fallback Cover ───────────────────────────────────────────────────
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

// ─── Track Tile ─────────────────────────────────────────────────────────────
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
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _tapController, curve: Curves.easeOut),
    );
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
                                  isActive: isActive, colors: colors),
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
                          style:
                              GoogleFonts.inter(fontSize: 12, color: subColor),
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
                          icon: Icon(Icons.more_vert_rounded,
                              color: subColor, size: 20),
                          padding: EdgeInsets.zero,
                          splashRadius: 20,
                          color: const Color(0xFF1A1A22),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
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
                                    const Icon(Icons.play_arrow_rounded,
                                        size: 18, color: _textPri),
                                    const SizedBox(width: 10),
                                    Text('Play Next',
                                        style: GoogleFonts.inter(
                                            color: _textPri,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            if (widget.onAddToQueue != null)
                              PopupMenuItem<int>(
                                value: 2,
                                child: Row(
                                  children: [
                                    const Icon(Icons.queue_music_rounded,
                                        size: 18, color: _textPri),
                                    const SizedBox(width: 10),
                                    Text('Add to Queue',
                                        style: GoogleFonts.inter(
                                            color: _textPri,
                                            fontWeight: FontWeight.w700)),
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

// ─── Nav Bar Item ───────────────────────────────────────────────────────────
class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDarkMode;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isDarkMode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Semantics(
        label: label,
        selected: isSelected,
        button: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.linear,
          width: double.infinity,
          height: 34,
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withOpacity(0.10),
              width: 1,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isDarkMode
                      ? (isSelected
                          ? Colors.white
                          : Colors.white.withOpacity(0.72))
                      : (isSelected
                          ? _lightNavIconPink
                          : _lightNavIconPink.withOpacity(0.70)),
                  size: 17,
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 8.0,
                    fontWeight: FontWeight.w800,
                    color: isDarkMode
                        ? (isSelected
                            ? Colors.white
                            : Colors.white.withOpacity(0.72))
                        : (isSelected
                            ? _lightNavIconPink
                            : _lightNavIconPink.withOpacity(0.70)),
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

class _SearchModePill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDarkMode;
  final VoidCallback onTap;

  const _SearchModePill({
    required this.label,
    required this.isSelected,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isDarkMode
              ? (isSelected
                  ? Colors.white.withOpacity(0.12)
                  : Colors.white.withOpacity(0.03))
              : (isSelected
                  ? _lightAccentPink.withOpacity(0.12)
                  : Colors.black.withOpacity(0.03)),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isDarkMode
                ? (isSelected
                    ? Colors.white.withOpacity(0.24)
                    : Colors.white.withOpacity(0.12))
                : (isSelected
                    ? _lightAccentPink.withOpacity(0.28)
                    : Colors.black.withOpacity(0.10)),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: isDarkMode
                ? (isSelected ? Colors.white : Colors.white.withOpacity(0.72))
                : (isSelected
                    ? _lightAccentPink
                    : Colors.black.withOpacity(0.60)),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

extension _LibrarySharedWidgetsExtension on _MainScreenState {
  Widget _buildLibrarySearchBarFromPart(List<Color> colors,
      {required String hintText,
      TextEditingController? controller,
      ValueChanged<String>? onChanged,
      String? query}) {
    final activeController = controller ?? _librarySearchController;
    final activeQuery = query ?? _libraryQuery;
    final bgColor = _isDarkMode
        ? Colors.white.withOpacity(0.06)
        : Colors.black.withOpacity(0.025);
    final borderColor = _isDarkMode
        ? Colors.white.withOpacity(0.14)
        : Colors.black.withOpacity(0.10);

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: _isDarkMode ? 14 : 8, sigmaY: _isDarkMode ? 14 : 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: TextField(
            controller: activeController,
            onChanged: onChanged ??
                (value) => _librarySetState(() => _libraryQuery = value),
            style: GoogleFonts.inter(
                color: _isDarkMode ? _textPri : _lightText,
                fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              border: InputBorder.none,
              icon: Icon(Icons.manage_search_rounded, color: colors[1]),
              suffixIcon: activeQuery.trim().isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: _isDarkMode ? _textSub : _lightSubtext),
                      onPressed: () {
                        activeController.clear();
                        if (onChanged == null) {
                          _librarySetState(() => _libraryQuery = '');
                        } else {
                          onChanged('');
                        }
                      },
                    )
                  : null,
              hintText: hintText,
              hintStyle: GoogleFonts.inter(
                  color: _isDarkMode ? _textSub : _lightSubtext,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

extension _LibraryModeWidgetsExtension on _MainScreenState {
  Widget _buildLibraryModeRowFromPart() {
    final items = <({String label, String mode})>[
      (label: 'Albums', mode: 'albums'),
      (label: 'Songs', mode: 'songs'),
      (label: 'Artists', mode: 'artists'),
      (label: 'Liked', mode: 'liked'),
    ];

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: _LibraryModePill(
              label: items[i].label,
              isSelected: _libraryViewMode == items[i].mode,
              isDarkMode: _isDarkMode,
              onTap: () {
                _librarySetState(() => _libraryViewMode = items[i].mode);
                _saveUiPreferences();
              },
            ),
          ),
          if (i != items.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _LibraryInfoChip extends StatelessWidget {
  final String label;
  final Color accent;

  const _LibraryInfoChip({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: Colors.white.withOpacity(0.88),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LibraryModePill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDarkMode;
  final VoidCallback onTap;

  const _LibraryModePill({
    required this.label,
    required this.isSelected,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isDarkMode
              ? (isSelected
                  ? Colors.white.withOpacity(0.12)
                  : Colors.white.withOpacity(0.03))
              : (isSelected
                  ? _lightAccentPink.withOpacity(0.12)
                  : Colors.black.withOpacity(0.03)),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isDarkMode
                ? (isSelected
                    ? Colors.white.withOpacity(0.24)
                    : Colors.white.withOpacity(0.12))
                : (isSelected
                    ? _lightAccentPink.withOpacity(0.28)
                    : Colors.black.withOpacity(0.10)),
          ),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: isDarkMode
                  ? (isSelected ? Colors.white : Colors.white.withOpacity(0.68))
                  : (isSelected
                      ? _lightAccentPink
                      : Colors.black.withOpacity(0.58)),
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
