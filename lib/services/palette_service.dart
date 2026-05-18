part of '../main.dart';

extension _PaletteServiceExtension on _MainScreenState {
  Future<void> _extractAlbumColors(
    String coverUrl,
    String albumName, {
    String? cacheKey,
  }) async {
    final fallback = getAlbumGradient(albumName);
    final key =
        cacheKey?.trim().isNotEmpty == true ? cacheKey!.trim() : albumName;

    final cached = _albumColorCache[key];
    if (cached != null && cached.length >= 4) {
      if (mounted) setState(() => _currentDynamicColors = cached);
      return;
    }

    if (coverUrl.isEmpty) {
      _albumColorCache[key] = fallback;
      _saveAlbumColorCache();
      if (mounted) setState(() => _currentDynamicColors = fallback);
      return;
    }

    if (_isBlockedCoverSource(coverUrl)) {
      _albumColorCache[key] = fallback;
      _saveAlbumColorCache();
      if (mounted) setState(() => _currentDynamicColors = fallback);
      return;
    }

    // Prevent duplicate extractions for the same cover
    if (_albumColorExtractionInProgress.contains(key)) {
      debugPrint('Palette extraction already in progress for $key, skipping');
      return;
    }

    _albumColorExtractionInProgress.add(key);

    try {
      final provider = _coverProvider(coverUrl);
      if (provider == null) throw Exception('Missing cover provider');

      // Resize image to 300x300 for faster palette extraction
      final paletteProvider = ResizeImage(
        provider,
        width: 300,
        height: 300,
      );

      final stopwatch = Stopwatch()..start();

      // Sample resized image for color extraction (much faster than full image)
      final palette = await PaletteGenerator.fromImageProvider(
        paletteProvider,
        maximumColorCount: 24,
        region: null, // Full resized image sampling
      );

      stopwatch.stop();
      debugPrint(
          'Palette extraction took ${stopwatch.elapsedMilliseconds}ms for $key');

      // Sort by combination of population (70%) and saturation (30%)
      final hsl = HSLColor.fromColor;
      final sortedColors = List<PaletteColor>.from(palette.paletteColors)
        ..sort((a, b) {
          final aScore =
              (a.population * 0.7) + (hsl(a.color).saturation * 1000 * 0.3);
          final bScore =
              (b.population * 0.7) + (hsl(b.color).saturation * 1000 * 0.3);
          return bScore.compareTo(aScore);
        });

      // Boost saturation by 15% for more vibrant colors
      Color boostSaturation(Color color) {
        final hslColor = hsl(color);
        return hslColor
            .withSaturation(
              (hslColor.saturation + 0.15).clamp(0.0, 1.0),
            )
            .toColor();
      }

      // Calculate average brightness to detect dark/muted palettes
      double calculateBrightness(List<Color> colors) {
        final brightness = colors.map((c) {
          final hsl = HSLColor.fromColor(c);
          return hsl.lightness;
        }).reduce((a, b) => a + b);
        return brightness / colors.length;
      }

      // Select top vibrant colors
      Color pickByScore(int index, Color fallbackColor) {
        if (sortedColors.length > index)
          return boostSaturation(sortedColors[index].color);
        return boostSaturation(fallbackColor);
      }

      final dominant = pickByScore(
        0,
        palette.dominantColor?.color ?? fallback[0],
      );

      // Get top 4-5 colors with saturation boost
      final extractedRaw = [
        dominant,
        pickByScore(1, palette.vibrantColor?.color ?? fallback[1]),
        pickByScore(2, palette.lightVibrantColor?.color ?? fallback[2]),
        pickByScore(3, palette.darkMutedColor?.color ?? fallback[3]),
        pickByScore(4, palette.lightMutedColor?.color ?? fallback[3]),
      ];

      // Check if colors are too dark/muted (average brightness < 0.25)
      final avgBrightness = calculateBrightness(extractedRaw);
      List<Color> extracted;

      if (avgBrightness < 0.25) {
        // Fallback: Use dominant color with gradient variations
        final base = palette.dominantColor?.color ?? fallback[0];
        extracted = [
          base,
          HSLColor.fromColor(base).withLightness(0.35).toColor(),
          HSLColor.fromColor(base).withLightness(0.25).toColor(),
          HSLColor.fromColor(base).withLightness(0.15).toColor(),
        ];
      } else {
        // Ensure at least one warm color if present in palette
        final hasWarmColor = sortedColors.any((c) {
          final hsl = HSLColor.fromColor(c.color);
          return hsl.hue >= 0 && hsl.hue <= 60 || hsl.hue >= 330;
        });

        if (hasWarmColor) {
          // Find and prioritize warm color
          final warmColor = sortedColors.firstWhere(
            (c) {
              final hsl = HSLColor.fromColor(c.color);
              return hsl.hue >= 0 && hsl.hue <= 60 || hsl.hue >= 330;
            },
            orElse: () => sortedColors[0],
          );
          extracted = [
            boostSaturation(warmColor.color),
            extractedRaw[0],
            extractedRaw[1],
            extractedRaw[2],
          ];
        } else {
          extracted = extractedRaw.take(4).toList();
        }
      }

      _albumColorCache[key] = extracted;
      _saveAlbumColorCache();

      if (!mounted) return;
      setState(() => _currentDynamicColors = extracted);
    } catch (_) {
      _albumColorCache[key] = fallback;
      _saveAlbumColorCache();
      if (mounted) setState(() => _currentDynamicColors = fallback);
    } finally {
      _albumColorExtractionInProgress.remove(key);
    }
  }

