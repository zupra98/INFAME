part of '../main.dart';

extension BuildLibraryTabExtension on _MainScreenState {
  String _libraryAlbumTitle(Map<String, String> album) {
    final brain = _libraryBrain[album['id'] ?? ''];
    return brain?['displayName'] ??
        album['displayName'] ??
        album['name'] ??
        'Album';
  }

  String _libraryAlbumArtist(Map<String, String> album) {
    final brain = _libraryBrain[album['id'] ?? ''];
    final artist = _cleanBrainValue(brain?['artist']).isNotEmpty
        ? brain!['artist']!
        : _cleanBrainValue(album['artist']).isNotEmpty
            ? album['artist']!
            : _artistAlbumFromFolder(album['name'] ?? '')['artist'] ?? '';
    return artist;
  }

  String _libraryAlbumSearchCacheKey(Map<String, String> album) {
    final id = album['id'] ?? '';
    if (id.isNotEmpty) return id;

    final title = album['name'] ?? album['displayName'] ?? '';
    final artist = album['artist'] ?? '';

    return '$title|$artist';
  }

  String _cachedLibraryAlbumSearchText(Map<String, String> album) {
    final key = _libraryAlbumSearchCacheKey(album);

    final cached = _librarySearchTextCache[key];
    if (cached != null) return cached;

    final text = _libraryAlbumSearchText(album);
    _librarySearchTextCache[key] = text;
    return text;
  }

  String _libraryAlbumSearchText(Map<String, String> album) {
    final brain = _libraryBrain[album['id'] ?? ''] ?? const <String, String>{};
    final tracks = _albumTracksCache[album['id'] ?? ''] ?? const <drive.File>[];
    final trackText = <String>[];

    for (final track in tracks) {
      final cached = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      trackText.add(track.name ?? '');
      if (cached != null) {
        trackText.addAll([
          cached.title,
          cached.artist,
          cached.album ?? '',
          cached.year ?? '',
          cached.genre ?? '',
        ]);
      }
    }

    return [
      album['name'] ?? '',
      album['displayName'] ?? '',
      album['artist'] ?? '',
      album['genre'] ?? '',
      album['year'] ?? '',
      brain['displayName'] ?? '',
      brain['artist'] ?? '',
      brain['genre'] ?? '',
      brain['year'] ?? '',
      _artistAlbumFromFolder(album['name'] ?? '')['artist'] ?? '',
      _artistAlbumFromFolder(album['name'] ?? '')['album'] ?? '',
      ...trackText,
    ].join(' ').toLowerCase();
  }

  bool _libraryAlbumMatches(Map<String, String> album, String query) {
    if (query.isEmpty) return true;
    final words = query.split(RegExp(r'\s+')).where((w) => w.trim().isNotEmpty);
    final haystack = _cachedLibraryAlbumSearchText(album);
    return words.every((word) => haystack.contains(word));
  }

  int _visibleArtistCount() {
    final artists = <String>{};
    for (final album in _albums) {
      final artist = _cleanBrainValue(_libraryAlbumArtist(album));
      if (artist.isNotEmpty) artists.add(artist.toLowerCase());
    }
    return artists.length;
  }

  List<Map<String, String>> _cachedVisibleAlbumsForQuery(String query) {
    final cacheKey = [
      query,
      _librarySortMode,
      _libraryGridMode,
      _libraryViewMode,
      _albums.length,
      _libraryTrackIndex.length,
      _homeBrowseCacheVersion,
      _libraryBrowseCacheVersion,
    ].join('|');
    if (_cachedLibraryAlbumsKey == cacheKey) return _cachedVisibleLibraryAlbums;

    final visibleAlbums =
        _albums.where((album) => _libraryAlbumMatches(album, query)).toList();

    visibleAlbums.sort((a, b) {
      final an = _libraryAlbumTitle(a).toLowerCase();
      final bn = _libraryAlbumTitle(b).toLowerCase();
      if (_librarySortMode == 'artist') {
        final aa = _libraryAlbumArtist(a).toLowerCase();
        final ba = _libraryAlbumArtist(b).toLowerCase();
        final byArtist = aa.compareTo(ba);
        if (byArtist != 0) return byArtist;
      }
      if (_librarySortMode == 'za') return bn.compareTo(an);
      return an.compareTo(bn);
    });

    _cachedLibraryAlbumsKey = cacheKey;
    _cachedVisibleLibraryAlbums = visibleAlbums;
    return visibleAlbums;
  }

