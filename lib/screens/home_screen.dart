part of '../main.dart';

extension BuildHomeTabExtension on _MainScreenState {
  ({
    List<Map<String, String>> recent,
    List<Map<String, String>> played,
    List<Map<String, String>> library,
    List<Map<String, String>> explore,
    List<Map<String, String>> heavy,
  }) _cachedHomeTabData() {
    final cacheKey = [
      _albums.length,
      _libraryBrain.length,
      _playHistory.length,
      _homeShowContinue,
      _homeShowArtists,
      _homeShowDiscovery,
      _homeBrowseCacheVersion,
      _shuffledExploreAlbums.length,
    ].join('|');

    if (_cachedHomeListKey == cacheKey) {
      return (
        recent: _cachedRecentBrainAlbums,
        played: _cachedLastPlayedAlbums,
        library: _cachedHomeLibraryAlbums,
        explore: _cachedHomeExploreAlbums,
        heavy: _cachedHomeHeavyRotationAlbums,
      );
    }

    // _brainAlbums() already returns resolved albums, so no need to call _resolvedAlbumMap again
    final recent = _recentBrainAlbums(limit: 14);
    final played = _lastPlayedAlbums(limit: 10);
    final primaryAlbums = played.isNotEmpty ? played : recent;
    final allAlbums = _albums;
    final library = allAlbums
        .where((a) => !primaryAlbums.contains(a))
        .take(14)
        .map(_resolvedAlbumMap)
        .toList();
    final explore = (_shuffledExploreAlbums.isEmpty
            ? (List<Map<String, String>>.from(
                allAlbums,
              )..shuffle())
                .take(14)
                .toList()
            : _shuffledExploreAlbums)
        .map(_resolvedAlbumMap)
        .toList();
    final heavy = primaryAlbums.take(8).toList();

    // Debug: Check first album metadata
    if (kHomeCacheDebug && recent.isNotEmpty) {
      final first = recent.first;
      debugPrint(
        '[HomeCache] First recent album: displayName="${first['displayName']}" artist="${first['artist']}" name="${first['name']}"',
      );
    }

    if (kHomeCacheDebug) {
      debugPrint(
        '[HomeCache] Cache rebuilt: recent=${recent.length}, played=${played.length}, library=${library.length}, explore=${explore.length}, heavy=${heavy.length}',
      );
    }

    _cachedHomeListKey = cacheKey;
    _cachedRecentBrainAlbums = recent;
    _cachedLastPlayedAlbums = played;
    _cachedHomeLibraryAlbums = library;
    _cachedHomeExploreAlbums = explore;
    _cachedHomeHeavyRotationAlbums = heavy;

    return (
      recent: recent,
      played: played,
      library: library,
      explore: explore,
      heavy: heavy,
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Good night';
  }

  Widget buildHomeTab() {
    final stopwatch = Stopwatch()..start();
    final colors = _safeColors(_currentDynamicColors);
    final homeData = _cachedHomeTabData();
    final recent = homeData.recent;
    final played = homeData.played;
    final primaryAlbums = played.isNotEmpty ? played : recent;
    final allAlbums = _albums;

    final glowColor = _isDarkMode ? Colors.white : _neonMagenta;

    final page = RepaintBoundary(
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          return false;
        },
        child: Container(
          color: Colors.transparent,
          child: RefreshIndicator(
            onRefresh: () async {
              HapticFeedback.mediumImpact();
              await Future.delayed(const Duration(milliseconds: 500));
            },
            color: glowColor,
            backgroundColor: Colors.transparent,
            displacement: 60,
            child: CustomScrollView(
              key: const PageStorageKey('home_tab_v3'),
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: _HomeGreetingHeader(
                      greeting: _greeting(),
                      colors: colors,
                      onSearch: () => _selectRootTab(2),
                      onSources: _openSourceChoiceSheetFromPart,
                      onSettings: _openSettingsSheet,
                      isDarkMode: _isDarkMode,
                    ),
                  ),
                ),
                if (_loadingMetadata)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _HomeProgressBlock(
                        label: _metadataStatusLabel(),
                        progress: _metadataTotal > 0
                            ? (_metadataDone / _metadataTotal).clamp(0.0, 1.0)
                            : null,
                        colors: colors,
                        onTap: _openSettingsSheet,
                      ),
                    ),
                  ),
                if (_loadingSaved || _isScanning)
                  const SliverFillRemaining(child: Center(child: _HomeLoader()))
                else if (_albums.isEmpty)
                  SliverFillRemaining(
                    child: _HomeEmptyState(
                      onSources: _openSourceChoiceSheetFromPart,
                    ),
                  )
                else ...[
                  // Recently Played row
                  if (_homeShowContinue && primaryAlbums.isNotEmpty) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Recently Played',
                          style: GoogleFonts.inter(
                            color: glowColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: _AnimatedSection(
                          delay: 120,
                          child: _HomeAlbumRow(
                            albums: primaryAlbums,
                            onTap: _openAlbumByBrain,
                            isDarkMode: _isDarkMode,
                          ),
                        ),
                      ),
                    ),
                  ],
                  // Your Library row
                  if (_homeShowArtists && homeData.library.isNotEmpty) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Your Library',
                          style: GoogleFonts.inter(
                            color: glowColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: _AnimatedSection(
                          delay: 220,
                          child: _HomeAlbumRow(
                            albums: homeData.library,
                            onTap: _openAlbumByBrain,
                            isDarkMode: _isDarkMode,
                          ),
                        ),
                      ),
                    ),
                  ],
                  // Explore row (all albums shuffled)
                  if (_homeShowDiscovery && allAlbums.length > 4) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Explore',
                          style: GoogleFonts.inter(
                            color: glowColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: _AnimatedSection(
                          delay: 320,
                          child: _HomeAlbumRow(
                            albums: homeData.explore,
                            onTap: _openAlbumByBrain,
                            isDarkMode: _isDarkMode,
                          ),
                        ),
                      ),
                    ),
                  ],
                  // Heavy Rotation
                  if (_homeShowDiscovery) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Heavy Rotation',
                          style: GoogleFonts.inter(
                            color: glowColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: _AnimatedSection(
                          delay: 420,
                          child: _HomeAlbumRow(
                            albums: homeData.heavy,
                            onTap: _openAlbumByBrain,
                            isDarkMode: _isDarkMode,
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 170)),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
    assert(() {
      _verboseUiLog('Home build: ${stopwatch.elapsedMicroseconds}us');
      return true;
    }());
    return page;
  }
}