  // â”€â”€ Album View Logic â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _openAlbum(Map<String, String> album) async {
    final normalizedAlbum = _resolvedAlbumMap(album);
    final albumId = _albumCacheKey(normalizedAlbum, source: 'open_album');
    final albumName =
        normalizedAlbum['displayName'] ?? album['name'] ?? 'Unknown Album';
    final cachedTracks = _albumTracksCache[albumId];
    final sortedCachedTracks = cachedTracks == null || cachedTracks.isEmpty
        ? null
        : _sortTracksForAlbum(cachedTracks);
    final cachedColors = _albumColorCache[albumId];
    final isLocalAlbum = _isLocalAlbumRecord(normalizedAlbum);
    final localIndexTracks = isLocalAlbum
        ? _sortTracksForAlbum(_localTracksForAlbumFromIndex(normalizedAlbum))
        : <drive.File>[];
    final localFallbackTracks = isLocalAlbum
        ? (localIndexTracks.isNotEmpty
            ? localIndexTracks
            : _sortTracksForAlbum(_localTracksForAlbum(normalizedAlbum)))
        : <drive.File>[];

    debugPrint(
        'AlbumOpen requested albumKey=$albumId cacheCount=${cachedTracks?.length ?? 0} indexCount=${isLocalAlbum ? localIndexTracks.length : 0} fallbackCount=${localFallbackTracks.length}');

    setState(() {
      _viewingAlbum = normalizedAlbum;
      _loadingAlbum = sortedCachedTracks == null &&
          (!isLocalAlbum || localFallbackTracks.isEmpty);
      _albumTracks = sortedCachedTracks ??
          (isLocalAlbum ? localFallbackTracks : <drive.File>[]);
      _albumMetadataLoading = false;
      _albumMetadataDone = 0;
      _albumMetadataTotal = 0;
      _currentDynamicColors = cachedColors ?? getAlbumGradient(albumName);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _extractAlbumColors(
        normalizedAlbum['cover'] ?? '',
        albumName,
        cacheKey: albumId,
      );
    });

    if (sortedCachedTracks != null) {
      _applyFirstCachedEmbeddedCover(normalizedAlbum, sortedCachedTracks);
      _indexAlbumFromTracks(normalizedAlbum, sortedCachedTracks);
      _indexTracksForAlbum(normalizedAlbum, sortedCachedTracks);
      unawaited(
          _hydrateAlbumDurationsInBackground(albumId, sortedCachedTracks));
      return;
    }

