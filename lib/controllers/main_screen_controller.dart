part of '../main.dart';

extension _MainScreenControllerExtension on _MainScreenState {
  Future<void> _shutdownPlaybackService() async {
    if (_isShuttingDownPlayback) return;
    _isShuttingDownPlayback = true;
    debugPrint('App detached: stopping playback service');

    try {
      if (_infameAudioHandlerInstance != null) {
        await _infameAudioHandlerInstance!.stop();
      } else {
        await _player.stop();
      }
    } catch (e) {
      debugPrint('Player stop failed during shutdown: $e');
    }

    debugPrint('AudioService stopped');

    _audioServicePlayerAttached = false;
    _audioServiceAttachedPlayer = null;
  }

  Future<void> _loadCachedMetadata() async {
    await _metaStore.load();
    final changed = _mergeCachedMetadataDurations();
    if (changed) {
      await _saveKnownTrackDurations();
      if (_libraryTrackIndex.isNotEmpty) {
        await _saveLibraryTrackIndex();
      }
    }
    if (mounted) setState(() {});
  }

  bool _mergeCachedMetadataDurations() {
    var changed = false;
    for (final entry in _metaStore.cachedDurationsMs.entries) {
      if (_knownTrackDurationsMs[entry.key] != entry.value) {
        _setKnownTrackDuration(entry.key, entry.value);
        changed = true;
      }
    }
    return changed;
  }

  Color get _appAccent => _accentColorForMode(_accentMode);

  Future<void> _loadLastPlayed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastPlayedPrefsKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = json.decode(raw);
      if (decoded is! Map) return;

      final data = <String, String>{};
      decoded.forEach((key, value) {
        if (key is String && value != null) {
          data[key] = value.toString();
        }
      });

