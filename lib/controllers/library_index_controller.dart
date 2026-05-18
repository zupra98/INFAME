part of '../main.dart';

extension _LibraryIndexControllerExtension on _MainScreenState {
  Future<bool> _mergeKnownTrackDurationsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_knownTrackDurationsKey);
      if (raw == null || raw.isEmpty) return false;

      final decoded = json.decode(raw);
      if (decoded is! Map) return false;

      var changed = false;
      decoded.forEach((key, value) {
        if (key is! String) return;
        final durationMs = _validDurationMsFromValue(value);
        if (durationMs == null) return;

        if (_knownTrackDurationsMs[key] != durationMs ||
            _libraryTrackIndex[key]?['durationMs'] != durationMs.toString()) {
          changed = true;
        }
        _setKnownTrackDuration(key, durationMs);
      });

      return changed;
    } catch (_) {
      return false;
    }
  }

  String _albumCoverForIndex(Map<String, String> album) {
    final key = _albumCacheKey(album, source: 'album_cover_index');
    final direct = _sanitizeCoverSource(
      album['cover'] ??
          album['customCoverUrl'] ??
          album['coverUrl'] ??
          album['thumbnailLink'] ??
          album['artwork'] ??
          _libraryBrain[key]?['cover'] ??
          '',
    );
    if (direct.isNotEmpty) return direct;
    final tracks = _tracksForAlbumKey(key);
    for (final track in tracks) {
      final cached = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      final cover = _sanitizeCoverSource(cached?.coverPath);
      if (cover.isNotEmpty) return cover;
    }
    return '';
  }

  String _albumStableKey(Map<String, String> album) {
    final id = _albumCacheKey(album, source: 'album_stable');
    if (id.isNotEmpty) return id;
    final artist = (album['artist'] ?? '').trim().toLowerCase();
    final name =
        (album['displayName'] ?? album['name'] ?? '').trim().toLowerCase();
    return '$artist::$name'.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  String _safeArtworkFileName(String value) {
    final cleaned = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return cleaned
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '')
        .trim();
  }

  String _imageExtensionFromHeaders(http.Response response, String url) {
    final type = response.headers['content-type']?.toLowerCase() ?? '';
    if (type.contains('png')) return '.png';
    if (type.contains('webp')) return '.webp';
    if (type.contains('jpeg') || type.contains('jpg')) return '.jpg';
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('.png')) return '.png';
    if (lowerUrl.contains('.webp')) return '.webp';
    return '.jpg';
  }

  bool _repairLibraryTrackIndexFromAlbums() {
    if (_libraryTrackIndex.isEmpty || _albums.isEmpty) return false;

    final albumsById = <String, Map<String, String>>{};
    for (final album in _albums) {
      final id = album['id'] ?? '';
      if (id.isNotEmpty) albumsById[id] = album;
    }

    var changed = false;
    for (final entry in _libraryTrackIndex.entries) {
      final record = entry.value;
      final albumId = record['albumId'] ?? '';
      final album = albumsById[albumId];
      if (album != null) {
        final albumCover = _albumCoverForIndex(album);
        if (albumCover.isNotEmpty && record['albumCover'] != albumCover) {
          record['albumCover'] = albumCover;
          changed = true;
        }
      }

      final durationMs = _knownTrackDurationsMs[entry.key];
      if (durationMs != null &&
          durationMs > 0 &&
          durationMs < 86400000 &&
          record['durationMs'] != durationMs.toString()) {
        record['durationMs'] = durationMs.toString();
        changed = true;
      }
    }

    return changed;
  }

  bool _applyAlbumCoverFromMetadataScan(
    String albumId,
    String coverPath, {
    bool persistChanges = true,
    bool refreshUi = true,
  }) {
    if (albumId.trim().isEmpty || coverPath.trim().isEmpty) return false;

    var changed = false;
    for (final album in _albums) {
      if ((album['id'] ?? '') == albumId && album['cover'] != coverPath) {
        album['cover'] = coverPath;
        changed = true;
        break;
      }
    }

    if (_viewingAlbum != null && (_viewingAlbum!['id'] ?? '') == albumId) {
      if (_viewingAlbum!['cover'] != coverPath) {
        _viewingAlbum!['cover'] = coverPath;
        changed = true;
      }
    }

    final brain = _libraryBrain[albumId];
    if (brain != null && brain['cover'] != coverPath) {
      brain['cover'] = coverPath;
      changed = true;
      if (persistChanges) _saveLibraryBrain();
    }

    for (final record in _libraryTrackIndex.values) {
      if ((record['albumId'] ?? '') == albumId &&
          record['albumCover'] != coverPath) {
        record['albumCover'] = coverPath;
        changed = true;
      }
    }

    if (changed && persistChanges) {
      _librarySearchTextCache.clear();
      _persistAlbums();
      _saveLibraryTrackIndex();
      _invalidateHomeBrowseCache();
      _invalidateLibraryBrowseCache();
      if (refreshUi && mounted) setState(() {});
    }

    return changed;
  }

  void _queueAlbumCoverFromMetadataScan(String albumId, String coverPath) {
    final normalizedId =
        _albumCacheKey(albumId, source: 'metadata_cover_found');
    if (normalizedId.trim().isEmpty || coverPath.trim().isEmpty) return;
    _pendingAlbumCoverUpdates[normalizedId] = coverPath;
    _pendingAlbumCoverFlushTimer ??=
        Timer(const Duration(milliseconds: 500), _flushPendingAlbumCovers);
  }

  void _flushPendingAlbumCovers() {
    _pendingAlbumCoverFlushTimer?.cancel();
    _pendingAlbumCoverFlushTimer = null;
    if (_pendingAlbumCoverUpdates.isEmpty) return;

    final pending = Map<String, String>.from(_pendingAlbumCoverUpdates);
    _pendingAlbumCoverUpdates.clear();

    var changed = false;
    for (final entry in pending.entries) {
      if (_applyAlbumCoverFromMetadataScan(
        entry.key,
        entry.value,
        persistChanges: false,
        refreshUi: false,
      )) {
        changed = true;
      }
    }

    if (changed) {
      _librarySearchTextCache.clear();
      _saveLibraryBrain();
      _persistAlbums();
      _saveLibraryTrackIndex();
      _invalidateHomeBrowseCache();
      _invalidateLibraryBrowseCache();
      _nowPlaying.refresh();
      debugPrint('UI refresh after cover scan');
      if (mounted) setState(() {});
    }
  }

  Future<void> _syncForegroundMetadataResults() async {
    if (_syncingForegroundMetadataResults) return;
    _syncingForegroundMetadataResults = true;

    try {
      await _mergeKnownTrackDurationsFromPrefs();
      await _metaStore.reload();
      await _loadAlbums();

      final repaired = _repairLibraryTrackIndexFromAlbums();
      if (repaired) await _saveLibraryTrackIndex();

      await _saveKnownTrackDurations();

      if (!mounted) return;
      _librarySearchTextCache.clear();
      _nowPlaying.refresh();
      setState(() {});
    } finally {
      _syncingForegroundMetadataResults = false;
    }
  }

  String _formatDurationMs(int ms) => _formatDurationMsFromPart(ms);

  Future<Duration?> _getDurationWithTemporaryPlayer(
      drive.File file, String token) async {
    final fileId = DriveUtils.effectiveId(file);
    if (fileId == null) return null;

    // Check if we already have duration in cache
    final cachedMs = _knownTrackDurationsMs[fileId];
    if (cachedMs != null && cachedMs > 0) {
      return Duration(milliseconds: cachedMs);
    }

    // Use temporary AudioPlayer to get duration
    final tempPlayer = AudioPlayer();
    try {
      final source = DriveAudioSource(
        fileId,
        token,
        knownSourceLength: int.tryParse(file.size ?? ''),
      );

      Duration? duration = await tempPlayer
          .setAudioSource(source)
          .timeout(const Duration(seconds: 10), onTimeout: () => null);

      duration ??= await tempPlayer.durationStream
          .firstWhere((value) => value != null)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      final durationMs = _validDurationMsFromValue(duration?.inMilliseconds);
      if (durationMs != null) {
        return Duration(milliseconds: durationMs);
      }
    } catch (e) {
      // Continue on error
      return null;
    } finally {
      await tempPlayer.dispose();
    }

    return null;
  }

  Future<void> _clearLibraryTrackIndex() async {
    _libraryTrackIndex.clear();
    await _saveLibraryTrackIndex();
    _invalidateLibraryBrowseCache();
  }

  Future<void> _buildLibraryTrackIndex() async {
    if (_user == null || _albums.isEmpty) {
      _showError('Sign in and add albums first.');
      return;
    }

    setState(() {
      _loadingSaved = true;
    });

    try {
      final headers = await _user!.authHeaders;
      final api = drive.DriveApi(GoogleAuthClient(headers));
      final newIndex = <String, Map<String, String>>{};

      for (final album in _albums) {
        if (!mounted) return;

        try {
          final tracks = await _fetchTracksForAlbumRecord(api, album);
          final sortedTracks = _sortTracksForAlbum(tracks);

          _albumTracksCache[album['id'] ?? ''] = sortedTracks;

          for (final track in sortedTracks) {
            final trackId = DriveUtils.effectiveId(track);
            if (trackId == null || trackId.isEmpty) continue;

            final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
            final trackMeta = DriveUtils.getTrackMeta(track);

            final albumCover = _albumCoverForIndex(album);

            final durationMs = _knownTrackDurationsMs[trackId] ??
                _validDurationMsFromValue(
                    _libraryTrackIndex[trackId]?['durationMs']) ??
                _validDurationMsFromValue(meta?.durationMs) ??
                _validDurationMsFromValue(trackMeta['durationMs']);
            if (durationMs != null) _setKnownTrackDuration(trackId, durationMs);

            final record = <String, String>{
              'id': trackId,
              'name': track.name ?? '',
              'albumId': album['id'] ?? '',
              'albumName': (meta?.album?.trim().isNotEmpty == true)
                  ? meta!.album!.trim()
                  : (album['displayName'] ?? album['name'] ?? ''),
              'albumArtist': _canonicalArtistName(
                albumArtist: album['artist'],
                trackArtist:
                    meta?.artist ?? trackMeta['artist']?.toString() ?? '',
                albumName: (meta?.album?.trim().isNotEmpty == true)
                    ? meta!.album!.trim()
                    : (album['displayName'] ?? album['name'] ?? ''),
              ),
              'albumCover': albumCover,
              'mimeType': track.mimeType ?? '',
              'thumbnailLink': track.thumbnailLink ?? '',
              'size': track.size ?? '0',
              'modifiedTime':
                  track.modifiedTime?.millisecondsSinceEpoch.toString() ?? '',
              if (durationMs != null && durationMs > 0)
                'durationMs': durationMs.toString(),
            };

            if (meta != null) {
              final metaMap = meta.toMap();
              record['title'] = metaMap['title'] ?? '';
              record['artist'] = metaMap['artist'] ?? '';
              record['album'] = metaMap['album'] ?? '';
              record['year'] = metaMap['year'] ?? '';
              record['genre'] = metaMap['genre'] ?? '';
              record['trackNumber'] = metaMap['trackNumber'] ?? '';
              record['discNumber'] = metaMap['discNumber'] ?? '';
            } else {
              record['title'] =
                  trackMeta['title']?.toString() ?? track.name ?? '';
              record['artist'] = trackMeta['artist']?.toString() ?? '';
              record['album'] = album['displayName'] ?? album['name'] ?? '';
              record['year'] = trackMeta['year']?.toString() ?? '';
              record['genre'] = trackMeta['genre']?.toString() ?? '';
              record['trackNumber'] =
                  trackMeta['trackNumber']?.toString() ?? '';
              record['discNumber'] = trackMeta['discNumber']?.toString() ?? '';
            }

            newIndex[trackId] = record;
          }
        } catch (e) {
          // Continue even if one album fails
          continue;
        }
      }

      // Replace the index at the end
      _libraryTrackIndex.clear();
      _libraryTrackIndex.addAll(newIndex);
      await _saveLibraryTrackIndex();
      _invalidateLibraryBrowseCache();
      _queueArtistImagePrefetch();

      if (!mounted) return;

      setState(() {
        _loadingSaved = false;
      });

      _showSuccess('Song index built successfully.');
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingSaved = false;
        });
        _showError('Failed to build song index: $e');
      }
    }
  }

  drive.File _fileFromTrackIndexRecord(Map<String, String> record) {
    final modifiedTime = int.tryParse(record['modifiedTime'] ?? '');
    final file = drive.File()
      ..id = record['id']
      ..name = record['name']
      ..mimeType = record['mimeType']
      ..thumbnailLink = record['thumbnailLink']
      ..size = record['size'] ?? '0'
      ..modifiedTime = modifiedTime != null
          ? DateTime.fromMillisecondsSinceEpoch(modifiedTime)
          : null;

    final source = (record['source'] ?? '').trim();
    final localPath = (record['localPath'] ?? '').trim();
    final localUri = (record['localUri'] ?? '').trim();
    if (source.isNotEmpty || localPath.isNotEmpty || localUri.isNotEmpty) {
      file.appProperties = <String, String>{
        if (source.isNotEmpty) 'source': source,
        if (localPath.isNotEmpty) 'path': localPath,
        if (localUri.isNotEmpty) 'localUri': localUri,
      };
      file.properties = Map<String, String>.from(file.appProperties!);
    }

    return file;
  }
}
