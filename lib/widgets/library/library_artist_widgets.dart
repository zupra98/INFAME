part of '../../main.dart';

extension _LibraryArtistWidgetsExtension on _MainScreenState {
  Widget _buildArtistsViewFromPart(
    List<Color> colors,
    String query,
    Color bgColor,
  ) {
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
                          child: _buildGradientText(
                            'Artists',
                            size: 34,
                            spacing: -1.4,
                          ),
                        ),
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
                    _buildLibrarySearchBar(
                      colors,
                      hintText: 'Search artists...',
                    ),
                    const SizedBox(height: 12),
                    _buildLibraryModeRow(),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _LibraryInfoChip(
                          label: '${visibleArtists.length} artists',
                          accent: colors[1],
                        ),
                        _LibraryInfoChip(
                          label: '${artists.length} total',
                          accent: colors[2],
                        ),
                        if (_libraryQuery.trim().isNotEmpty)
                          GestureDetector(
                            onTap: () =>
                                _librarySetState(() => _libraryQuery = ''),
                            child: _LibraryInfoChip(
                              label: 'Clear search Ãƒâ€”',
                              accent: _pink,
                            ),
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
                          color: _textPri,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Indexed songs: ${_libraryTrackIndex.length}',
                        style: GoogleFonts.inter(
                          color: _textSub,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Albums in library: ${_albums.length}',
                        style: GoogleFonts.inter(
                          color: _textSub,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Open albums or run Library metadata scan to build the song list.',
                        style: GoogleFonts.inter(
                          color: _textSub,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _buildLibraryTrackIndex,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors[1],
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: Text(
                          'Build Song Index',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                        ),
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
                          color: _textPri,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () =>
                            _librarySetState(() => _libraryQuery = ''),
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

                    return FadeSlideIn(
                      key: ValueKey('artist-$artist'),
                      child: PressableScale(
                        onTap: () {
                          final artistRecords = List<Map<String, String>>.from(
                            artists[artist] ?? [],
                          );
                          final artistAlbums = _albums.where((album) {
                            final resolved = _resolvedAlbumMap(album);
                            final albumArtist = _canonicalArtistName(
                              albumArtist: _libraryAlbumArtist(resolved),
                              trackArtist: _libraryBrain[resolved['id'] ?? '']
                                      ?['artist'] ??
                                  resolved['artist'] ??
                                  '',
                              albumName: resolved['name'] ??
                                  resolved['displayName'] ??
                                  '',
                            );
                            return albumArtist.toLowerCase() ==
                                artist.toLowerCase();
                          }).map((album) {
                            final resolved = _resolvedAlbumMap(album);
                            final merged = Map<String, String>.from(
                              resolved,
                            );
                            final brain = _libraryBrain[resolved['id'] ?? ''];
                            if (brain != null) merged.addAll(brain);
                            merged['artist'] = _libraryAlbumArtist(
                              resolved,
                            );
                            merged['displayName'] = _libraryAlbumTitle(
                              resolved,
                            );
                            return merged;
                          }).toList();

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
                                      '$songCount songs Ã¢â‚¬Â¢ $albumCount albums',
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
            const SliverToBoxAdapter(child: SizedBox(height: 170)),
          ],
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
  List<Map<String, String>> records,
) {
  final sorted = List<Map<String, String>>.from(records);
  sorted.sort((a, b) {
    final aAlbum = (a['albumName'] ?? a['album'] ?? '').toLowerCase();
    final bAlbum = (b['albumName'] ?? b['album'] ?? '').toLowerCase();
    final albumCompare = aAlbum.compareTo(bAlbum);
    if (albumCompare != 0) return albumCompare;

    final discCompare = _artistRecordDiscNumber(
      a,
    ).compareTo(_artistRecordDiscNumber(b));
    if (discCompare != 0) return discCompare;

    final trackCompare = _artistRecordTrackNumber(
      a,
    ).compareTo(_artistRecordTrackNumber(b));
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
                              '${visibleAlbums.length} albums â€¢ ${tracks.length} songs',
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
                        unawaited(
                          onPlayTrack(
                            file,
                            queue: trackFiles,
                            idx: i,
                            coverUrl: coverUrl,
                            colors: colors,
                          ),
                        );
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