  ({List<Map<String, String>> records, List<drive.File> files})
      _cachedVisibleSongsForQuery(String query) {
    final cacheKey = [
      query,
      _libraryViewMode,
      _libraryTrackIndex.length,
      _albums.length,
      _libraryBrowseCacheVersion,
    ].join('|');
    if (_cachedLibrarySongsKey == cacheKey) {
      return (
        records: _cachedVisibleLibrarySongs,
        files: _cachedVisibleLibrarySongFiles,
      );
    }

    final visibleSongs = <Map<String, String>>[];
    for (final record in _libraryTrackIndex.values) {
      final title = record['title'] ?? record['name'] ?? '';
      final artist = record['artist'] ?? '';
      final album = record['albumName'] ?? '';
      final year = record['year'] ?? '';
      final genre = record['genre'] ?? '';
      final filename = record['name'] ?? '';

      final searchText =
          '$title $artist $album $year $genre $filename'.toLowerCase();
      if (query.isEmpty || searchText.contains(query)) {
        visibleSongs.add(record);
      }
    }

    visibleSongs.sort((a, b) {
      final at = a['title'] ?? a['name'] ?? '';
      final bt = b['title'] ?? b['name'] ?? '';
      return at.toLowerCase().compareTo(bt.toLowerCase());
    });

    final visibleSongFiles =
        visibleSongs.map((r) => _fileFromTrackIndexRecord(r)).toList();

    _cachedLibrarySongsKey = cacheKey;
    _cachedVisibleLibrarySongs = visibleSongs;
    _cachedVisibleLibrarySongFiles = visibleSongFiles;
    return (records: visibleSongs, files: visibleSongFiles);
  }

