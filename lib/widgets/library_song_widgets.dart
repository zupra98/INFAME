part of '../main.dart';

extension _LibrarySongWidgetsExtension on _MainScreenState {
  Widget _buildSongsViewFromPart(
      List<Color> colors, String query, Color bgColor,
      {bool likedOnly = false,
      String title = 'Songs',
      String subtitle = 'Search songs across all albums.',
      String scrollKey = 'library_songs_scroll'}) {
    final pageTitleColor = _isDarkMode ? _textPri : _lightText;
    final pageSubColor = _isDarkMode ? _textSub : _lightSubtext;
    final visibleSongsCache =
        _cachedVisibleSongsForQuery(query, likedOnly: likedOnly);
    final visibleSongs = visibleSongsCache.records;
    final visibleSongFiles = visibleSongsCache.files;
    final countLabel = likedOnly
        ? '${visibleSongs.length} liked'
        : '${visibleSongs.length} songs';
    final indexedLabel = likedOnly
        ? '${_likedTrackKeys.length} liked'
        : '${_libraryTrackIndex.length} indexed';
    final infoTitle = likedOnly ? 'liked tracks' : 'albums';

    return RepaintBoundary(
        child: Container(
      color: bgColor,
      child: CustomScrollView(
        key: PageStorageKey<String>(scrollKey),
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _buildGradientText(title,
                              size: 34, spacing: -1.4)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: pageSubColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildLibrarySearchBar(
                    colors,
                    hintText: likedOnly
                        ? 'Search liked songs by title, artist, album...'
                        : 'Search songs by title, artist, album...',
                  ),
                  const SizedBox(height: 12),
                  _buildLibraryModeRow(),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _LibraryInfoChip(label: countLabel, accent: colors[1]),
                      _LibraryInfoChip(label: indexedLabel, accent: colors[2]),
                      _LibraryInfoChip(
                          label: '${_albums.length} $infoTitle',
                          accent: colors[0]),
                      if (_libraryQuery.trim().isNotEmpty)
                        GestureDetector(
                          onTap: () =>
                              _librarySetState(() => _libraryQuery = ''),
                          child: _LibraryInfoChip(
                              label: 'Clear search Ã—', accent: _pink),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_libraryTrackIndex.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      likedOnly
                          ? 'Liked songs need an indexed library.'
                          : 'Song index is empty.',
                      style: GoogleFonts.inter(
                          color: pageTitleColor, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Indexed songs: ${_libraryTrackIndex.length}',
                      style: GoogleFonts.inter(
                          color: pageSubColor, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Albums in library: ${_albums.length}',
                      style: GoogleFonts.inter(
                          color: pageSubColor, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      likedOnly
                          ? 'Like songs after they are indexed to see them here.'
                          : 'Open albums or run Library metadata scan to build the song list.',
                      style: GoogleFonts.inter(
                          color: pageSubColor, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (!likedOnly)
                      ElevatedButton(
                        onPressed: _buildLibraryTrackIndex,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors[1],
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999)),
                        ),
                        child: Text('Build Song Index',
                            style:
                                GoogleFonts.inter(fontWeight: FontWeight.w900)),
                      ),
                  ],
                ),
              ),
            )
          else if (visibleSongs.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      likedOnly
                          ? 'No liked songs match that search.'
                          : 'No songs match that search.',
                      style: GoogleFonts.inter(
                          color: pageTitleColor, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () =>
                          _librarySetState(() => _libraryQuery = ''),
                      child: Text('Clear search',
                          style: GoogleFonts.inter(
                              color: colors[1], fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((ctx, i) {
                  final record = visibleSongs[i];
                  final file = visibleSongFiles[i];
                  final title = record['title'] ?? record['name'] ?? '';
                  final artist = record['artist'] ?? '';
                  final album = record['albumName'] ?? '';
                  final coverUrl = record['albumCover'] ?? '';
                  final durationMsStr = record['durationMs'];
                  final durationMs =
                      durationMsStr != null && durationMsStr.isNotEmpty
                          ? int.tryParse(durationMsStr)
                          : null;
                  final duration = durationMs != null && durationMs > 0
                      ? Duration(milliseconds: durationMs)
                      : _knownTrackDurations[file.id];
                  final liked = _isTrackLiked(file);

                  return ListenableBuilder(
                    listenable: _nowPlaying,
                    builder: (context, _) {
                      final activeId = _nowPlaying.track == null
                          ? null
                          : DriveUtils.effectiveId(_nowPlaying.track!);
                      final isActive = activeId != null &&
                          activeId == DriveUtils.effectiveId(file);
                      final glowColor =
                          _isDarkMode ? _neonMagenta : _lightAccentPink;
                      final textColor = isActive
                          ? glowColor
                          : (_isDarkMode ? Colors.white : _lightText);
                      final subColor = isActive
                          ? glowColor.withOpacity(0.82)
                          : (_isDarkMode ? _textSub : _lightSubtext);

                      return FadeSlideIn(
                        key: ValueKey('song-${record['id']}'),
                        child: PressableScale(
                          onTap: () {
                            _playSong(
                              file,
                              queue: visibleSongFiles,
                              idx: i,
                              coverUrl: coverUrl,
                              colors: _currentDynamicColors,
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? glowColor.withOpacity(0.08)
                                  : (_isDarkMode
                                      ? Colors.white.withOpacity(0.03)
                                      : Colors.black.withOpacity(0.03)),
                              borderRadius: BorderRadius.circular(20),
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
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.circular(kArtworkRadius),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: colors,
                                    ),
                                  ),
                                  child: coverUrl.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                              kArtworkRadius),
                                          child: _coverImage(
                                            coverUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                _AlbumFallbackCover(
                                              name: album,
                                              colors: colors,
                                              radius: kArtworkRadius,
                                              small: true,
                                            ),
                                          ),
                                        )
                                      : _AlbumFallbackCover(
                                          name: album,
                                          colors: colors,
                                          radius: kArtworkRadius,
                                          small: true,
                                        ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AnimatedDefaultTextStyle(
                                        duration:
                                            const Duration(milliseconds: 220),
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          color: textColor,
                                        ),
                                        child: Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        artist.isNotEmpty ? artist : album,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: subColor,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                                if (duration != null)
                                  Text(
                                    '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                                    style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: subColor,
                                        fontWeight: FontWeight.w700),
                                  ),
                                IconButton(
                                  tooltip: liked ? 'Unlike' : 'Like',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  splashRadius: 20,
                                  icon: Icon(
                                    liked
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: liked ? _pink : subColor,
                                    size: 20,
                                  ),
                                  onPressed: () => _toggleLikedTrack(file),
                                ),
                                const SizedBox(width: 4),
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
                                      _addTracksPlayNext([file]);
                                    } else if (value == 2) {
                                      _addTracksToQueueEnd([file]);
                                    }
                                  },
                                  itemBuilder: (context) => [
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
                          ),
                        ),
                      );
                    },
                  );
                }, childCount: visibleSongs.length),
              ),
            ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 170),
          ),
        ],
      ),
    ));
  }
}
