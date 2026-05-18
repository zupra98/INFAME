part of '../main.dart';

extension _ArtworkServiceExtension on _MainScreenState {
  Future<String?> _downloadArtworkToLocalCache(
    Map<String, String> album,
    _ArtworkCandidate candidate,
  ) async {
    final res = await http.get(Uri.parse(candidate.imageUrl),
        headers: {'User-Agent': 'InfameApp/1.0'});
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    final type = res.headers['content-type']?.toLowerCase() ?? '';
    if (type.isNotEmpty && !type.startsWith('image/')) return null;
    if (res.bodyBytes.length > 12 * 1024 * 1024) return null;

    final dir = await getApplicationSupportDirectory();
    final artworkDir = Directory('${dir.path}/infame/artwork');
    if (!await artworkDir.exists()) await artworkDir.create(recursive: true);
    final key = _safeArtworkFileName(_albumStableKey(album));
    final source = _safeArtworkFileName(candidate.source);
    final ext = _imageExtensionFromHeaders(res, candidate.imageUrl);
    final path = '${artworkDir.path}/${key}_$source$ext';
    final file = File(path);
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return path;
  }

  Future<void> _applyArtworkOverrideToAlbum(
    Map<String, String> album,
    String coverPath, {
    String source = 'Custom',
    String remoteUrl = '',
  }) async {
    final albumId = album['id'] ?? '';
    final currentCover = _albumCoverForIndex(album);
    if ((album['driveCover'] ?? '').isEmpty &&
        currentCover.isNotEmpty &&
        currentCover != coverPath) {
      album['driveCover'] = currentCover;
    }

    void apply(Map<String, String> target) {
      if ((target['driveCover'] ?? '').isEmpty &&
          currentCover.isNotEmpty &&
          currentCover != coverPath) {
        target['driveCover'] = currentCover;
      }
      target['cover'] = coverPath;
      target['customCoverUrl'] = coverPath;
      target['artworkSource'] = source;
      if (remoteUrl.isNotEmpty) target['artworkRemoteUrl'] = remoteUrl;
      target['artworkUpdatedAt'] =
          DateTime.now().millisecondsSinceEpoch.toString();
    }

    apply(album);
    for (final savedAlbum in _albums) {
      if ((savedAlbum['id'] ?? '') == albumId) {
        apply(savedAlbum);
        break;
      }
    }
    if (_viewingAlbum != null && (_viewingAlbum!['id'] ?? '') == albumId) {
      apply(_viewingAlbum!);
    }

    final brain = _libraryBrain[albumId];
    if (brain != null) {
      brain['cover'] = coverPath;
      await _saveLibraryBrain();
    }

    for (final record in _libraryTrackIndex.values) {
      if ((record['albumId'] ?? '') == albumId) {
        record['albumCover'] = coverPath;
      }
    }

    if (albumId.isNotEmpty && _currentPlayingAlbumId() == albumId) {
      _nowPlaying.currentCoverUrl = coverPath;
      _nowPlaying.refresh();
    }

    _librarySearchTextCache.clear();
    await _persistAlbums();
    await _saveLibraryTrackIndex();
    await _extractAlbumColors(coverPath, _albumTitleForArtwork(album));
    _invalidateHomeBrowseCache();
    _invalidateLibraryBrowseCache();
    if (mounted) setState(() {});
  }

  Future<void> _revertAlbumArtwork(Map<String, String> album) async {
    final albumId = _albumCacheKey(album, source: 'revert_artwork');
    final fallback = album['driveCover'] ??
        album['coverUrl'] ??
        album['thumbnailLink'] ??
        album['artwork'] ??
        '';

    void revert(Map<String, String> target) {
      target.remove('customCoverUrl');
      target.remove('artworkSource');
      target.remove('artworkRemoteUrl');
      target.remove('artworkUpdatedAt');
      target['cover'] = fallback;
    }

    revert(album);
    for (final savedAlbum in _albums) {
      if (_albumCacheKey(savedAlbum, source: 'revert_artwork_saved') ==
              albumId ||
          (savedAlbum['id'] ?? '') == albumId) {
        revert(savedAlbum);
        break;
      }
    }
    if (_viewingAlbum != null &&
        (_albumCacheKey(_viewingAlbum!, source: 'revert_artwork_view') ==
                albumId ||
            (_viewingAlbum!['id'] ?? '') == albumId)) {
      revert(_viewingAlbum!);
    }

    final brain = _libraryBrain[albumId];
    if (brain != null) {
      brain['cover'] = fallback;
      await _saveLibraryBrain();
    }
    for (final record in _libraryTrackIndex.values) {
      if ((record['albumId'] ?? '') == albumId) {
        record['albumCover'] = fallback;
      }
    }
    _librarySearchTextCache.clear();
    await _persistAlbums();
    await _saveLibraryTrackIndex();
    _invalidateHomeBrowseCache();
    _invalidateLibraryBrowseCache();
    if (mounted) setState(() {});
  }