  ({Map<String, List<Map<String, String>>> grouped, List<String> names})
      _cachedVisibleArtistsForQuery(String query) {
    final cacheKey = [
      query,
      _libraryViewMode,
      _libraryTrackIndex.length,
      _libraryBrowseCacheVersion,
    ].join('|');
    if (_cachedLibraryArtistsKey == cacheKey) {
      return (
        grouped: _cachedLibraryArtists,
        names: _cachedVisibleLibraryArtists
      );
    }

    final artists = <String, List<Map<String, String>>>{};
    for (final record in _libraryTrackIndex.values) {
      final artist = record['artist'] ?? '';
      if (artist.isEmpty) continue;
      artists.putIfAbsent(artist, () => []);
      artists[artist]!.add(record);
    }

    final artistNames = artists.keys.toList();
    final visibleArtists = artistNames
        .where(
            (artist) => query.isEmpty || artist.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    _cachedLibraryArtistsKey = cacheKey;
    _cachedLibraryArtists = artists;
    _cachedVisibleLibraryArtists = visibleArtists;
    return (grouped: artists, names: visibleArtists);
  }

  Widget _buildSongsView(List<Color> colors, String query, Color bgColor) {
    final visibleSongsCache = _cachedVisibleSongsForQuery(query);
    final visibleSongs = visibleSongsCache.records;
    final visibleSongFiles = visibleSongsCache.files;

    return RepaintBoundary(
        child: Container(
      color: bgColor,
      child: CustomScrollView(
        key: const PageStorageKey('library_songs_scroll'),
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 14),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _buildGradientText('Songs',
                              size: 34, spacing: -1.4)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Search songs across all albums.',
                    style: GoogleFonts.inter(
                      color: _textSub,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassyContainer(
                    radius: 26,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    customColor: Colors.white.withOpacity(0.078),
                    customBorder: Colors.white.withOpacity(0.13),
                    child: TextField(
                      controller: _librarySearchController,
                      onChanged: (value) =>
                          setState(() => _libraryQuery = value),
                      style: GoogleFonts.inter(
                          color: _textPri, fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        icon:
                            Icon(Icons.manage_search_rounded, color: colors[1]),
                        suffixIcon: _libraryQuery.trim().isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    color: _textSub),
                                onPressed: () {
                                  _librarySearchController.clear();
                                  setState(() => _libraryQuery = '');
                                },
                              )
                            : null,
                        hintText: 'Search songs by title, artist, album...',
                        hintStyle: GoogleFonts.inter(
                            color: _textSub, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _LibraryModePill(
                        label: 'Albums',
                        isSelected: _libraryViewMode == 'albums',
                        onTap: () {
                          setState(() => _libraryViewMode = 'albums');
                          _saveUiPreferences();
                        },
                      ),
                      const SizedBox(width: 8),
                      _LibraryModePill(
                        label: 'Songs',
                        isSelected: _libraryViewMode == 'songs',
                        onTap: () {
                          setState(() => _libraryViewMode = 'songs');
                          _saveUiPreferences();
                        },
                      ),
                      const SizedBox(width: 8),
                      _LibraryModePill(
                        label: 'Artists',
                        isSelected: _libraryViewMode == 'artists',
                        onTap: () {
                          setState(() => _libraryViewMode = 'artists');
                          _saveUiPreferences();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _LibraryInfoChip(
                          label: '${visibleSongs.length} songs',
                          accent: colors[1]),
                      _LibraryInfoChip(
                          label: '${_libraryTrackIndex.length} indexed',
                          accent: colors[2]),
                      _LibraryInfoChip(
                          label: '${_albums.length} albums', accent: colors[0]),
                      if (_libraryQuery.trim().isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(() => _libraryQuery = ''),
                          child: _LibraryInfoChip(
                              label: 'Clear search ×', accent: _pink),
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
                      'Song index is empty.',
                      style: GoogleFonts.inter(
                          color: _textPri, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Indexed songs: ${_libraryTrackIndex.length}',
                      style: GoogleFonts.inter(
                          color: _textSub, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Albums in library: ${_albums.length}',
                      style: GoogleFonts.inter(
                          color: _textSub, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Open albums or run Library metadata scan to build the song list.',
                      style: GoogleFonts.inter(
                          color: _textSub, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
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
                      'No songs match that search.',
                      style: GoogleFonts.inter(
                          color: _textPri, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => setState(() => _libraryQuery = ''),
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

                  return GestureDetector(
                    key: ValueKey(record['id']),
                    onTap: () {
                      _playSong(
                        file,
                        queue: visibleSongFiles,
                        idx: i,
                        coverUrl: coverUrl,
                        colors: _currentDynamicColors,
                      );
                    },
                    behavior: HitTestBehavior.opaque,
                    child: GlassyContainer(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      radius: 20,
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
                                    borderRadius:
                                        BorderRadius.circular(kArtworkRadius),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: _textPri,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  artist.isNotEmpty ? artist : album,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: _textSub,
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
                                  color: _textSub,
                                  fontWeight: FontWeight.w700),
                            ),
                          const SizedBox(width: 8),
                          PopupMenuButton<int>(
                            tooltip: 'Track options',
                            icon: const Icon(Icons.more_vert_rounded,
                                color: _textSub, size: 20),
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

  Widget _buildArtistsView(List<Color> colors, String query, Color bgColor) {
    final artistsCache = _cachedVisibleArtistsForQuery(query);
    final artists = artistsCache.grouped;
    final visibleArtists = artistsCache.names;

    return RepaintBoundary(
        child: Container(
      color: bgColor,
      child: CustomScrollView(
        key: const PageStorageKey('library_artists_scroll'),
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 14),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _buildGradientText('Artists',
                              size: 34, spacing: -1.4)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Browse artists from your library.',
                    style: GoogleFonts.inter(
                      color: _textSub,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassyContainer(
                    radius: 26,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    customColor: Colors.white.withOpacity(0.078),
                    customBorder: Colors.white.withOpacity(0.13),
                    child: TextField(
                      controller: _librarySearchController,
                      onChanged: (value) =>
                          setState(() => _libraryQuery = value),
                      style: GoogleFonts.inter(
                          color: _textPri, fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        icon:
                            Icon(Icons.manage_search_rounded, color: colors[1]),
                        suffixIcon: _libraryQuery.trim().isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    color: _textSub),
                                onPressed: () {
                                  _librarySearchController.clear();
                                  setState(() => _libraryQuery = '');
                                },
                              )
                            : null,
                        hintText: 'Search artists...',
                        hintStyle: GoogleFonts.inter(
                            color: _textSub, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _LibraryModePill(
                        label: 'Albums',
                        isSelected: _libraryViewMode == 'albums',
                        onTap: () {
                          setState(() => _libraryViewMode = 'albums');
                          _saveUiPreferences();
                        },
                      ),
                      const SizedBox(width: 8),
                      _LibraryModePill(
                        label: 'Songs',
                        isSelected: _libraryViewMode == 'songs',
                        onTap: () {
                          setState(() => _libraryViewMode = 'songs');
                          _saveUiPreferences();
                        },
                      ),
                      const SizedBox(width: 8),
                      _LibraryModePill(
                        label: 'Artists',
                        isSelected: _libraryViewMode == 'artists',
                        onTap: () {
                          setState(() => _libraryViewMode = 'artists');
                          _saveUiPreferences();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _LibraryInfoChip(
                          label: '${visibleArtists.length} artists',
                          accent: colors[1]),
                      _LibraryInfoChip(
                          label: '${artists.length} total', accent: colors[2]),
                      if (_libraryQuery.trim().isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(() => _libraryQuery = ''),
                          child: _LibraryInfoChip(
                              label: 'Clear search ×', accent: _pink),
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
                      'Song index is empty.',
                      style: GoogleFonts.inter(
                          color: _textPri, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Indexed songs: ${_libraryTrackIndex.length}',
                      style: GoogleFonts.inter(
                          color: _textSub, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Albums in library: ${_albums.length}',
                      style: GoogleFonts.inter(
                          color: _textSub, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Open albums or run Library metadata scan to build the song list.',
                      style: GoogleFonts.inter(
                          color: _textSub, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
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
          else if (visibleArtists.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No artists match that search.',
                      style: GoogleFonts.inter(
                          color: _textPri, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => setState(() => _libraryQuery = ''),
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
                  final artist = visibleArtists[i];
                  final songCount = artists[artist]!.length;
                  final albumSet = <String>{};
                  for (final record in artists[artist]!) {
                    final album = record['albumName'] ?? '';
                    if (album.isNotEmpty) albumSet.add(album);
                  }
                  final albumCount = albumSet.length;

                  return GestureDetector(
                    key: ValueKey(artist),
                    onTap: () {
                      // TODO: Implement artist detail view
                    },
                    behavior: HitTestBehavior.opaque,
                    child: GlassyContainer(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      radius: 20,
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: colors,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                artist[0].toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                  '$songCount songs • $albumCount albums',
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: _textSub,
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: _textSub),
                        ],
                      ),
                    ),
                  );
                }, childCount: visibleArtists.length),
              ),
            ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 170),
          ),
        ],
      ),
    ));
  }

  Widget buildLibraryTab() {
    final stopwatch = Stopwatch()..start();
    final colors = _safeColors(_currentDynamicColors);
    final query = _libraryQuery.trim().toLowerCase();
    final bgColor = _isDarkMode ? _darkBg : _lightBg;

    if (_libraryViewMode == 'songs') {
      final page = _buildSongsView(colors, query, bgColor);
      assert(() {
        debugPrint('Library build (songs): ${stopwatch.elapsedMicroseconds}us');
        return true;
      }());
      return page;
    }

    if (_libraryViewMode == 'artists') {
      final page = _buildArtistsView(colors, query, bgColor);
      assert(() {
        debugPrint(
            'Library build (artists): ${stopwatch.elapsedMicroseconds}us');
        return true;
      }());
      return page;
    }

    final visibleAlbums = _cachedVisibleAlbumsForQuery(query);

    final page = RepaintBoundary(
        child: Container(
      color: bgColor,
      child: CustomScrollView(
        key: const PageStorageKey('library_tab_scroll'),
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 14),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _buildGradientText('Crates',
                              size: 34, spacing: -1.4)),
                      IconButton(
                        tooltip: _libraryGridMode ? 'List view' : 'Grid view',
                        icon: Icon(
                          _libraryGridMode
                              ? Icons.view_list_rounded
                              : Icons.grid_view_rounded,
                          color: _textSub,
                        ),
                        onPressed: () => setState(
                            () => _libraryGridMode = !_libraryGridMode),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Sort library',
                        icon: const Icon(Icons.sort_rounded, color: _textSub),
                        color: const Color(0xFF1A1A22),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        onSelected: (value) =>
                            setState(() => _librarySortMode = value),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'az',
                            child: Text('Album A–Z',
                                style: GoogleFonts.inter(color: _textPri)),
                          ),
                          PopupMenuItem(
                            value: 'za',
                            child: Text('Album Z–A',
                                style: GoogleFonts.inter(color: _textPri)),
                          ),
                          PopupMenuItem(
                            value: 'artist',
                            child: Text('Artist A–Z',
                                style: GoogleFonts.inter(color: _textPri)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Search albums, artists, songs, years — all in one place.',
                    style: GoogleFonts.inter(
                      color: _textSub,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassyContainer(
                    radius: 26,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    customColor: Colors.white.withOpacity(0.078),
                    customBorder: Colors.white.withOpacity(0.13),
                    child: TextField(
                      controller: _librarySearchController,
                      onChanged: (value) =>
                          setState(() => _libraryQuery = value),
                      style: GoogleFonts.inter(
                          color: _textPri, fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        icon:
                            Icon(Icons.manage_search_rounded, color: colors[1]),
                        suffixIcon: _libraryQuery.trim().isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    color: _textSub),
                                onPressed: () {
                                  _librarySearchController.clear();
                                  setState(() => _libraryQuery = '');
                                },
                              )
                            : null,
                        hintText: 'Search Nas, Illmatic, track names...',
                        hintStyle: GoogleFonts.inter(
                            color: _textSub, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _LibraryModePill(
                        label: 'Albums',
                        isSelected: _libraryViewMode == 'albums',
                        onTap: () {
                          setState(() => _libraryViewMode = 'albums');
                          _saveUiPreferences();
                        },
                      ),
                      const SizedBox(width: 8),
                      _LibraryModePill(
                        label: 'Songs',
                        isSelected: _libraryViewMode == 'songs',
                        onTap: () {
                          setState(() => _libraryViewMode = 'songs');
                          _saveUiPreferences();
                        },
                      ),
                      const SizedBox(width: 8),
                      _LibraryModePill(
                        label: 'Artists',
                        isSelected: _libraryViewMode == 'artists',
                        onTap: () {
                          setState(() => _libraryViewMode = 'artists');
                          _saveUiPreferences();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _LibraryInfoChip(
                          label:
                              '${visibleAlbums.length}/${_albums.length} albums',
                          accent: colors[1]),
                      _LibraryInfoChip(
                          label: '${_visibleArtistCount()} artists',
                          accent: colors[2]),
                      _LibraryInfoChip(
                          label: '${_metaStore.count} tagged tracks',
                          accent: colors[0]),
                      if (_libraryQuery.trim().isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(() => _libraryQuery = ''),
                          child: _LibraryInfoChip(
                              label: 'Clear search ×', accent: _pink),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_loadingSaved || _isScanning)
            const SliverFillRemaining(
              child: Center(
                  child: CircularProgressIndicator(color: _accentDefault)),
            )
          else if (_albums.isEmpty)
            const SliverFillRemaining(
              child: Center(
                  child: Text('Library is empty.',
                      style: TextStyle(color: _textSub))),
            )
          else if (visibleAlbums.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No records match that search.',
                      style: GoogleFonts.inter(
                          color: _textPri, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => setState(() => _libraryQuery = ''),
                      child: Text('Clear search',
                          style: GoogleFonts.inter(
                              color: colors[1], fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ),
            )
          else if (_libraryGridMode)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate((ctx, i) {
                  final album = visibleAlbums[i];
                  final merged = Map<String, String>.from(album);
                  final brain = _libraryBrain[album['id'] ?? ''];
                  if (brain != null) merged.addAll(brain);
                  final folderGuess =
                      _artistAlbumFromFolder(album['name'] ?? '');
                  merged['artist'] = _libraryAlbumArtist(album);
                  merged['displayName'] = _libraryAlbumTitle(album);
                  if ((merged['artist'] ?? '').isEmpty &&
                      folderGuess['artist'] != null) {
                    merged['artist'] = folderGuess['artist']!;
                  }
                  return _AlbumGridCard(
                    key: ValueKey(album['id'] ?? album['name']),
                    album: merged,
                    onTap: () => _openAlbum(album),
                    isDarkMode: _isDarkMode,
                  );
                }, childCount: visibleAlbums.length),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((ctx, i) {
                  final album = visibleAlbums[i];
                  final brain = _libraryBrain[album['id'] ?? ''];
                  final name = _libraryAlbumTitle(album);
                  final artist = _libraryAlbumArtist(album);
                  final year = brain?['year'] ?? album['year'] ?? '';
                  final genre = brain?['genre'] ?? album['genre'] ?? '';
                  final coverUrl = album['cover'] ?? brain?['cover'] ?? '';
                  final gradient = getAlbumGradient(name);

                  return GestureDetector(
                    key: ValueKey(album['id'] ?? album['name']),
                    onTap: () => _openAlbum(album),
                    behavior: HitTestBehavior.opaque,
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
                              borderRadius:
                                  BorderRadius.circular(kArtworkRadius),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                              : 'Album • Drive',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: _textSub,
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: _textSub),
                        ],
                      ),
                    ),
                  );
                }, childCount: visibleAlbums.length),
              ),
            ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 170),
          ),
        ],
      ),
    ));
    assert(() {
      debugPrint('Library build (albums): ${stopwatch.elapsedMicroseconds}us');
      return true;
    }());
    return page;
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
  final VoidCallback onTap;

  const _LibraryModePill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color:
              isSelected ? Colors.white.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? Colors.white.withOpacity(0.24)
                : Colors.white.withOpacity(0.12),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.60),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