// â”€â”€â”€ Elevated Home Widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _HomeGreetingHeader extends StatelessWidget {
  final String greeting;
  final List<Color> colors;
  final VoidCallback onSearch;
  final VoidCallback onSources;
  final VoidCallback onSettings;
  final bool isDarkMode;

  const _HomeGreetingHeader({
    required this.greeting,
    required this.colors,
    required this.onSearch,
    required this.onSources,
    required this.onSettings,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final glowColor = isDarkMode ? Colors.white : _neonMagenta;

    return Row(
      children: [
        Expanded(
          child: Text(
            greeting,
            style: GoogleFonts.inter(
              color: glowColor,
              fontSize: 36,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          onPressed: onSearch,
          icon: Icon(
            Icons.search_rounded,
            color: glowColor.withOpacity(0.88),
            size: 26,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onSources,
          icon: Icon(
            Icons.storage_rounded,
            color: glowColor.withOpacity(0.88),
            size: 26,
          ),
        ),
        const SizedBox(width: 2),
        IconButton(
          onPressed: onSettings,
          icon: Icon(
            Icons.tune_rounded,
            color: glowColor.withOpacity(0.88),
            size: 24,
          ),
        ),
      ],
    );
  }
}

class _HomeProgressBlock extends StatelessWidget {
  final String label;
  final double? progress;
  final List<Color> colors;
  final VoidCallback onTap;

  const _HomeProgressBlock({
    required this.label,
    required this.progress,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final safe = _safeColors(colors);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF121214),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: safe[1],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(safe[1]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeLoader extends StatelessWidget {
  const _HomeLoader();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(
              Colors.white.withOpacity(0.6),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Loading...',
          style: GoogleFonts.inter(
            color: Colors.white.withOpacity(0.6),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  final VoidCallback onSources;

  const _HomeEmptyState({required this.onSources});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'No music yet',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Choose Google Drive or import local files to start',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: onSources,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Choose source',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeroAlbum extends StatefulWidget {
  final Map<String, String> hero;
  final List<Color> colors;
  final VoidCallback onTap;

  const _HomeHeroAlbum({
    required this.hero,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_HomeHeroAlbum> createState() => _HomeHeroAlbumState();
}

class _HomeHeroAlbumState extends State<_HomeHeroAlbum>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.hero['displayName'] ?? widget.hero['name'] ?? 'Unknown';
    final artist = widget.hero['artist'] ?? 'Unknown Artist';
    final cover = widget.hero['cover'] ?? widget.hero['coverUrl'] ?? '';
    final gradient = getAlbumGradient(name);
    final safe = _safeColors(widget.colors);

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        height: 320,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kArtworkRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          boxShadow: [
            BoxShadow(
              color: safe[1].withOpacity(0.4),
              blurRadius: 50,
              offset: const Offset(0, 25),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover.isNotEmpty)
              _coverImage(
                cover,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _AlbumFallbackCover(
                  name: name,
                  colors: gradient,
                  radius: 0,
                  small: false,
                ),
              )
            else
              _AlbumFallbackCover(
                name: name,
                colors: gradient,
                radius: 0,
                small: false,
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.75),
                  ],
                ),
              ),
            ),
            Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + (_pulseController.value * 0.05),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 36,
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
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

class _AnimatedSection extends StatefulWidget {
  final Widget child;
  final int delay;

  const _AnimatedSection({required this.child, required this.delay});

  @override
  State<_AnimatedSection> createState() => _AnimatedSectionState();
}

class _AnimatedSectionState extends State<_AnimatedSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(_animation),
        child: widget.child,
      ),
    );
  }
}
