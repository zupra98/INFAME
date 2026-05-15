part of '../main.dart';

class MusixApp extends StatelessWidget {
  const MusixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infame',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        sliderTheme: const SliderThemeData(
          thumbColor: _accentDefault,
          activeTrackColor: _pink,
          inactiveTrackColor: _glassWhite,
          trackHeight: 4,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  final WidgetBuilder builder;

  const _KeepAlivePage({super.key, required this.builder});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.builder(context);
  }
}

extension _PlayerShellWidgetsExtension on _MainScreenState {
  Widget _buildMainShellFromPart() {
    if (_user == null && !_hasLocalMusicLibrary) {
      return _buildSignInScreen();
    }

    final bgColor = _isDarkMode ? _darkBg : _lightBg;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: bgColor,
      extendBody: false,
      body: Stack(
        children: [
          Positioned.fill(child: _NeonBlobBackground(isDarkMode: _isDarkMode)),
          SafeArea(
            bottom: false,
            child: _viewingAlbum != null
                ? _buildAlbumView()
                : PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    itemCount: 3,
                    onPageChanged: (index) {
                      debugPrint('PageView onPageChanged index=$index');
                      _mainShellSetState(() {
                        _navIndex = index;
                        _viewingAlbum = null;
                        _currentDynamicColors =
                            List<Color>.from(_defaultDynamicColors);
                      });
                    },
                    itemBuilder: (context, index) {
                      switch (index) {
                        case 0:
                          return _KeepAlivePage(
                            key: const PageStorageKey('home_keep_alive'),
                            builder: (_) => buildHomeTab(),
                          );
                        case 1:
                          return _KeepAlivePage(
                            key: const PageStorageKey('now_playing_keep_alive'),
                            builder: (_) => _buildNowPlayingTab(),
                          );
                        case 2:
                          return _KeepAlivePage(
                            key: const PageStorageKey('library_keep_alive'),
                            builder: (_) => buildLibraryTab(),
                          );
                        default:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
          ),
          Positioned(
            bottom: 18 + safeBottom,
            left: 14,
            right: 14,
            child: SafeArea(
              top: false,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    height: 64,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isDarkMode
                          ? (_darkBg).withOpacity(0.45)
                          : _lightGlassBase.withOpacity(0.86),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: _isDarkMode
                            ? _neonPurple.withOpacity(0.25)
                            : _lightAccentPink.withOpacity(0.22),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _isDarkMode
                              ? _neonPurple.withOpacity(0.15)
                              : _lightAccentPink.withOpacity(0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: _NavBarItem(
                            icon: Icons.home_rounded,
                            label: 'Home',
                            isDarkMode: _isDarkMode,
                            isSelected: _navIndex == 0,
                            onTap: () => _selectRootTab(0),
                          ),
                        ),
                        Expanded(
                          child: _NavBarItem(
                            icon: Icons.album_rounded,
                            label: 'Now Playing',
                            isDarkMode: _isDarkMode,
                            isSelected: _navIndex == 1,
                            onTap: () => _selectRootTab(1),
                          ),
                        ),
                        Expanded(
                          child: _NavBarItem(
                            icon: Icons.library_music_rounded,
                            label: 'Library',
                            isDarkMode: _isDarkMode,
                            isSelected: _navIndex == 2,
                            onTap: () => _selectRootTab(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _nowPlaying,
            builder: (context, _) {
              final hasCurrentTrack = _nowPlaying.hasCurrentTrack;
              final shouldShowMiniPlayer = hasCurrentTrack && _navIndex != 1;
              if (!shouldShowMiniPlayer) {
                return const SizedBox.shrink();
              }
              final track = _nowPlaying.track;
              final trackKey = track == null ? 'mini-player' : track.id;
              return Positioned(
                bottom: 88 + safeBottom,
                left: 16,
                right: 16,
                child: FadeSlideIn(
                  key: ValueKey('mini-$trackKey-$shouldShowMiniPlayer'),
                  child: _PlayerFloatingBar(
                    player: _player,
                    onNext: () => _playNext(),
                    onPrev: () => _playPrev(),
                    onOpenNowPlaying: () => _selectRootTab(1),
                    resolveMiniPlayerTrack: _resolveMiniPlayerTrack,
                    onPlayFromQueue: (track, index) => _playQueueIndex(index),
                    isDarkMode: _isDarkMode,
                    knownTrackDurationsMs: _knownTrackDurationsMs,
                    knownTrackDurations: _knownTrackDurations,
                  ),
                ),
              );
            },
          ),
          ValueListenableBuilder<String?>(
            valueListenable: _localImportStatus,
            builder: (context, status, _) {
              final message = status?.trim() ?? '';
              if (message.isEmpty) return const SizedBox.shrink();
              return Positioned(
                top: 18,
                left: 18,
                right: 18,
                child: IgnorePointer(
                  child: GlassyContainer(
                    radius: 18,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    customBorder:
                        (_isDarkMode ? _accentDefault : _lightAccentPink)
                            .withOpacity(0.22),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: _pink,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            message,
                            style: GoogleFonts.inter(
                              color: _isDarkMode ? _textPri : _lightText,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSignInScreenFromPart() {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildAppBackground(
              [_pink, _accentDefault, _purple, _cyan],
              signIn: true,
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: _buildSourceChoiceContent(
                  compact: false,
                  onDrive: _signIn,
                  onLocal: _showLocalImportChooser,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSourceChoiceSheetFromPart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.72),
      builder: (sheetContext) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            margin: const EdgeInsets.only(top: 110),
            decoration: BoxDecoration(
              color: (_isDarkMode ? _darkBg : _lightBg).withOpacity(0.98),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border(
                top: BorderSide(
                  color: (_isDarkMode ? Colors.white : Colors.black)
                      .withOpacity(0.08),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                child: _buildSourceChoiceContent(
                  compact: true,
                  onDrive: () {
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _signIn();
                    });
                  },
                  onLocal: () {
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _showLocalImportChooser();
                    });
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSourceChoiceContent({
    required bool compact,
    required VoidCallback onDrive,
    required VoidCallback onLocal,
  }) {
    final accent = _isDarkMode ? _accentDefault : _lightAccentPink;
    final subTextColor = _isDarkMode ? _textSub : _lightSubtext;
    final titleSize = compact ? 30.0 : 44.0;
    final spacing = compact ? 2.5 : 4.0;

    Widget buildChoiceCard({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return PressableScale(
        onTap: onTap,
        child: GlassyContainer(
          radius: 24,
          padding: const EdgeInsets.all(18),
          customBorder: accent.withOpacity(0.28),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      accent.withOpacity(0.34),
                      accent.withOpacity(0.12),
                    ],
                  ),
                ),
                child: Icon(icon, color: accent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: _isDarkMode ? _textPri : _lightText,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: subTextColor,
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGradientText('INFAME', size: titleSize, spacing: spacing),
        const SizedBox(height: 12),
        Text(
          'Choose where your music comes from.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: subTextColor,
            fontSize: compact ? 13 : 14,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 22),
        buildChoiceCard(
          icon: Icons.cloud_rounded,
          title: 'Use Google Drive',
          subtitle: 'Sign in and browse your Drive library.',
          onTap: onDrive,
        ),
        const SizedBox(height: 14),
        buildChoiceCard(
          icon: Icons.folder_open_rounded,
          title: 'Use Local Files',
          subtitle: 'Import files or scan a music folder without signing in.',
          onTap: onLocal,
        ),
        const SizedBox(height: 18),
        ValueListenableBuilder<String?>(
          valueListenable: _localImportStatus,
          builder: (context, status, _) {
            final message = status?.trim() ?? '';
            if (message.isNotEmpty) {
              return GlassyContainer(
                radius: 18,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                customBorder: accent.withOpacity(0.18),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: _pink,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: GoogleFonts.inter(
                          color: _isDarkMode ? _textPri : _lightText,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return _signingIn
                ? const Center(child: CircularProgressIndicator(color: _pink))
                : Text(
                    _user == null
                        ? 'Google login is only needed for Drive.'
                        : 'Drive is connected. Local files still work too.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: subTextColor.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  );
          },
        ),
      ],
    );
  }

  Widget _buildNowPlayingTabFromPart() {
    return ListenableBuilder(
      listenable: _nowPlaying,
      builder: (context, _) {
        final track = _nowPlaying.track;
        if (track == null) {
          final textColor = _isDarkMode ? _darkTextPri : _lightTextPri;
          final subTextColor = _isDarkMode ? _darkTextSub : _lightTextSub;
          final accent = _isDarkMode ? _neonPurple : _lightAccentPink;
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.music_off_rounded, size: 52, color: accent),
                  const SizedBox(height: 16),
                  Text(
                    'Nothing playing',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick something from Home or Library',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: subTextColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final trackId = DriveUtils.effectiveId(track) ?? '';
        final record = trackId.isEmpty ? null : _libraryTrackIndex[trackId];
        final albumName =
            ((record?['album'] ?? record?['albumName'] ?? '')).trim();

        return _FullScreenPlayerSheet(
          player: _player,
          onNext: () => _playNext(),
          onPrev: () => _playPrev(),
          onPlayFromQueue: (queueTrack, index) => _playQueueIndex(index),
          onRemoveQueueItemAt: _removeQueueItemAt,
          onClearUpcomingQueue: _clearUpcomingQueue,
          isDarkMode: _isDarkMode,
          albumName: albumName,
          isLiked: _isTrackLiked(track),
          onToggleLiked: () => _toggleLikedTrack(track),
          knownTrackDurationsMs: _knownTrackDurationsMs,
          knownTrackDurations: _knownTrackDurations,
          embedded: true,
        );
      },
    );
  }
}