  Future<List<_ArtworkCandidate>> _searchArtworkSource(
    String source,
    String albumName,
    String artistName,
    String year,
  ) async {
    switch (source) {
      case 'itunes':
        return _searchITunesArtworkCandidates(albumName, artistName, year);
      case 'audiodb':
        return _searchTheAudioDbArtworkCandidates(albumName, artistName, year);
      case 'musicbrainz':
        return _searchMusicBrainzArtworkCandidates(albumName, artistName, year);
      default:
        return const <_ArtworkCandidate>[];
    }
  }

  Future<void> _showArtworkSourcePicker() async {
    final album = _viewingAlbum;
    if (album == null) return;

    final albumName = _albumTitleForArtwork(album);
    final artistName = _albumArtistForArtwork(album);
    final year = _albumYearForArtwork(album);
    final currentCover = _albumCoverForIndex(album);
    final glowColor = _isDarkMode ? _neonPurple : _neonMagenta;
    var candidates = <_ArtworkCandidate>[];
    var loading = false;
    var status = 'Choose a source to search artwork.';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            Future<void> runSource(String source) async {
              sheetSetState(() {
                loading = true;
                candidates = <_ArtworkCandidate>[];
                status = 'Searching artwork...';
              });
              try {
                final results = await _searchArtworkSource(
                    source, albumName, artistName, year);
                sheetSetState(() {
                  candidates = results;
                  status = results.isEmpty
                      ? 'No artwork found for this source.'
                      : 'Tap the correct cover to save it locally.';
                });
              } catch (e) {
                sheetSetState(() => status = 'Could not search artwork: $e');
              } finally {
                sheetSetState(() => loading = false);
              }
            }

            Future<void> pickCandidate(_ArtworkCandidate candidate) async {
              sheetSetState(() {
                loading = true;
                status = 'Saving artwork locally...';
              });
              try {
                final localPath =
                    await _downloadArtworkToLocalCache(album, candidate);
                if (localPath == null || localPath.isEmpty) {
                  sheetSetState(() => status = 'Could not download artwork.');
                  return;
                }
                await _applyArtworkOverrideToAlbum(
                  album,
                  localPath,
                  source: candidate.source,
                  remoteUrl: candidate.imageUrl,
                );
                if (mounted) Navigator.of(sheetContext).pop();
                _showSuccess('Artwork updated.');
              } catch (e) {
                sheetSetState(() => status = 'Could not save artwork: $e');
              } finally {
                sheetSetState(() => loading = false);
              }
            }

            Widget sourceButton(
                String label, IconData icon, VoidCallback onTap) {
              return Expanded(
                child: PressableScale(
                  onTap: loading ? null : onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 10),
                    decoration: BoxDecoration(
                      color: (_isDarkMode
                          ? Colors.white.withOpacity(0.08)
                          : Colors.white),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: glowColor.withOpacity(0.35)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: glowColor, size: 20),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                              color: _textPri,
                              fontWeight: FontWeight.w800,
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Container(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88),
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 14,
                bottom: MediaQuery.of(context).padding.bottom + 18,
              ),
              decoration: BoxDecoration(
                color: _isDarkMode
                    ? const Color(0xFF121018)
                    : const Color(0xFFFFFBFF),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: glowColor.withOpacity(0.28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _textSub.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Choose Artwork Source',
                      style: GoogleFonts.inter(
                          color: _textPri,
                          fontSize: 22,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('$artistName â€¢ $albumName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          color: _textSub, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (currentCover.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(kArtworkRadius),
                          child: SizedBox(
                              width: 58,
                              height: 58,
                              child: _coverImage(currentCover, cacheSize: 160)),
                        )
                      else
                        Container(
                            width: 58,
                            height: 58,
                            color: glowColor.withOpacity(0.14),
                            child: Icon(Icons.album_rounded, color: glowColor)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          status,
                          style: GoogleFonts.inter(
                              color: _textSub, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      sourceButton('iTunes', Icons.music_note_rounded,
                          () => runSource('itunes')),
                      const SizedBox(width: 10),
                      sourceButton('TheAudioDB', Icons.storage_rounded,
                          () => runSource('audiodb')),
                      const SizedBox(width: 10),
                      sourceButton('MusicBrainz', Icons.public_rounded,
                          () => runSource('musicbrainz')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      sourceButton('Current', Icons.image_rounded, () async {
                        await _revertAlbumArtwork(album);
                        if (mounted) Navigator.of(sheetContext).pop();
                        _showSuccess('Using current cover.');
                      }),
                      const SizedBox(width: 10),
                      sourceButton('Revert', Icons.undo_rounded, () async {
                        await _revertAlbumArtwork(album);
                        if (mounted) Navigator.of(sheetContext).pop();
                        _showSuccess('Artwork reverted.');
                      }),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (loading)
                    LinearProgressIndicator(
                        color: glowColor,
                        backgroundColor: glowColor.withOpacity(0.12)),
                  if (!loading && candidates.isNotEmpty)
                    Flexible(
                      child: GridView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(top: 10),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final candidate = candidates[index];
                          return GestureDetector(
                            onTap: () => pickCandidate(candidate),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(kArtworkRadius),
                                    child: Container(
                                      color: glowColor.withOpacity(0.10),
                                      child: _coverImage(
                                        candidate.thumbnailUrl.isNotEmpty
                                            ? candidate.thumbnailUrl
                                            : candidate.imageUrl,
                                        cacheSize: 260,
                                        errorBuilder: (_, __, ___) => Center(
                                            child: Icon(
                                                Icons.broken_image_rounded,
                                                color: glowColor)),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  candidate.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      color: _textPri,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11),
                                ),
                                Text(
                                  [
                                    candidate.source,
                                    if (candidate.year.isNotEmpty)
                                      candidate.year
                                  ].join(' â€¢ '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      color: _textSub,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _refreshCurrentAlbumCover() async {
    final album = _viewingAlbum;
    if (album == null) return;

    final normalized = _resolvedAlbumMap(album);
    final albumId = normalized['id'] ?? '';
    final brain = _libraryBrain[albumId] ?? const <String, String>{};
    final albumName =
        normalized['displayName'] ?? normalized['name'] ?? 'Unknown Album';
    final artist = normalized['artist'] ?? 'Unknown Artist';

    _showSuccess('Checking embedded cover first...');

    final embedded = await _findEmbeddedCoverForAlbum(album);
    if (embedded != null && embedded.isNotEmpty) {
      setState(() {
        album['cover'] = embedded;
        for (final savedAlbum in _albums) {
          if (_albumCacheKey(savedAlbum, source: 'show_artwork_saved') ==
                  albumId ||
              savedAlbum['id'] == album['id']) {
            savedAlbum['cover'] = embedded;
            break;
          }
        }
      });
      await _persistAlbums();
      await _extractAlbumColors(embedded, albumName);
      _showSuccess('Embedded album cover restored.');
      return;
    }

    _showSuccess('Searching Cover Art Archive...');
    final fetched = await _fetchCoverArt(albumName, artist);
    if (fetched == null || fetched.isEmpty) {
      _showError(
          'No cover found. Embedded art was missing and online lookup failed.');
      return;
    }

    setState(() {
      album['cover'] = fetched;
      for (final savedAlbum in _albums) {
        if (_albumCacheKey(savedAlbum, source: 'show_artwork_saved') ==
                albumId ||
            savedAlbum['id'] == album['id']) {
          savedAlbum['cover'] = fetched;
          break;
        }
      }
    });

    await _persistAlbums();
    await _extractAlbumColors(fetched, albumName);
    _showSuccess('Album cover refreshed.');
  }
}
