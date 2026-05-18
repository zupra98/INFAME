part of '../../main.dart';

class _HomeAlbumRow extends StatelessWidget {
  final List<Map<String, String>> albums;
  final ValueChanged<Map<String, String>> onTap;
  final bool isDarkMode;

  const _HomeAlbumRow({
    required this.albums,
    required this.onTap,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 192,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return Padding(
            padding: EdgeInsets.only(
              right: index == albums.length - 1 ? 0 : 12,
            ),
            child: FadeSlideIn(
              key: ValueKey('home-row-${album['id'] ?? album['name']}'),
              child: _HomeAlbumCard(
                key: ValueKey(album['id'] ?? album['name']),
                info: album,
                onTap: () => onTap(album),
                isDarkMode: isDarkMode,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _JumpBackInSection extends StatelessWidget {
  final List<Map<String, String>> history;
  final List<Color> colors;
  final ValueChanged<Map<String, String>> onTap;

  const _JumpBackInSection({
    required this.history,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Jump back in',
          style: GoogleFonts.inter(
            color: _neonMagenta,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _JumpBackInCard(
              item: history[i],
              onTap: () => onTap(history[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _JumpBackInCard extends StatelessWidget {
  final Map<String, String> item;
  final VoidCallback onTap;

  const _JumpBackInCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = item['title'] ?? 'Track';
    final cover = item['cover'] ?? '';
    final gradient = getAlbumGradient(title);

    return FadeSlideIn(
      key: ValueKey('jump-${item['title'] ?? 'track'}'),
      child: PressableScale(
        onTap: onTap,
        child: SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    width: 140,
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(kArtworkRadius),
                      gradient: LinearGradient(colors: gradient),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: cover.isNotEmpty
                        ? _coverImage(
                            cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _AlbumFallbackCover(
                              name: title,
                              colors: gradient,
                              radius: kArtworkRadius,
                              small: true,
                            ),
                          )
                        : _AlbumFallbackCover(
                            name: title,
                            colors: gradient,
                            radius: kArtworkRadius,
                            small: true,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: _neonMagenta,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingShuffleButton extends StatefulWidget {
  final List<Color> colors;
  final VoidCallback onTap;

  const _FloatingShuffleButton({required this.colors, required this.onTap});

  @override
  State<_FloatingShuffleButton> createState() => _FloatingShuffleButtonState();
}

class _FloatingShuffleButtonState extends State<_FloatingShuffleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safe = _safeColors(widget.colors);

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: safe[1],
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: safe[1].withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Icon(Icons.shuffle_rounded, color: Colors.black, size: 28),
        ),
      ),
    );
  }
}

class _HomeAlbumTile extends StatefulWidget {
  final Map<String, String> album;
  final String heroTag;
  final VoidCallback onTap;

  const _HomeAlbumTile({
    required this.album,
    required this.heroTag,
    required this.onTap,
  });

  @override
  State<_HomeAlbumTile> createState() => _HomeAlbumTileState();
}

class _HomeAlbumTileState extends State<_HomeAlbumTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name =
        widget.album['displayName'] ?? widget.album['name'] ?? 'Unknown';
    final artist = widget.album['artist'] ?? 'Unknown Artist';
    final cover = widget.album['cover'] ?? widget.album['coverUrl'] ?? '';
    final gradient = getAlbumGradient(name);

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: widget.heroTag,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kArtworkRadius),
                    gradient: LinearGradient(colors: gradient),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: cover.isNotEmpty
                      ? _coverImage(
                          cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _AlbumFallbackCover(
                            name: name,
                            colors: gradient,
                            radius: kArtworkRadius,
                            small: true,
                          ),
                        )
                      : _AlbumFallbackCover(
                          name: name,
                          colors: gradient,
                          radius: kArtworkRadius,
                          small: true,
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