    try {
      List<drive.File> tracks;
      if (isLocalAlbum) {
        tracks = localFallbackTracks.isNotEmpty
            ? localFallbackTracks
            : _sortTracksForAlbum(_localTracksForAlbum(normalizedAlbum));
      } else {
        if (_user == null) {
          throw Exception('Sign in to load Drive albums.');
        }
        final headers = await _user!.authHeaders;
        final api = drive.DriveApi(GoogleAuthClient(headers));
        tracks =
            _sortTracksForAlbum(await _fetchTracksForAlbumRecord(api, album));
      }

      if (!mounted) return;

      _albumTracksCache[albumId] = tracks;
      if (isLocalAlbum && tracks.isEmpty) {
        debugPrint(
          'DataIntegrityWarning local album opened with zero restored tracks key=$albumId title=${normalizedAlbum['displayName'] ?? normalizedAlbum['name'] ?? ''} artist=${normalizedAlbum['artist'] ?? ''}',
        );
      }
      _applyFirstCachedEmbeddedCover(normalizedAlbum, tracks);
      _indexAlbumFromTracks(normalizedAlbum, tracks, save: false);
      _indexTracksForAlbum(normalizedAlbum, tracks);
      _saveLibraryBrain();
      _persistAlbums();

      setState(() {
        _albumTracks = tracks;
        _loadingAlbum = false;
      });
      unawaited(_hydrateAlbumDurationsInBackground(albumId, tracks));

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _precacheTrackArtwork(normalizedAlbum['cover'] ?? '');
      });
    } catch (e) {
      _showError('Failed to load album: $e');
      if (mounted) setState(() => _loadingAlbum = false);
    }
  }

  void _applyFirstCachedEmbeddedCover(
      Map<String, String> album, List<drive.File> tracks) {
    String? cachedEmbeddedCover;
    for (final track in tracks) {
      final cached = _metaStore.peek(track);
      if (cached?.coverPath != null && cached!.coverPath!.isNotEmpty) {
        cachedEmbeddedCover = cached.coverPath;
        break;
      }
    }

    if (cachedEmbeddedCover == null) return;

    bool changed = album['cover'] != cachedEmbeddedCover;
    album['cover'] = cachedEmbeddedCover;

    for (final savedAlbum in _albums) {
      if (savedAlbum['id'] == album['id']) {
        if (savedAlbum['cover'] != cachedEmbeddedCover) {
          savedAlbum['cover'] = cachedEmbeddedCover;
          changed = true;
        }
        break;
      }
    }

    if (changed) {
      _persistAlbums();
      if (mounted) setState(() {});
    }
  }

  void _precacheTrackArtwork(String coverUrl) {
    if (coverUrl.isEmpty || !_isLocalCover(coverUrl)) return;
    final provider = _coverProvider(coverUrl);
    if (provider != null) {
      precacheImage(provider, context).catchError((_) {});
    }
  }

  Future<void> _hydrateAlbumDurationsInBackground(
    String albumId,
    List<drive.File> tracks,
  ) async {
    final normalizedAlbumId = albumId.trim();
    if (normalizedAlbumId.isEmpty || tracks.isEmpty) return;
    if (_hydratingAlbumDurations.contains(normalizedAlbumId) ||
        _hydratedAlbumDurations.contains(normalizedAlbumId)) {
      return;
    }
    _hydratingAlbumDurations.add(normalizedAlbumId);

    var filled = 0;
    var stillMissing = 0;

    final missingTracks = <drive.File>[];
    for (final track in tracks) {
      if (_durationMsForTrack(track) == null) {
        missingTracks.add(track);
      }
    }
    _verboseScanLog(
        'AlbumDurationHydration start album=$normalizedAlbumId missing=${missingTracks.length}');

    try {
      // First pass: hydrate from already cached metadata/index only.
      var quickChanged = false;
      for (final track in missingTracks) {
        final trackId = DriveUtils.effectiveId(track);
        if (trackId == null || trackId.isEmpty) continue;

        final durationMs = _durationMsForTrack(track);
        if (durationMs == null) continue;

        _storeDurationForTrackId(
          trackId,
          durationMs,
          persist: false,
          refreshVisibleAlbum: false,
        );
        quickChanged = true;
        filled++;
        _verboseScanLog(
            'AlbumDurationHydration cached track=$trackId durationMs=$durationMs');
      }

      if (quickChanged) {
        await _saveKnownTrackDurations();
        await _saveLibraryTrackIndex();
        _invalidateLibraryBrowseCache();
        if (mounted && _viewingAlbum?['id'] == normalizedAlbumId) {
          setState(() {});
        }
      }

      // Second pass: best-effort backfill for truly missing Drive durations.
      // Local files are parsed at import time and should not try to use Drive auth.
      final driveMissingTracks = missingTracks
          .where((track) => !DriveUtils.isLocalFile(track))
          .toList(growable: false);
      if (driveMissingTracks.isEmpty || _user == null) {
        stillMissing =
            missingTracks.where((t) => _durationMsForTrack(t) == null).length;
        return;
      }

      final headers = await _user!.authHeaders;
      final bearer = headers['Authorization'] ?? headers['authorization'] ?? '';
      if (!bearer.startsWith('Bearer ')) return;
      final token = bearer.substring(7);

      var changed = false;
      var batchedUiUpdates = 0;
      final client = http.Client();
      try {
        for (final track in driveMissingTracks) {
          final trackId = DriveUtils.effectiveId(track);
          if (trackId == null || trackId.isEmpty) continue;

          final existing = _durationMsForTrack(track);
          if (existing != null) continue;

          final fastResult = await FastTagReader.read(
            file: track,
            token: token,
            readCover: false,
            client: client,
          );
          final durationMs =
              _validDurationMsFromValue(fastResult?.duration?.inMilliseconds);
          if (durationMs == null) continue;

          _storeDurationForTrackId(
            trackId,
            durationMs,
            persist: false,
            refreshVisibleAlbum: false,
          );
          changed = true;
          filled++;
          batchedUiUpdates++;
          _verboseScanLog(
              'AlbumDurationHydration cached track=$trackId durationMs=$durationMs');

          if (batchedUiUpdates >= 6 &&
              mounted &&
              _viewingAlbum?['id'] == normalizedAlbumId) {
            batchedUiUpdates = 0;
            setState(() {});
          }
        }
      } finally {
        client.close();
      }

      if (changed) {
        await _saveKnownTrackDurations();
        await _saveLibraryTrackIndex();
        _invalidateLibraryBrowseCache();
        if (mounted && _viewingAlbum?['id'] == normalizedAlbumId) {
          setState(() {});
        }
      }
      stillMissing = tracks.where((t) => _durationMsForTrack(t) == null).length;
    } catch (_) {
      // Best effort only.
    } finally {
      _hydratingAlbumDurations.remove(normalizedAlbumId);
      _hydratedAlbumDurations.add(normalizedAlbumId);
      _verboseScanLog(
          'AlbumDurationHydration complete album=$normalizedAlbumId filled=$filled stillMissing=$stillMissing');
    }
  }

  void _closeAlbum() {
    setState(() {
      _viewingAlbum = null;
      _albumTracks = [];
      _currentDynamicColors = List<Color>.from(_defaultDynamicColors);
    });
  }

  Future<List<drive.File>> _fetchTracksForAlbumRecord(
    drive.DriveApi api,
    Map<String, String> album,
  ) async {
    if (_isLocalAlbumRecord(album)) {
      return _sortTracksForAlbum(_localTracksForAlbum(album));
    }

    final List<drive.File> tracks = [];
    final folderIds =
        (album['id'] ?? '').split(',').where((id) => id.trim().isNotEmpty);

    for (final fId in folderIds) {
      String? pageToken;

      do {
        final res = await api.files.list(
          q: "'$fId' in parents and trashed = false",
          $fields:
              'files(id,name,mimeType,shortcutDetails(targetId,targetMimeType),size,modifiedTime),nextPageToken',
          pageSize: 100,
          pageToken: pageToken,
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
        );

        final files = res.files ?? <drive.File>[];
        tracks.addAll(files.where((file) => DriveUtils.isAudio(file)));
        pageToken = res.nextPageToken;
      } while (pageToken != null);
    }

    tracks.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    return tracks;
  }

  List<drive.File> _sortTracksForAlbum(List<drive.File> tracks) {
    final sorted = List<drive.File>.from(tracks);

    int discOf(drive.File file) {
      return _metaStore.peekFresh(file)?.discNumber ??
          _metaStore.peek(file)?.discNumber ??
          1;
    }

    int trackOf(drive.File file) {
      final cached = _metaStore.peekFresh(file) ?? _metaStore.peek(file);
      if (cached?.trackNumber != null) return cached!.trackNumber!;
      final name = file.name ?? '';
      final match = RegExp(r'^\s*(\d{1,3})[\s._-]+').firstMatch(name);
      return int.tryParse(match?.group(1) ?? '') ?? 9999;
    }

    String titleOf(drive.File file) {
      final cached = _metaStore.peekFresh(file) ?? _metaStore.peek(file);
      return (cached?.title ?? file.name ?? '').toLowerCase();
    }

    sorted.sort((a, b) {
      final discCompare = discOf(a).compareTo(discOf(b));
      if (discCompare != 0) return discCompare;

      final trackCompare = trackOf(a).compareTo(trackOf(b));
      if (trackCompare != 0) return trackCompare;

      return titleOf(a).compareTo(titleOf(b));
    });

    return sorted;
  }

  Future<void> _playCurrentAlbum({bool shuffle = false}) async {
    if (_albumTracks.isEmpty) return;

    final tracks = _sortTracksForAlbum(_albumTracks);
    if (shuffle && tracks.length > 1) {
      tracks.shuffle(math.Random());
    }

    setState(() => _albumTracks = tracks);

    final albumId = _viewingAlbum?['id'] ?? '';
    final coverUrl =
        _viewingAlbum?['cover'] ?? _libraryBrain[albumId]?['cover'] ?? '';

    await _playSong(
      tracks.first,
      queue: tracks,
      idx: 0,
      coverUrl: coverUrl,
      colors: _safeColors(_currentDynamicColors),
    );
  }

  // â”€â”€ Drive Explorer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _fetchExplore({required String folderId}) async {
    if (_user == null) {
      debugPrint('[DriveExplore] user not signed in');
      _driveExplorerLoadError = 'Sign in to load Drive folders.';
      return;
    }

    if (_loadingExplore) {
      debugPrint('Drive folder load skipped because already loading');
      return;
    }

    debugPrint('Drive folder load started');
    setState(() => _loadingExplore = true);
    _driveSettingsSetState?.call(() {});

    try {
      final headers = await _user!.authHeaders;
      final api = drive.DriveApi(GoogleAuthClient(headers));

      final result = await api.files.list(
        q: "'$folderId' in parents and trashed = false",
        $fields:
            'files(id,name,mimeType,shortcutDetails(targetId,targetMimeType),size,modifiedTime)',
        pageSize: 100,
        orderBy: 'folder,name',
        corpora: 'allDrives',
        spaces: 'drive',
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );

      final files = result.files ?? <drive.File>[];

      if (!mounted) return;

      var filteredFiles = files
          .where((f) => DriveUtils.isFolder(f) || DriveUtils.isAudio(f))
          .toList();

      if (folderId == 'root' &&
          filteredFiles.where(DriveUtils.isFolder).isEmpty) {
        debugPrint(
            'Drive root returned no direct children, loading all folders fallback');

        String? pageToken;
        final allFolders = <drive.File>[];
        do {
          final folderResult = await api.files.list(
            q: "mimeType = 'application/vnd.google-apps.folder' and trashed = false",
            $fields:
                'files(id,name,mimeType,shortcutDetails(targetId,targetMimeType),size,modifiedTime),nextPageToken',
            pageSize: 100,
            pageToken: pageToken,
            orderBy: 'name',
            corpora: 'allDrives',
            spaces: 'drive',
            supportsAllDrives: true,
            includeItemsFromAllDrives: true,
          );
          final folderFiles = folderResult.files ?? <drive.File>[];
          allFolders.addAll(
              folderFiles.where((f) => DriveUtils.isFolder(f)).toList());
          pageToken = folderResult.nextPageToken;
        } while (pageToken != null);

        filteredFiles = allFolders;
      }

      debugPrint(
          'Drive folder load completed with count ${filteredFiles.length}');

      setState(() {
        _exploreItems = filteredFiles;
        _loadingExplore = false;
        _driveExplorerLoadError = null;
      });
      _driveSettingsSetState?.call(() {});
    } catch (e) {
      debugPrint('Drive folder load failed with error: $e');
      _driveExplorerLoadError = e.toString();
      _driveExplorerAutoLoadAttempted = false;
      if (e.toString().contains('401')) {
        _showError('Session expired. Sign out and sign back in.');
      } else {
        _showError('Drive load failed: $e');
      }

      if (mounted) setState(() => _loadingExplore = false);
      _driveSettingsSetState?.call(() {});
    }
  }

  Future<void> _exploreGoBack() async {
    if (_navStack.isNotEmpty) {
      final prev = _navStack.removeLast();
      setState(() {
        _exploreFolder = prev.id == 'root' ? null : prev;
        _exploreItems = [];
      });
      _driveSettingsSetState?.call(() {});
      if (prev.id == 'root') {
        await _fetchExplore(folderId: 'root');
      } else {
        await _fetchExplore(folderId: prev.id ?? 'root');
      }
    } else {
      setState(() {
        _exploreFolder = null;
        _exploreItems = [];
      });
      _driveSettingsSetState?.call(() {});
      await _fetchExplore(folderId: 'root');
    }
  }

  Future<void> _openExploreFolder(drive.File folder) async {
    final tid = DriveUtils.effectiveId(folder);
    if (tid == null) return;

    debugPrint('selected folder changed: ${folder.name} (id: $tid)');

    if (_exploreFolder == null) {
      _navStack.add(drive.File()
        ..id = 'root'
        ..name = 'My Drive');
    } else {
      _navStack.add(_exploreFolder!);
    }

    final display = drive.File()
      ..id = tid
      ..name = folder.name
      ..mimeType = 'application/vnd.google-apps.folder';

    setState(() {
      _exploreFolder = display;
      _exploreItems = [];
    });
    _driveSettingsSetState?.call(() {});

    await _fetchExplore(folderId: tid);
  }
}
