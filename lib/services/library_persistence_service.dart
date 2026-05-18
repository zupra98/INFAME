part of '../main.dart';

extension _LibraryPersistenceServiceExtension on _MainScreenState {
  Future<void> _loadAlbums() async {
    setState(() => _loadingSaved = true);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_albumsPrefsKey);
    final now = DateTime.now().millisecondsSinceEpoch.toString();

    if (!mounted) return;

    var changed = false;
    final loadedAlbums = raw != null
        ? List<Map<String, String>>.from(
            (json.decode(raw) as List).map((e) => Map<String, String>.from(e)),
          )
        : <Map<String, String>>[];

    for (final album in loadedAlbums) {
      final normalizedId = _albumCacheKey(album, source: 'load_album');
      if (normalizedId.isNotEmpty) {
        album['id'] = normalizedId;
        album['albumKey'] = normalizedId;
      }
      if ((album['dateAdded'] ?? '').isEmpty) {
        album['dateAdded'] = now;
        changed = true;
      }
    }

    setState(() {
      _albums = loadedAlbums;
      _librarySearchTextCache.clear();
      _shuffledExploreAlbums = (List<Map<String, String>>.from(loadedAlbums)
            ..shuffle())
          .take(14)
          .toList();
      _loadingSaved = false;
    });

    _invalidateHomeBrowseCache();
    _invalidateLibraryBrowseCache();
    _buildBasicLibraryBrain(save: true);
    final repairedIndex = _repairLibraryTrackIndexFromAlbums();
    if (repairedIndex) await _saveLibraryTrackIndex();
    if (_albums.any(_isLocalAlbumRecord)) {
      _rebuildLocalAlbumTrackCacheFromIndex(log: true);
    }
    if (changed) await _persistAlbums();
    _logStartupSourceState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _precacheAlbumCovers(limit: 36);
    });
  }

  void _precacheAlbumCovers({int limit = 36}) {
    final candidates = _albums
        .map((album) => album['cover'] ?? '')
        .where((cover) => cover.isNotEmpty)
        .where((cover) => _isLocalCover(cover))
        .take(limit);

    for (final cover in candidates) {
      final provider = _coverProvider(cover);
      if (provider != null) {
        precacheImage(provider, context).catchError((_) {});
      }
    }
  }

  Future<void> _persistAlbums() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_albumsPrefsKey, json.encode(_albums));
  }

  String _audioExtension(drive.File file) {
    final name = file.name ?? 'track.mp3';
    final dot = name.lastIndexOf('.');
    if (dot == -1) return '.mp3';
    return name.substring(dot).toLowerCase();
  }

  String _safeCacheName(String id) {
    return id
        .replaceAll('/', '_')
        .replaceAll(':', '_')
        .replaceAll('?', '_')
        .replaceAll('&', '_')
        .replaceAll('=', '_');
  }

  Future<File> _downloadTrackToTemp(
      String fileId, String token, String extension) async {
    final dir = await getTemporaryDirectory();
    final unique = DateTime.now().microsecondsSinceEpoch;
    final path =
        '${dir.path}/musix_meta_${_safeCacheName(fileId)}_$unique$extension';
    final tempFile = File(path);

    final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
    final client = http.Client();

    try {
      final request = http.Request('GET', uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'User-Agent': 'InfameApp/1.0',
        })
        ..followRedirects = false;

      final response = await client.send(request);
      http.StreamedResponse finalResponse = response;

      if (response.isRedirect && response.headers.containsKey('location')) {
        final redirectUri = Uri.parse(response.headers['location']!);
        final secondRequest = http.Request('GET', redirectUri);
        finalResponse = await client.send(secondRequest);
      }

      if (finalResponse.statusCode != 200 && finalResponse.statusCode != 206) {
        throw Exception(
            'Could not download metadata file: ${finalResponse.statusCode}');
      }

      final sink = tempFile.openWrite();
      await finalResponse.stream.pipe(sink);
      return tempFile;
    } finally {
      client.close();
    }
  }

  String _coverExtensionFromBytes(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return '.png';
    }

    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return '.jpg';
    }

    if (bytes.length >= 12 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return '.webp';
    }

    return '.jpg';
  }

  Future<String?> _saveEmbeddedCover(drive.File file, Uint8List bytes) async {
    final fileId = DriveUtils.effectiveId(file);
    if (fileId == null || bytes.isEmpty) return null;

    try {
      _pendingAlbumCoverFlushTimer?.cancel();
      _pendingAlbumCoverFlushTimer = null;
      _pendingAlbumCoverUpdates.clear();

      final dir = await getApplicationDocumentsDirectory();
      final coverDir = Directory('${dir.path}/musix_embedded_covers');
      if (!await coverDir.exists()) {
        await coverDir.create(recursive: true);
      }

      final ext = _coverExtensionFromBytes(bytes);
      final path = '${coverDir.path}/${_safeCacheName(fileId)}$ext';
      final out = File(path);
      await out.writeAsBytes(bytes, flush: true);
      return 'file://$path';
    } catch (_) {
      return null;
    }
  }

  void _applyEmbeddedCoverToAlbum(
    drive.File file,
    String coverPath, {
    Map<String, String>? albumRecord,
  }) {
    final fileId = DriveUtils.effectiveId(file);
    final safeCoverPath = _sanitizeCoverSource(coverPath);
    if (safeCoverPath.isEmpty) return;
    bool changed = false;

    void applyToAlbum(Map<String, String> album) {
      album['cover'] = safeCoverPath;
      changed = true;
    }

    if (albumRecord != null) {
      final albumId = _albumCacheKey(albumRecord, source: 'apply_cover');
      for (final album in _albums) {
        if (_albumCacheKey(album, source: 'apply_cover_saved') == albumId ||
            album['id'] == albumId) {
          applyToAlbum(album);
          break;
        }
      }

      if (_viewingAlbum != null &&
          (_albumCacheKey(_viewingAlbum!, source: 'apply_cover_view') ==
                  albumId ||
              _viewingAlbum!['id'] == albumId)) {
        _viewingAlbum!['cover'] = safeCoverPath;
        changed = true;
      }
    } else if (_viewingAlbum != null && fileId != null) {
      final inCurrentAlbum =
          _albumTracks.any((track) => DriveUtils.effectiveId(track) == fileId);
      if (inCurrentAlbum) {
        _viewingAlbum!['cover'] = safeCoverPath;
        for (final album in _albums) {
          if (album['id'] == _viewingAlbum!['id']) {
            album['cover'] = safeCoverPath;
            break;
          }
        }
        changed = true;
      }
    }

    if (_nowPlaying.track != null && fileId != null) {
      final activeId = DriveUtils.effectiveId(_nowPlaying.track!);
      if (activeId == fileId) {
        _nowPlaying.currentCoverUrl = safeCoverPath;
        _nowPlaying.refresh();
      }
    }

    if (changed) {
      final albumIdForCover = albumRecord?['id'] ?? _viewingAlbum?['id'] ?? '';
      final normalizedAlbumId = _albumCacheKey(
        albumRecord ?? _viewingAlbum ?? <String, String>{},
        source: 'apply_cover_record',
      );
      if (albumIdForCover.isNotEmpty) {
        for (final record in _libraryTrackIndex.values) {
          if ((record['albumId'] ?? '') == albumIdForCover ||
              (record['albumId'] ?? '') == normalizedAlbumId) {
            record['albumCover'] = safeCoverPath;
          }
        }
        _saveLibraryTrackIndex();
      }
      _persistAlbums();
      debugPrint('UI refresh after cover scan');
      if (mounted) setState(() {});
    }
  }
}
