part of '../main.dart';

extension _MetadataLibraryServiceExtension on _MainScreenState {
  Future<void> _loadMetadataForEntireLibrary() async {
    if (_user == null || _albums.isEmpty || _loadingMetadata) return;

    setState(() {
      _loadingMetadata = true;
      _metadataDone = 0;
      _metadataTotal = 0;
    });

    try {
      final authHeaders = await _user!.authHeaders;
      final bearer =
          authHeaders['Authorization'] ?? authHeaders['authorization'] ?? '';
      if (!bearer.startsWith('Bearer ')) {
        throw Exception('Could not get Google token.');
      }

      final token = bearer.substring(7);
      final api = drive.DriveApi(GoogleAuthClient(authHeaders));
      final Map<String, drive.File> uniqueTracks = {};
      final Map<String, Map<String, String>> trackAlbums = {};

      for (final album in _albums) {
        if (!mounted) return;
        final tracks = await _fetchTracksForAlbumRecord(api, album);
        _albumTracksCache[album['id'] ?? ''] = _sortTracksForAlbum(tracks);

        for (final track in tracks) {
          final id = DriveUtils.effectiveId(track);
          if (id != null) {
            uniqueTracks[id] = track;
            trackAlbums[id] = album;
          }
        }
      }

      int freshCacheHits = 0;
      int missingCount = 0;
      int changedCount = 0;
      final missing = uniqueTracks.values.where((track) {
        final fresh = _metaStore.peekFresh(track);
        final trackId = DriveUtils.effectiveId(track);
        final hasDuration = trackId != null &&
            (_validDurationMsFromValue(
                      _knownTrackDurationsMs[trackId] ??
                          _libraryTrackIndex[trackId]?['durationMs'],
                    ) !=
                    null ||
                _validDurationMsFromValue(fresh?.durationMs) != null);
        if (fresh != null && hasDuration) {
          freshCacheHits++;
          return false;
        }
        if (_metaStore.peek(track) == null) {
          missingCount++;
        } else {
          changedCount++;
        }
        return true;
      }).toList()
        ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

      _verboseScanLog(
        'MetadataScan fresh cache hits=$freshCacheHits missing=$missingCount changed=$changedCount',
      );
      _verboseScanLog('MetadataScan skipped unchanged=$freshCacheHits');

      if (!mounted) return;

      if (missing.isEmpty) {
        for (final album in _albums) {
          final albumId = album['id'] ?? '';
          final cachedTracks = _albumTracksCache[albumId];
          if (cachedTracks != null) {
            _indexAlbumFromTracks(album, cachedTracks, save: false);
            _indexTracksForAlbum(album, cachedTracks);
          }
        }
        await _saveLibraryBrain();
        await _saveLibraryTrackIndex();
        await _persistAlbums();
        _invalidateHomeBrowseCache();
        _invalidateLibraryBrowseCache();
        setState(() => _loadingMetadata = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Metadata is already loaded and album display was refreshed.',
              style: GoogleFonts.inter(
                  color: Colors.black, fontWeight: FontWeight.w800),
            ),
            backgroundColor: _accentDefault,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      setState(() {
        _metadataTotal = missing.length;
        _metadataDone = 0;
      });
      _updateMetadataProgressUi(force: true);

      final client = http.Client();
      final controller = _ScanConcurrencyController(
        initialConcurrency: 6,
        maxConcurrency: 8,
      );
      int tracksProcessed = 0;

      try {
        await _runWithConcurrency<drive.File>(
          missing,
          controller,
          (track, index) async {
            if (!mounted) return;
            final id = DriveUtils.effectiveId(track);
            await _loadMetadataFor(
              track,
              token,
              albumRecord: id == null ? null : trackAlbums[id],
              textOnly: true,
              persistImmediately: false,
              refreshUi: false,
              client: client,
            );
            if (mounted) {
              _metadataDone++;
              _updateMetadataProgressUi();
            }
            tracksProcessed++;
            if (tracksProcessed % 100 == 0) {
              await _metaStore.persistNow();
              await _saveLibraryTrackIndex();
            }
          },
        );
      } finally {
        client.close();
      }

      if (!mounted) return;

      setState(() => _loadingMetadata = false);
      _updateMetadataProgressUi(force: true);
      await _persistAlbums();

      // Final save of metadata and library index
      await _metaStore.persistNow();

      for (final album in _albums) {
        final albumId = album['id'] ?? '';
        final cachedTracks = _albumTracksCache[albumId];
        if (cachedTracks != null) {
          _indexAlbumFromTracks(album, cachedTracks, save: false);
          _indexTracksForAlbum(album, cachedTracks);
        }
      }
      await _saveLibraryBrain();
      await _saveLibraryTrackIndex();
      _invalidateHomeBrowseCache();
      _invalidateLibraryBrowseCache();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Metadata loaded and cached for ' +
                missing.length.toString() +
                ' library tracks.',
            style: GoogleFonts.inter(
                color: Colors.black, fontWeight: FontWeight.w800),
          ),
          backgroundColor: _accentDefault,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMetadata = false);
        _updateMetadataProgressUi(force: true);
        _showError('Library metadata load failed: ' + e.toString());
      }
    }
  }

  Future<void> _backupLibraryCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_albumsBackupPrefsKey, json.encode(_albums));
  }

  Future<void> _restoreLibraryBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_albumsBackupPrefsKey);

    if (raw == null || raw.isEmpty) {
      _showError('No library backup found yet.');
      return;
    }

    try {
      final restored = List<Map<String, String>>.from(
        (json.decode(raw) as List).map((e) => Map<String, String>.from(e)),
      );

      setState(() {
        _albums = restored
          ..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
        _librarySearchTextCache.clear();
        _shuffledExploreAlbums = (List<Map<String, String>>.from(restored)
              ..shuffle())
            .take(14)
            .toList();
        _viewingAlbum = null;
        _albumTracks = [];
      });

      _buildBasicLibraryBrain(save: false);
      await _persistAlbums();
      await _saveLibraryBrain();
      _showSuccess('Previous library restored.');
    } catch (e) {
      _showError('Could not restore library backup: $e');
    }
  }

  Future<bool> _confirmDangerAction({
    required String title,
    required String body,
    required String confirmText,
  }) async {
    final controller = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF181820),
          surfaceTintColor: Colors.transparent,
          title: Text(
            title,
            style:
                GoogleFonts.inter(color: _textPri, fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                body,
                style: GoogleFonts.inter(
                    color: _textSub, height: 1.45, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Text(
                'Type $confirmText to continue.',
                style: GoogleFonts.inter(
                    color: _textPri, fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                style: GoogleFonts.inter(
                    color: _textPri, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  hintText: confirmText,
                  hintStyle:
                      GoogleFonts.inter(color: _textSub.withOpacity(0.6)),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.12)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.12)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _accentDefault),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Cancel',
                  style: GoogleFonts.inter(
                      color: _textSub, fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                    dialogContext, controller.text.trim() == confirmText);
              },
              child: Text('Confirm',
                  style: GoogleFonts.inter(
                      color: _accentDefault, fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result == true;
  }

  Future<void> _clearLibraryCacheSafely() async {
    if (_albums.isEmpty) {
      _showSuccess('Library cache is already empty.');
      return;
    }

    final confirmed = await _confirmDangerAction(
      title: 'Clear app library cache?',
      body:
          'This does NOT delete anything from Google Drive. It only removes the albums saved inside Infame. A backup will be saved first so you can restore it from Settings.',
      confirmText: 'CLEAR',
    );

    if (!confirmed) return;

    await _backupLibraryCache();

    setState(() {
      _albums.clear();
      _viewingAlbum = null;
      _albumTracks.clear();
      _albumTracksCache.clear();
      _libraryBrain.clear();
      _libraryTrackIndex.clear();
      _playHistory.clear();
      _currentDynamicColors = List<Color>.from(_defaultDynamicColors);
    });

    await _persistAlbums();
    await _saveLibraryBrain();
    await _saveLibraryTrackIndex();
    await _savePlayHistory();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Library cache cleared. Your Drive files are untouched.',
          style: GoogleFonts.inter(
              color: Colors.black, fontWeight: FontWeight.w900),
        ),
        backgroundColor: _accentDefault,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'RESTORE',
          textColor: Colors.black,
          onPressed: _restoreLibraryBackup,
        ),
      ),
    );
  }

  Future<void> _clearMetadataCacheSafely() async {
    final confirmed = await _confirmDangerAction(
      title: 'Clear metadata cache?',
      body:
          'Song titles, artists, album metadata and cached scan results will be removed. Your Drive music files stay untouched.',
      confirmText: 'CLEAR',
    );

    if (!confirmed) return;

    await _metaStore.clear();
    _librarySearchTextCache.clear();
    for (final album in _albums) {
      album.remove('displayName');
      album.remove('artist');
      album.remove('year');
      album.remove('genre');
      album.remove('trackCount');
    }
    _libraryBrain.clear();
    _buildBasicLibraryBrain(save: false);
    await _persistAlbums();
    await _saveLibraryBrain();
    _nowPlaying.refresh();
    if (mounted) setState(() {});
    _showSuccess('Metadata cache cleared.');
  }

  Future<void> _clearCoverCacheSafely() async {
    final confirmed = await _confirmDangerAction(
      title: 'Clear embedded cover cache?',
      body:
          'This removes locally saved embedded album covers. Your Drive files stay untouched, and covers can be regenerated by scanning metadata again.',
      confirmText: 'CLEAR',
    );

    if (!confirmed) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final coverDir = Directory('${dir.path}/musix_embedded_covers');
      if (await coverDir.exists()) {
        await coverDir.delete(recursive: true);
      }

      for (final album in _albums) {
        if (_isLocalCover(album['cover'])) {
          album['cover'] = '';
        }
        album.remove(_embeddedCoverScanFingerprintKey);
        final albumId = album['id'] ?? '';
        if (albumId.isNotEmpty) {
          _libraryBrain[albumId]?.remove(_embeddedCoverScanFingerprintKey);
          for (final record in _libraryTrackIndex.values) {
            if ((record['albumId'] ?? '') == albumId &&
                _isLocalCover(record['albumCover'])) {
              record['albumCover'] = '';
            }
          }
        }
      }
      _failedCoverSources.clear();
      await _saveFailedCoverSources();

      await _persistAlbums();
      await _saveLibraryBrain();
      await _saveLibraryTrackIndex();
      _invalidateHomeBrowseCache();
      _invalidateLibraryBrowseCache();
      if (mounted) setState(() {});
      _showSuccess('Cover cache cleared.');
    } catch (e) {
      _showError('Could not clear cover cache: $e');
    }
  }

  Future<void> _removeCurrentAlbumFromLibrary() async {
    final album = _viewingAlbum;
    if (album == null) return;

    final confirmed = await _confirmDangerAction(
      title: 'Remove album from Infame?',
      body:
          'This only removes the album from the app library cache. It does not delete the folder or songs from Google Drive.',
      confirmText: 'REMOVE',
    );

    if (!confirmed) return;

    await _backupLibraryCache();
    final id = album['id'];

    setState(() {
      _albums.removeWhere((a) => a['id'] == id);
      if (id != null) _libraryBrain.remove(id);
      _playHistory.removeWhere((item) => item['albumId'] == id);
      _viewingAlbum = null;
      _albumTracks = [];
      _currentDynamicColors = List<Color>.from(_defaultDynamicColors);
    });

    await _persistAlbums();
    await _saveLibraryBrain();
    await _savePlayHistory();
    _showSuccess('Album removed from app library. Drive files are untouched.');
  }
}
