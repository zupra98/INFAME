part of '../../main.dart';

extension _LibraryAlbumWidgetsExtension on _MainScreenState {
  Widget buildLibraryTabFromPart() {
    final stopwatch = Stopwatch()..start();
    final colors = _safeColors(_currentDynamicColors);
    final query = _libraryQuery.trim().toLowerCase();
    final bgColor = _isDarkMode ? _darkBg : _lightBg;

    if (_libraryViewMode == 'songs') {
      final page = _buildSongsView(colors, query, bgColor);
      assert(() {
        _verboseUiLog(
          'Library build (songs): ${stopwatch.elapsedMicroseconds}us',
        );
        return true;
      }());
      return page;
    }

    if (_libraryViewMode == 'liked') {
      final page = _buildLikedViewFromPart(colors, query, bgColor);
      assert(() {
        _verboseUiLog(
          'Library build (liked): ${stopwatch.elapsedMicroseconds}us',
        );
        return true;
      }());
      return page;
    }

    if (_libraryViewMode == 'artists') {
      final page = _buildArtistsView(colors, query, bgColor);
      assert(() {
        _verboseUiLog(
          'Library build (artists): ${stopwatch.elapsedMicroseconds}us',
        );
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
                          child: _buildGradientText(
                            'Crates',
                            size: 34,
                            spacing: -1.4,
                          ),
                        ),
                        IconButton(
                          tooltip: _libraryGridMode ? 'List view' : 'Grid view',
                          icon: Icon(
                            _libraryGridMode
                                ? Icons.view_list_rounded
                                : Icons.grid_view_rounded,
                            color: _textSub,
                          ),
                          onPressed: () => _librarySetState(
                            () => _libraryGridMode = !_libraryGridMode,
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Sort library',
                          icon: const Icon(Icons.sort_rounded, color: _textSub),
                          color: const Color(0xFF1A1A22),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          onSelected: (value) =>
                              _librarySetState(() => _librarySortMode = value),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'az',
                              child: Text(
                                'Album Aâ€“Z',
                                style: GoogleFonts.inter(color: _textPri),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'za',
                              child: Text(
                                'Album Zâ€“A',
                                style: GoogleFonts.inter(color: _textPri),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'artist',
                              child: Text(
                                'Artist Aâ€“Z',
                                style: GoogleFonts.inter(color: _textPri),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Search albums, artists, songs, years â€” all in one place.',
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
                          accent: colors[1],
                        ),
                        _LibraryInfoChip(
                          label: '${_visibleArtistCount()} artists',
                          accent: colors[2],
                        ),
                        _LibraryInfoChip(
                          label: '${_metaStore.count} tagged tracks',
                          accent: colors[0],
                        ),
                        if (_libraryQuery.trim().isNotEmpty)
                          GestureDetector(
                            onTap: () =>
                                _librarySetState(() => _libraryQuery = ''),
                            child: _LibraryInfoChip(
                              label: 'Clear search Ã—',
                              accent: _pink,
                            ),
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
                  child: CircularProgressIndicator(color: _accentDefault),
                ),
              )
            else if (_albums.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    'Library is empty.',
                    style: TextStyle(color: _textSub),
                  ),
                ),
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
                    final album = _resolvedAlbumMap(visibleAlbums[i]);
                    final merged = Map<String, String>.from(album);
                    final brain = _libraryBrain[album['id'] ?? ''];
                    if (brain != null) merged.addAll(brain);
                    final folderGuess = _artistAlbumFromFolder(
                      album['name'] ?? '',
                    );
                    merged['artist'] = _libraryAlbumArtist(album);
                    merged['displayName'] = _libraryAlbumTitle(album);
                    if ((merged['artist'] ?? '').isEmpty &&
                        folderGuess['artist'] != null) {
                      merged['artist'] = folderGuess['artist']!;
                    }
                    return FadeSlideIn(
                      key: ValueKey(
                        'library-grid-${album['id'] ?? album['name']}',
                      ),
                      child: _AlbumGridCard(
                        key: ValueKey(album['id'] ?? album['name']),
                        album: merged,
                        onTap: () => _openAlbum(album),
                        isDarkMode: _isDarkMode,
                      ),
                    );
                  }, childCount: visibleAlbums.length),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((ctx, i) {
                    final album = _resolvedAlbumMap(visibleAlbums[i]);
                    final brain = _libraryBrain[album['id'] ?? ''];
                    final name = _libraryAlbumTitle(album);
                    final artist = _libraryAlbumArtist(album);
                    final year = brain?['year'] ?? album['year'] ?? '';
                    final genre = brain?['genre'] ?? album['genre'] ?? '';
                    final coverUrl = album['cover'] ?? brain?['cover'] ?? '';
                    final gradient = getAlbumGradient(name);

                    return FadeSlideIn(
                      key: ValueKey(
                        'library-list-${album['id'] ?? album['name']}',
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
                  }, childCount: visibleAlbums.length),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 170)),
          ],
        ),
      ),
    );
    assert(() {
      _verboseUiLog(
        'Library build (albums): ${stopwatch.elapsedMicroseconds}us',
      );
      return true;
    }());
    return page;
  }
}
