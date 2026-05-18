part of '../../main.dart';

extension _AlbumDetailWidgetsExtension on _MainScreenState {
  Widget _buildAlbumViewFromPart() {
    final album = _resolvedAlbumMap(_viewingAlbum!);
    final albumId = album['id'] ?? '';
    final brain = _libraryBrain[albumId] ?? <String, String>{};
    final albumName = album['displayName'] ?? album['name'] ?? 'Unknown Album';
    final artist = album['artist'] ?? '';
    final year = brain['year'] ?? album['year'] ?? '';
    final genre = brain['genre'] ?? album['genre'] ?? '';
    final coverUrl = album['cover'] ?? brain['cover'] ?? '';
    final colors = _safeColors(_currentDynamicColors);
    final glowColor = _isDarkMode ? _neonPurple : _neonMagenta;
    final fallbackGradient = getAlbumGradient(albumName);
    final albumDetails = [
      if (artist.trim().isNotEmpty) artist.trim(),
      if (year.trim().isNotEmpty) year.trim(),
      if (genre.trim().isNotEmpty) genre.trim(),
    ].join(' â€¢ ');

    // Calculate enhanced metadata from tracks
    String enhancedAlbumInfo = '';
    if (_albumTracks.isNotEmpty) {
      final infoParts = <String>[];

      // Artist from metadata or brain
      String metadataArtist = '';
      for (final track in _albumTracks) {
        final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
        if (meta != null && meta.artist.isNotEmpty) {
          metadataArtist = meta.artist;
          break;
        }
      }
      final displayArtist = metadataArtist.isNotEmpty ? metadataArtist : artist;
      if (displayArtist.trim().isNotEmpty) infoParts.add(displayArtist.trim());

      // Year from metadata or brain
      String metadataYear = '';
      for (final track in _albumTracks) {
        final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
        if (meta != null) {
          if (meta.year != null && meta.year!.length >= 4) {
            final yearMatch = RegExp(r'\d{4}').firstMatch(meta.year!);
            if (yearMatch != null) {
              metadataYear = yearMatch.group(0)!;
              break;
            }
          }
        }
      }
      final displayYear = metadataYear.isNotEmpty ? metadataYear : year;
      if (displayYear.trim().isNotEmpty) infoParts.add(displayYear.trim());

      // Genre from metadata or brain
      String metadataGenre = '';
      for (final track in _albumTracks) {
        final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
        if (meta != null && meta.genre != null && meta.genre!.isNotEmpty) {
          metadataGenre = meta.genre!;
          break;
        }
      }
      final displayGenre = metadataGenre.isNotEmpty ? metadataGenre : genre;
      if (displayGenre.trim().isNotEmpty) infoParts.add(displayGenre.trim());

      // Track count
      final trackCount = _albumTracks.length;
      infoParts.add(trackCount == 1 ? '1 track' : '$trackCount tracks');

      enhancedAlbumInfo = infoParts.join(' â€¢ ');
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          pinned: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _textPri),
            onPressed: _closeAlbum,
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, color: _textPri),
              color: const Color(0xFF1A1A22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              onSelected: (value) {
                if (value == 'load_metadata') {
                  _loadMetadataForCurrentAlbum();
                } else if (value == 'choose_artwork') {
                  _showArtworkSourcePicker();
                } else if (value == 'refresh_cover') {
                  _refreshCurrentAlbumCover();
                } else if (value == 'remove_album') {
                  _removeCurrentAlbumFromLibrary();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'load_metadata',
                  enabled: !_albumMetadataLoading && !_loadingMetadata,
                  child: Row(
                    children: [
                      Icon(Icons.tag_rounded, color: glowColor, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        _albumMetadataLoading
                            ? 'Loading metadata...'
                            : 'Load metadata for album',
                        style: GoogleFonts.inter(
                          color: _textPri,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'choose_artwork',
                  child: Row(
                    children: [
                      Icon(
                        Icons.image_search_rounded,
                        color: glowColor,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Choose artwork source',
                        style: GoogleFonts.inter(
                          color: _textPri,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'remove_album',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Remove from app library',
                        style: GoogleFonts.inter(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () =>
                      _showCoverZoom('album_hero_$albumName', coverUrl, colors),
                  child: Hero(
                    tag: 'album_hero_$albumName',
                    child: Container(
                      width: 154,
                      height: 154,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(kArtworkRadius),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [glowColor, glowColor.withOpacity(0.7)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: glowColor.withOpacity(0.42),
                            blurRadius: 34,
                            offset: const Offset(0, 14),
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
                                cacheSize: _coverLargeDecodeSize,
                                errorBuilder: (_, __, ___) =>
                                    _AlbumFallbackCover(
                                  name: albumName,
                                  colors: fallbackGradient,
                                  radius: kArtworkRadius,
                                ),
                              ),
                            )
                          : _AlbumFallbackCover(
                              name: albumName,
                              colors: fallbackGradient,
                              radius: kArtworkRadius,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  albumName,
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: _isDarkMode ? Colors.white : _neonMagenta,
                    height: 1.04,
                    letterSpacing: -1.0,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  enhancedAlbumInfo.isNotEmpty
                      ? enhancedAlbumInfo
                      : (albumDetails.isNotEmpty
                          ? albumDetails
                          : 'Album â€¢ Drive Library'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: _isDarkMode
                        ? const Color(0xFFFFB6E1).withOpacity(0.9)
                        : Colors.black.withOpacity(0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _AlbumActionButton(
                        icon: Icons.play_arrow_rounded,
                        label: 'Play',
                        accent: _isDarkMode ? Colors.white : _neonMagenta,
                        primary: true,
                        onTap: () => _playCurrentAlbum(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AlbumActionButton(
                        icon: Icons.shuffle_rounded,
                        label: 'Shuffle',
                        accent: _isDarkMode ? Colors.white : _neonMagenta,
                        onTap: () => _playCurrentAlbum(shuffle: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_albumMetadataLoading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: glowColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Loading album metadata $_albumMetadataDone/$_albumMetadataTotal',
                              style: GoogleFonts.inter(
                                color: _textSub,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _albumMetadataTotal > 0
                                ? (_albumMetadataDone / _albumMetadataTotal)
                                    .clamp(0.0, 1.0)
                                : null,
                            minHeight: 4,
                            backgroundColor: Colors.white.withOpacity(0.13),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              glowColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        if (_loadingAlbum)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator(color: _pink)),
          )
        else if (_albumTracks.isEmpty)
          const SliverFillRemaining(
            child: Center(
              child: Text(
                'No tracks found in this album.',
                style: TextStyle(color: _textSub),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((ctx, i) {
                return _TrackGlassTile(
                  key: ValueKey(DriveUtils.effectiveId(_albumTracks[i])),
                  track: _albumTracks[i],
                  queue: _albumTracks,
                  index: i,
                  coverUrl: coverUrl,
                  durationText: _trackDurationLabel(_albumTracks[i]),
                  isLiked: _isTrackLiked(_albumTracks[i]),
                  onTap: () => _playSong(
                    _albumTracks[i],
                    queue: _albumTracks,
                    idx: i,
                    coverUrl: coverUrl,
                    colors: colors,
                  ),
                  onToggleLiked: () => _toggleLikedTrack(_albumTracks[i]),
                  onPlayNext: () => _addTracksPlayNext([_albumTracks[i]]),
                  onAddToQueue: () => _addTracksToQueueEnd([_albumTracks[i]]),
                  isDarkMode: _isDarkMode,
                );
              }, childCount: _albumTracks.length),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 170)),
      ],
    );
  }

  // â”€â”€ Home Tab â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
}
