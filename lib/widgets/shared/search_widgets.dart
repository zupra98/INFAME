part of '../../main.dart';

extension _SearchWidgetsExtension on _MainScreenState {
  Widget _buildSearchTabFromPart() {
    final colors = _safeColors(_currentDynamicColors);
    final query = _searchQuery.trim().toLowerCase();
    final selectedMode = _searchViewMode;
    final bgColor = _isDarkMode ? _darkBg : _lightBg;
    final albumsCache = _cachedVisibleAlbumsForQuery(query);
    final songsCache = _cachedVisibleSongsForQuery(query);
    final likedSongsCache = _cachedVisibleSongsForQuery(query, likedOnly: true);
    final artistsCache = _cachedVisibleArtistsForQuery(query);
    final albums = albumsCache;
    final songs = songsCache.records;
    final songFiles = songsCache.files;
    final likedSongs = likedSongsCache.records;
    final likedSongFiles = likedSongsCache.files;
    final artists = artistsCache.grouped;
    final visibleArtists = artistsCache.names;
    final showAll = selectedMode == 'all';
    final showAlbums = showAll || selectedMode == 'albums';
    final showArtists = showAll || selectedMode == 'artists';
    final showSongs = showAll || selectedMode == 'songs';
    final showLiked = showAll || selectedMode == 'liked';
    final hasVisibleResults = showAll
        ? albums.isNotEmpty ||
            visibleArtists.isNotEmpty ||
            songs.isNotEmpty ||
            likedSongs.isNotEmpty
        : showAlbums
            ? albums.isNotEmpty
            : showArtists
                ? visibleArtists.isNotEmpty
                : showSongs
                    ? songs.isNotEmpty
                    : likedSongs.isNotEmpty;

    debugPrint(
      '[Search] results rebuilt: category=$selectedMode count=${showAll ? (albums.length + visibleArtists.length + songs.length + likedSongs.length) : (showAlbums ? albums.length : showArtists ? visibleArtists.length : showSongs ? songs.length : likedSongs.length)}',
    );

    return RepaintBoundary(
      child: Container(
        color: bgColor,
        child: CustomScrollView(
          key: const PageStorageKey('search_tab_scroll'),
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
                          child: _buildGradientText(
                            'Search',
                            size: 34,
                            spacing: -1.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Search songs, albums, artists and liked tracks.',
                      style: GoogleFonts.inter(
                        color: _textSub,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildLibrarySearchBar(
                      colors,
                      hintText: 'Search Nas, albums, artists...',
                      controller: _searchSearchController,
                      onChanged: (value) {
                        debugPrint('[Search] query changed: "$value"');
                        _searchSetState(() => _searchQuery = value);
                      },
                      query: _searchQuery,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SearchModePill(
                          label: 'All',
                          isSelected: selectedMode == 'all',
                          isDarkMode: _isDarkMode,
                          onTap: () {
                            debugPrint('[Search] category selected: all');
                            _searchSetState(() => _searchViewMode = 'all');
                          },
                        ),
                        _SearchModePill(
                          label: 'Albums',
                          isSelected: selectedMode == 'albums',
                          isDarkMode: _isDarkMode,
                          onTap: () {
                            debugPrint('[Search] category selected: albums');
                            _searchSetState(() => _searchViewMode = 'albums');
                          },
                        ),
                        _SearchModePill(
                          label: 'Artists',
                          isSelected: selectedMode == 'artists',
                          isDarkMode: _isDarkMode,
                          onTap: () {
                            debugPrint('[Search] category selected: artists');
                            _searchSetState(() => _searchViewMode = 'artists');
                          },
                        ),
                        _SearchModePill(
                          label: 'Songs',
                          isSelected: selectedMode == 'songs',
                          isDarkMode: _isDarkMode,
                          onTap: () {
                            debugPrint('[Search] category selected: songs');
                            _searchSetState(() => _searchViewMode = 'songs');
                          },
                        ),
                        if (_likedTrackKeys.isNotEmpty)
                          _SearchModePill(
                            label: 'Liked',
                            isSelected: selectedMode == 'liked',
                            isDarkMode: _isDarkMode,
                            onTap: () {
                              debugPrint('[Search] category selected: liked');
                              _searchSetState(() => _searchViewMode = 'liked');
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (!hasVisibleResults)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'No results found.',
                        style: GoogleFonts.inter(
                          color: _textPri,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () {
                          _searchSearchController.clear();
                          _searchSetState(() => _searchQuery = '');
                        },
                        child: Text(
                          'Clear search',
                          style: GoogleFonts.inter(
                            color: colors[1],
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              if (showArtists && visibleArtists.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Artists',
                      style: GoogleFonts.inter(
                        color: _isDarkMode ? Colors.white : _textPri,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((ctx, i) {
                      final artist = visibleArtists[i];
                      final records =
                          artists[artist] ?? const <Map<String, String>>[];
                      final albumSet = <String>{};
                      for (final record in records) {
                        final album = record['albumName'] ?? '';
                        if (album.isNotEmpty) albumSet.add(album);
                      }

                      final artistAlbums = _albums.where((album) {
                        final resolved = _resolvedAlbumMap(album);
                        final albumArtist = _canonicalArtistName(
                          albumArtist: _libraryAlbumArtist(resolved),
                          trackArtist: _libraryBrain[resolved['id'] ?? '']
                                  ?['artist'] ??
                              resolved['artist'] ??
                              '',
                          albumName:
                              resolved['name'] ?? resolved['displayName'] ?? '',
                        );
                        return albumArtist.toLowerCase() ==
                            artist.toLowerCase();
                      }).map((album) {
                        final resolved = _resolvedAlbumMap(album);
                        final merged = Map<String, String>.from(resolved);
                        final brain = _libraryBrain[resolved['id'] ?? ''];
                        if (brain != null) merged.addAll(brain);
                        merged['artist'] = _libraryAlbumArtist(resolved);
                        merged['displayName'] = _libraryAlbumTitle(
                          resolved,
                        );
                        return merged;
                      }).toList();

                      return FadeSlideIn(
                        key: ValueKey('search-artist-$artist'),
                        child: PressableScale(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _ArtistDetailPage(
                                  artistName: artist,
                                  artistImageUrl:
                                      _artistImageCache[_artistImageCacheKey(
                                            artist,
                                          )] ??
                                          '',
                                  artistAlbums: artistAlbums,
                                  artistTrackRecords: records,
                                  isDarkMode: _isDarkMode,
                                  accentColors: _safeColors(colors),
                                  onOpenAlbum: _openAlbum,
                                  onPlayTrack: (file,
                                      {queue, idx, coverUrl, colors}) {
                                    return _playSong(
                                      file,
                                      queue: queue,
                                      idx: idx,
                                      coverUrl: coverUrl,
                                      colors: colors,
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                          child: GlassyContainer(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            radius: 20,
                            child: Row(
                              children: [
                                _ArtistAvatar(
                                  artistName: artist,
                                  imageUrl:
                                      _artistImageCache[_artistImageCacheKey(
                                    artist,
                                  )],
                                  colors: colors,
                                  size: 56,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: _textPri,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${records.length} songs â€¢ ${albumSet.length} albums',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: _textSub,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: _textSub,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }, childCount: visibleArtists.length),
                  ),
                ),
              ],
              if (showAlbums && albums.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Albums',
                      style: GoogleFonts.inter(
                        color: _isDarkMode ? Colors.white : _textPri,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((ctx, i) {
                      final album = _resolvedAlbumMap(albums[i]);
                      final brain = _libraryBrain[album['id'] ?? ''];
                      final name = _libraryAlbumTitle(album);
                      final artist = _libraryAlbumArtist(album);
                      final year = brain?['year'] ?? album['year'] ?? '';
                      final genre = brain?['genre'] ?? album['genre'] ?? '';
                      final coverUrl = album['cover'] ?? brain?['cover'] ?? '';
                      final gradient = getAlbumGradient(name);

                      return FadeSlideIn(
                        key: ValueKey(
                          'search-album-${album['id'] ?? album['name']}',
                        ),
                        child: PressableScale(
                          onTap: () => _openAlbum(album),
                          child: GlassyContainer(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            radius: 20,
                            child: Row(
                              children: [
                                Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      kArtworkRadius,
                                    ),
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
                                            errorBuilder: (_, __, ___) =>
                                                _AlbumFallbackCover(
                                              name: name,
                                              colors: gradient,
                                              radius: kArtworkRadius,
                                              small: true,
                                            ),
                                          ),
                                        )
                                      : _AlbumFallbackCover(
                                          name: name,
                                          colors: gradient,
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
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: _textPri,
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
                                                    : 'Album â€¢ Drive',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: _textSub,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: _textSub,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }, childCount: albums.length),
                  ),
                ),
              ],
              if (showSongs && songs.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Songs',
                      style: GoogleFonts.inter(
                        color: _isDarkMode ? Colors.white : _textPri,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 18),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((ctx, i) {
                      final record = songs[i];
                      final file = songFiles[i];
                      final coverUrl = record['albumCover'] ?? '';
                      return _TrackGlassTile(
                        key: ValueKey('search-song-${record['id']}'),
                        track: file,
                        queue: songFiles,
                        index: i,
                        coverUrl: coverUrl,
                        isLiked: _isTrackLiked(file),
                        onTap: () {
                          unawaited(
                            _playSong(
                              file,
                              queue: songFiles,
                              idx: i,
                              coverUrl: coverUrl,
                              colors: _currentDynamicColors,
                            ),
                          );
                        },
                        onToggleLiked: () => _toggleLikedTrack(file),
                        onPlayNext: () => _addTracksPlayNext([file]),
                        onAddToQueue: () => _addTracksToQueueEnd([file]),
                        isDarkMode: _isDarkMode,
                      );
                    }, childCount: songs.length),
                  ),
                ),
              ],
              if (showLiked && likedSongs.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Liked',
                      style: GoogleFonts.inter(
                        color: _isDarkMode ? Colors.white : _textPri,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 18),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((ctx, i) {
                      final record = likedSongs[i];
                      final file = likedSongFiles[i];
                      final coverUrl = record['albumCover'] ?? '';

                      return _TrackGlassTile(
                        key: ValueKey('search-liked-${record['id']}'),
                        track: file,
                        queue: [file],
                        index: 0,
                        coverUrl: coverUrl,
                        isLiked: true,
                        onTap: () {
                          unawaited(
                            _playSong(
                              file,
                              queue: [file],
                              idx: 0,
                              coverUrl: coverUrl,
                              colors: _currentDynamicColors,
                            ),
                          );
                        },
                        onToggleLiked: () => _toggleLikedTrack(file),
                        onPlayNext: () => _addTracksPlayNext([file]),
                        onAddToQueue: () => _addTracksToQueueEnd([file]),
                        isDarkMode: _isDarkMode,
                      );
                    }, childCount: likedSongs.length),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 170)),
            ],
          ],
        ),
      ),
    );
  }
}
