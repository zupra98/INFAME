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

  String _librarySongSearchText(Map<String, String> record) {
    return [
      record['title'] ?? '',
      record['artist'] ?? '',
      record['albumName'] ?? '',
      record['name'] ?? '',
      record['year'] ?? '',
      record['genre'] ?? '',
    ].join(' ').toLowerCase();
  }

  Widget _buildLibrarySearchBar(List<Color> colors,
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
            onChanged:
                onChanged ?? (value) => setState(() => _libraryQuery = value),
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
                          setState(() => _libraryQuery = '');
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

  int _visibleArtistCount() {
    return _canonicalArtistNamesFromLibrary().length;
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
      _cachedVisibleSongsForQuery(String query, {bool likedOnly = false}) {
    final cacheKey = [
      query,
      _libraryViewMode,
      _libraryTrackIndex.length,
      _albums.length,
      _likedTracksVersion,
      likedOnly,
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
      final recordKey = record['id'] ?? '';
      if (likedOnly && !(_likedTrackKeys.contains(recordKey))) continue;

      final searchText = _librarySongSearchText(record);
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

  Widget _buildSongsView(List<Color> colors, String query, Color bgColor,
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
                          onTap: () => setState(() => _libraryQuery = ''),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
      final albumId = record['albumId'] ?? '';
      final brain = albumId.isNotEmpty ? _libraryBrain[albumId] : null;
      final artist = _canonicalArtistName(
        albumArtist: record['albumArtist'] ?? brain?['artist'] ?? '',
        trackArtist: record['artist'] ?? '',
        albumName: record['albumName'] ?? brain?['displayName'] ?? '',
      );
      if (artist.isEmpty) continue;
      artists.putIfAbsent(artist, () => []);
      artists[artist]!.add(record);
    }

    final artistNames = artists.keys.toList();
    final visibleArtists = artistNames
        .where((artist) =>
            query.isEmpty ||
            artist.toLowerCase().contains(query) ||
            (artists[artist] ?? const <Map<String, String>>[]).any(
                (record) => _artistSearchTextForRecord(record).contains(query)))
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    _cachedLibraryArtistsKey = cacheKey;
    _cachedLibraryArtists = artists;
    _cachedVisibleLibraryArtists = visibleArtists;
    return (grouped: artists, names: visibleArtists);
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
                  _buildLibrarySearchBar(colors, hintText: 'Search artists...'),
                  const SizedBox(height: 12),
                  _buildLibraryModeRow(),
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
                      final artistRecords =
                          List<Map<String, String>>.from(artists[artist] ?? []);
                      final artistAlbums = _albums.where((album) {
                        final albumArtist = _canonicalArtistName(
                          albumArtist: _libraryAlbumArtist(album),
                          trackArtist: _libraryBrain[album['id'] ?? '']
                                  ?['artist'] ??
                              album['artist'] ??
                              '',
                          albumName:
                              album['name'] ?? album['displayName'] ?? '',
                        );
                        return albumArtist.toLowerCase() ==
                            artist.toLowerCase();
                      }).map((album) {
                        final merged = Map<String, String>.from(album);
                        final brain = _libraryBrain[album['id'] ?? ''];
                        if (brain != null) merged.addAll(brain);
                        merged['artist'] = _libraryAlbumArtist(album);
                        merged['displayName'] = _libraryAlbumTitle(album);
                        return merged;
                      }).toList();

                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _ArtistDetailPage(
                            artistName: artist,
                            artistImageUrl: _artistImageCache[
                                    _artistImageCacheKey(artist)] ??
                                '',
                            artistAlbums: artistAlbums,
                            artistTrackRecords: artistRecords,
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
                    behavior: HitTestBehavior.opaque,
                    child: GlassyContainer(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      radius: 20,
                      child: Row(
                        children: [
                          _ArtistAvatar(
                            artistName: artist,
                            imageUrl:
                                _artistImageCache[_artistImageCacheKey(artist)],
                            colors: colors,
                            size: 56,
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

    if (_libraryViewMode == 'liked') {
      final page = _buildSongsView(colors, query, bgColor,
          likedOnly: true,
          title: 'Liked',
          subtitle: 'Songs you have liked.',
          scrollKey: 'library_liked_scroll');
      assert(() {
        debugPrint('Library build (liked): ${stopwatch.elapsedMicroseconds}us');
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
                  _buildLibrarySearchBar(
                    colors,
                    hintText: 'Search Nas, Illmatic, track names...',
                  ),
                  const SizedBox(height: 12),
                  _buildLibraryModeRow(),
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

  Widget _buildLibraryModeRow() {
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
                setState(() => _libraryViewMode = items[i].mode);
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

drive.File _artistTrackFileFromRecord(Map<String, String> record) {
  final modifiedTime = int.tryParse(record['modifiedTime'] ?? '');
  return drive.File()
    ..id = record['id']
    ..name = record['name']
    ..mimeType = record['mimeType']
    ..thumbnailLink = record['thumbnailLink']
    ..size = record['size'] ?? '0'
    ..modifiedTime = modifiedTime != null
        ? DateTime.fromMillisecondsSinceEpoch(modifiedTime)
        : null;
}

int _artistRecordTrackNumber(Map<String, String> record) {
  return int.tryParse(record['trackNumber'] ?? '') ?? 9999;
}

int _artistRecordDiscNumber(Map<String, String> record) {
  return int.tryParse(record['discNumber'] ?? '') ?? 1;
}

List<Map<String, String>> _sortArtistRecords(
    List<Map<String, String>> records) {
  final sorted = List<Map<String, String>>.from(records);
  sorted.sort((a, b) {
    final aAlbum = (a['albumName'] ?? a['album'] ?? '').toLowerCase();
    final bAlbum = (b['albumName'] ?? b['album'] ?? '').toLowerCase();
    final albumCompare = aAlbum.compareTo(bAlbum);
    if (albumCompare != 0) return albumCompare;

    final discCompare =
        _artistRecordDiscNumber(a).compareTo(_artistRecordDiscNumber(b));
    if (discCompare != 0) return discCompare;

    final trackCompare =
        _artistRecordTrackNumber(a).compareTo(_artistRecordTrackNumber(b));
    if (trackCompare != 0) return trackCompare;

    final aTitle = (a['title'] ?? a['name'] ?? '').toLowerCase();
    final bTitle = (b['title'] ?? b['name'] ?? '').toLowerCase();
    return aTitle.compareTo(bTitle);
  });
  return sorted;
}

class _ArtistAvatar extends StatelessWidget {
  final String artistName;
  final String? imageUrl;
  final List<Color> colors;
  final double size;

  const _ArtistAvatar({
    required this.artistName,
    required this.imageUrl,
    required this.colors,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final safe = _safeColors(colors);
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;
    final letter =
        artistName.trim().isNotEmpty ? artistName.trim()[0].toUpperCase() : '?';

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: safe,
          ),
        ),
        child: hasImage
            ? _coverImage(
                imageUrl!,
                fit: BoxFit.cover,
                cacheSize: size <= 64 ? 160 : 320,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    letter,
                    style: GoogleFonts.inter(
                      fontSize: size * 0.42,
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withOpacity(0.58),
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  letter,
                  style: GoogleFonts.inter(
                    fontSize: size * 0.42,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withOpacity(0.58),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ArtistDetailPage extends StatelessWidget {
  final String artistName;
  final String artistImageUrl;
  final List<Map<String, String>> artistAlbums;
  final List<Map<String, String>> artistTrackRecords;
  final bool isDarkMode;
  final List<Color> accentColors;
  final Future<void> Function(Map<String, String> album) onOpenAlbum;
  final Future<void> Function(
    drive.File file, {
    List<drive.File>? queue,
    int? idx,
    String? coverUrl,
    List<Color>? colors,
  }) onPlayTrack;

  const _ArtistDetailPage({
    required this.artistName,
    required this.artistImageUrl,
    required this.artistAlbums,
    required this.artistTrackRecords,
    required this.isDarkMode,
    required this.accentColors,
    required this.onOpenAlbum,
    required this.onPlayTrack,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _safeColors(accentColors);
    final avatarSize = 112.0;
    final tracks = _sortArtistRecords(artistTrackRecords);
    final trackFiles = tracks.map(_artistTrackFileFromRecord).toList();
    final visibleAlbums = artistAlbums.toList()
      ..sort((a, b) {
        final an = (a['displayName'] ?? a['name'] ?? '').toLowerCase();
        final bn = (b['displayName'] ?? b['name'] ?? '').toLowerCase();
        return an.compareTo(bn);
      });

    return Scaffold(
      backgroundColor: isDarkMode ? _darkBg : _lightBg,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: isDarkMode ? Colors.white : _textPri,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Artist',
                        style: GoogleFonts.inter(
                          color: isDarkMode ? Colors.white : _textPri,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              sliver: SliverToBoxAdapter(
                child: GlassyContainer(
                  radius: 26,
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      _ArtistAvatar(
                        artistName: artistName,
                        imageUrl: artistImageUrl,
                        colors: colors,
                        size: avatarSize,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              artistName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: isDarkMode ? Colors.white : _textPri,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${visibleAlbums.length} albums • ${tracks.length} songs',
                              style: GoogleFonts.inter(
                                color: _textSub,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (visibleAlbums.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Albums',
                    style: GoogleFonts.inter(
                      color: isDarkMode ? Colors.white : _textPri,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate((ctx, i) {
                    final album = visibleAlbums[i];
                    return _AlbumGridCard(
                      key: ValueKey(album['id'] ?? album['name']),
                      album: album,
                      onTap: () async {
                        Navigator.of(context).pop();
                        await onOpenAlbum(album);
                      },
                      isDarkMode: isDarkMode,
                    );
                  }, childCount: visibleAlbums.length),
                ),
              ),
            ],
            if (tracks.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Songs',
                    style: GoogleFonts.inter(
                      color: isDarkMode ? Colors.white : _textPri,
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
                    final record = tracks[i];
                    final file = trackFiles[i];
                    final coverUrl = record['albumCover'] ?? '';
                    return _TrackGlassTile(
                      key: ValueKey(record['id']),
                      track: file,
                      queue: trackFiles,
                      index: i,
                      coverUrl: coverUrl,
                      onTap: () {
                        unawaited(onPlayTrack(
                          file,
                          queue: trackFiles,
                          idx: i,
                          coverUrl: coverUrl,
                          colors: colors,
                        ));
                      },
                      isDarkMode: isDarkMode,
                    );
                  }, childCount: tracks.length),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}