      if (!mounted) return;
      setState(() => _lastPlayed = data);
    } catch (_) {}
  }

  Future<void> _saveLastPlayed(
    drive.File file, {
    String? coverUrl,
  }) async {
    final fileId = DriveUtils.effectiveId(file);
    if (fileId == null) return;

    final meta = DriveUtils.getTrackMeta(file);
    final safeCoverUrl = _sanitizeCoverSource(coverUrl);
    final existing = _lastPlayed;
    final sameAsExisting = existing?['fileId'] == fileId;
    final data = <String, String>{
      'fileId': fileId,
      'fileName': file.name ?? meta['title'] ?? 'Unknown',
      'title': meta['title'] ?? file.name ?? 'Unknown',
      'artist': meta['artist'] ?? 'Unknown Artist',
      'coverUrl': safeCoverUrl.isNotEmpty
          ? safeCoverUrl
          : (sameAsExisting ? (existing?['coverUrl'] ?? '') : ''),
      'albumId': _viewingAlbum?['id'] ??
          (sameAsExisting ? (existing?['albumId'] ?? '') : ''),
      'albumName': _viewingAlbum?['name'] ??
          (sameAsExisting ? (existing?['albumName'] ?? '') : ''),
      'size': file.size ?? '',
      'modifiedTime': file.modifiedTime?.toIso8601String() ?? '',
    };

    _lastPlayed = data;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPlayedPrefsKey, json.encode(data));
    } catch (_) {}

    if (mounted) setState(() {});
  }

  Future<void> _playLastPlayed() async {
    final data = _lastPlayed;
    if (_user == null || data == null) return;

    final fileId = data['fileId'];
    if (fileId == null || fileId.isEmpty) return;

    try {
      final coverUrl = data['coverUrl'] ?? '';
      final albumName = data['albumName'] ?? '';
      final albumId = data['albumId'] ?? '';

      drive.File track = drive.File()
        ..id = fileId
        ..name = data['fileName'] ?? data['title'] ?? 'Unknown';

      List<drive.File> queue = [track];
      int index = 0;
      Map<String, String>? albumRecord;

      if (albumId.isNotEmpty) {
        albumRecord = _albums.firstWhere(
          (album) => album['id'] == albumId,
          orElse: () => {'id': albumId, 'name': albumName, 'cover': coverUrl},
        );

        final authHeaders = await _user!.authHeaders;
        final api = drive.DriveApi(GoogleAuthClient(authHeaders));
        final tracks = await _fetchTracksForAlbumRecord(api, albumRecord);
        final foundIndex =
            tracks.indexWhere((item) => DriveUtils.effectiveId(item) == fileId);

        if (tracks.isNotEmpty && foundIndex >= 0) {
          queue = tracks;
          index = foundIndex;
          track = tracks[foundIndex];
        }
      }

      await _playSong(
        track,
        queue: queue,
        idx: index,
        coverUrl: coverUrl.isNotEmpty ? coverUrl : albumRecord?['cover'],
        colors: getAlbumGradient(
            albumName.isNotEmpty ? albumName : (data['title'] ?? 'Infame')),
      );
    } catch (e) {
      _showError('Could not continue last song: $e');
    }
  }

  Future<void> _loadUiPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      glassModeNotifier.value = _glassMode;
      await _loadFailedCoverSources();
      final savedThemeMode = prefs.getString(_themeModePrefsKey);
      if (savedThemeMode != null) {
        final nextDarkMode = savedThemeMode != 'light';
        if (mounted && _isDarkMode != nextDarkMode) {
          setState(() => _isDarkMode = nextDarkMode);
        } else {
          _isDarkMode = nextDarkMode;
        }
      }

      final colorsRaw = prefs.getString(_albumColorPrefsKey);
      if (colorsRaw != null && colorsRaw.isNotEmpty) {
        try {
          final decodedColors = json.decode(colorsRaw);
          if (decodedColors is Map) {
            _albumColorCache.clear();
            decodedColors.forEach((key, value) {
              if (key is String && value is List) {
                final parsed = value
                    .map((item) => _colorFromHex(item.toString()))
                    .whereType<Color>()
                    .toList();
                if (parsed.length >= 4) {
                  _albumColorCache[key] = parsed.take(4).toList();
                }
              }
            });
          }
        } catch (_) {}
      }

      final raw = prefs.getString(_uiPrefsKey);
      if (raw == null || raw.isEmpty) return;

      final data = json.decode(raw);
      if (data is! Map) return;

      if (!mounted) return;
      setState(() {
        _showBackgroundGlow = data['showBackgroundGlow'] != false;
        _homeShowContinue = data['homeShowContinue'] != false;
        _homeShowGenres = data['homeShowGenres'] != false;
        _homeShowDecades = data['homeShowDecades'] != false;
        _homeShowArtists = data['homeShowArtists'] != false;
        _homeShowDiscovery = data['homeShowDiscovery'] != false;
        final savedGlassMode =
            (data['glassMode'] ?? _glassModeBalanced).toString();
        _glassMode = _isValidGlassMode(savedGlassMode)
            ? savedGlassMode
            : _glassModeBalanced;
        glassModeNotifier.value = _glassMode;

        final savedAccentMode =
            (data['accentMode'] ?? _accentModeChampagne).toString();
        _accentMode = _isValidAccentMode(savedAccentMode)
            ? savedAccentMode
            : _accentModeChampagne;

        final savedLibraryViewMode =
            (data['libraryViewMode'] ?? 'albums').toString();
        _libraryViewMode = (savedLibraryViewMode == 'albums' ||
                savedLibraryViewMode == 'songs' ||
                savedLibraryViewMode == 'artists' ||
                savedLibraryViewMode == 'liked')
            ? savedLibraryViewMode
            : 'albums';
      });
    } catch (_) {}
  }

  Future<void> _saveUiPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _themeModePrefsKey,
      _isDarkMode ? 'dark' : 'light',
    );
    await prefs.setString(
      _uiPrefsKey,
      json.encode({
        'showBackgroundGlow': _showBackgroundGlow,
        'glassMode': _glassMode,
        'homeShowContinue': _homeShowContinue,
        'homeShowGenres': _homeShowGenres,
        'homeShowDecades': _homeShowDecades,
        'homeShowArtists': _homeShowArtists,
        'homeShowDiscovery': _homeShowDiscovery,
        'accentMode': _accentMode,
        'libraryViewMode': _libraryViewMode,
      }),
    );
  }

  Future<void> _loadLikedTracks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final liked =
          prefs.getStringList(_likedTracksPrefsKey) ?? const <String>[];
      final nextLiked = <String>{};
      for (final key in liked) {
        final trimmed = key.trim();
        if (trimmed.isNotEmpty) nextLiked.add(trimmed);
      }
      _likedTrackKeys = nextLiked;
      _likedTracksVersion++;
      _invalidateLibraryBrowseCache();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveLikedTracks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final liked = _likedTrackKeys.toList()..sort();
      await prefs.setStringList(_likedTracksPrefsKey, liked);
    } catch (_) {}
  }
}
