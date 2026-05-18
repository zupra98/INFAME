part of '../../main.dart';

class MetadataScanTaskHandler extends TaskHandler {
  bool _cancelled = false;
  bool _scanStarted = false;
  int _done = 0;
  int _total = 0;
  int _fast = 0;
  int _deep = 0;
  int _failed = 0;
  int _lastPublishMs = 0;
  int _lastPublishedDone = 0;
  String _phase = 'Preparing';

  void _publish({
    bool running = true,
    bool force = false,
    int throttleMs = 450,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Updating the Android notification and SharedPreferences for every single
    // track is surprisingly expensive. Throttle normal progress updates, but
    // still allow important phase changes/final states to publish immediately.
    if (!force) {
      final doneDelta = (_done - _lastPublishedDone).abs();
      if (nowMs - _lastPublishMs < throttleMs && doneDelta < 25) return;
    }
    _lastPublishMs = nowMs;
    _lastPublishedDone = _done;

    final phaseLower = _phase.toLowerCase();
    final notificationText = phaseLower.contains('cover')
        ? (_total == 0
            ? 'Preparing embedded cover scan...'
            : 'Scanning covers $_done/$_total â€¢ Found: $_fast â€¢ Skipped: $_deep â€¢ Missing: $_failed')
        : phaseLower.contains('saving')
            ? 'Saving metadata cache...'
            : _total == 0
                ? 'Preparing metadata scan...'
                : 'Scanning metadata $_done/$_total â€¢ Fast: $_fast â€¢ Deep: $_deep â€¢ Failed: $_failed';

    FlutterForegroundTask.updateService(
      notificationTitle: 'Infame metadata scan',
      notificationText: notificationText,
    );

    final payload = {
      'type': 'metadata_progress',
      'done': _done,
      'total': _total,
      'fast': _fast,
      'deep': _deep,
      'failed': _failed,
      'phase': _phase,
      'running': running,
      'updatedAt': nowMs,
    };

    _saveMetadataProgressSnapshot(payload);
    FlutterForegroundTask.sendDataToMain(payload);
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    DartPluginRegistrant.ensureInitialized();

    // IMPORTANT: Start the real scan from inside onStart.
    // Waiting for sendDataToTask() after startService() can make the plugin
    // hit the foreground-service request timeout on some Android devices.
    _scanStarted = true;
    _phase = 'Starting';

    FlutterForegroundTask.updateService(
      notificationTitle: 'Infame metadata scan',
      notificationText: 'Starting metadata scan...',
    );

    _publish(force: true);

    Future.microtask(_runScan);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _publish();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    final payload = {
      'type': 'metadata_progress',
      'done': _done,
      'total': _total,
      'fast': _fast,
      'deep': _deep,
      'failed': _failed,
      'phase': isTimeout ? 'Stopped by Android timeout' : _phase,
      'running': false,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    _saveMetadataProgressSnapshot(payload);
    FlutterForegroundTask.sendDataToMain(payload);
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'start_metadata_scan') {
      if (_scanStarted) return;
      _scanStarted = true;
      Future.microtask(_runScan);
      return;
    }

    if (data == 'cancel_metadata_scan') {
      _cancelled = true;
      _phase = 'Cancelling';
      _publish();
    }
  }

  Future<void> _runScan() async {
    try {
      await _metaStore.load();

      final token = await FlutterForegroundTask.getData<String>(
        key: 'metadata_token',
      );
      final albumsRaw = await FlutterForegroundTask.getData<String>(
        key: 'metadata_albums',
      );

      if (token == null ||
          token.isEmpty ||
          albumsRaw == null ||
          albumsRaw.isEmpty) {
        _phase = 'Missing scan data';
        _publish(running: false, force: true);
        await FlutterForegroundTask.stopService();
        return;
      }

      final albums = List<Map<String, String>>.from(
        (json.decode(albumsRaw) as List).map(
          (e) => Map<String, String>.from(e),
        ),
      );

      _phase = 'Collecting tracks';
      _publish();

      final api = drive.DriveApi(
        GoogleAuthClient({'Authorization': 'Bearer $token'}),
      );
      final Map<String, drive.File> uniqueTracks = {};
      final Map<String, Map<String, String>> trackAlbums = {};
      final Map<String, List<drive.File>> albumTracks = {};

      for (final album in albums) {
        if (_cancelled) break;
        final tracks = await _fetchTracksForAlbumRecordBackground(api, album);
        albumTracks[_albumCacheKey(album, source: 'metadata_album_tracks')] =
            tracks;

        for (final track in tracks) {
          final id = DriveUtils.effectiveId(track);
          if (id == null) continue;
          uniqueTracks[id] = track;
          trackAlbums[id] = album;
        }
      }

      final missing = uniqueTracks.values
          .where((track) => _metaStore.peekFresh(track) == null)
          .toList()
        ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

      _total = missing.length;
      _done = 0;
      _publish();

      if (missing.isNotEmpty) {
        _phase = 'Fast text scan';
        _publish(force: true, throttleMs: 900);
        final textScanStart = DateTime.now();
        final controller = _ScanConcurrencyController(
          initialConcurrency: 8,
          maxConcurrency: 12,
        );
        final textClient = http.Client();
        try {
          await _runWithConcurrency<drive.File>(missing, controller, (
            track,
            index,
          ) async {
            if (_cancelled) return;
            final ok = await _loadFastTextMetadataBackground(
              track,
              token,
              client: textClient,
            );
            if (ok) {
              _fast++;
            } else {
              _failed++;
            }
            _done++;
            _publish(throttleMs: 900);
            if (_done % 100 == 0) {
              await _metaStore.persistNow();
            }
          });
        } finally {
          textClient.close();
        }

        await _metaStore.persistNow();
        final textElapsedMs = math.max(
          1,
          DateTime.now().difference(textScanStart).inMilliseconds,
        );
        final textRate = (_done * 60000 / textElapsedMs).toStringAsFixed(1);
        debugPrint(
          'MetadataScan perf text completed=$_done/${missing.length} rate=$textRate tracks/min errors=$_failed',
        );
      }

      // Even when all text metadata is already fresh, covers may still be
      // missing. Do not skip this phase just because there are no tracks in
      // the text-metadata queue.
      final coverTargets = <Map<String, String>>[];
      var skipped = 0;
      for (final album in albums) {
        if (_cancelled) break;

        final albumId = _albumCacheKey(album, source: 'cover_scan_album_id');
        final tracks = albumTracks[albumId] ?? <drive.File>[];
        final resolvedCover = _resolvedAlbumCoverBackground(album, tracks);
        final currentCover = (album['cover'] ?? '').trim();
        if (resolvedCover.isNotEmpty) {
          skipped++;
          debugPrint(
            'CoverScan skip cached albumKey=${_albumCoverScanKey(album)} reason=existing_cover',
          );
          continue;
        }

        if (!_isAlbumCoverScanStale(album)) {
          skipped++;
          debugPrint(
            'CoverScan skip cached albumKey=${_albumCoverScanKey(album)} reason=already_checked',
          );
          continue;
        }

        if (tracks.isEmpty) {
          album[_embeddedCoverScanFingerprintKey] = _albumCoverScanFingerprint(
            album,
          );
          skipped++;
          debugPrint(
            'CoverScan skip cached albumKey=${_albumCoverScanKey(album)} reason=no_tracks',
          );
          continue;
        }

        if (currentCover.isNotEmpty && resolvedCover.isEmpty) {
          debugPrint(
            'CoverScan key mismatch suspected oldKey=${album['id'] ?? ''} normalizedKey=${_albumCoverScanKey(album)}',
          );
        }

        coverTargets.add(album);
      }

      debugPrint('CoverScan started albumsMissingCover=${coverTargets.length}');

      _phase = 'Embedded cover scan';
      _total = coverTargets.length;
      _done = 0;
      _fast = 0;
      _deep = skipped;
      _failed = 0;
      _publish(force: true, throttleMs: 2000);
      final coverStart = DateTime.now();

      final controller = _ScanConcurrencyController(
        initialConcurrency: 2,
        maxConcurrency: 3,
      );
      var found = 0;
      var coverMissing = 0;

      final coverClient = http.Client();
      try {
        await _runWithConcurrency<Map<String, String>>(coverTargets, controller,
            (album, index) async {
          if (_cancelled) return;

          final albumId = _albumCacheKey(
            album,
            source: 'cover_scan_worker_album_id',
          );
          final albumKey = _albumCoverScanKey(album);
          final tracks = albumTracks[albumId] ?? <drive.File>[];
          final fingerprint = _albumCoverScanFingerprint(album);

          final coverPath = await _probeAlbumEmbeddedCoverBackground(
            album,
            tracks,
            token,
            client: coverClient,
          );

          album[_embeddedCoverScanFingerprintKey] = fingerprint;
          if (coverPath != null && coverPath.isNotEmpty) {
            album['cover'] = coverPath;
            _applyAlbumCoverPathToTrackCacheBackground(tracks, coverPath);
            _sendAlbumCoverFoundBackground(albumId, coverPath);
            found++;
            debugPrint(
              'CoverScan saved albumKey=$albumKey bytes=${coverPath.isNotEmpty ? '1' : '0'}',
            );
          } else {
            coverMissing++;
            debugPrint('CoverScan not found albumKey=$albumKey');
          }

          _done++;
          _fast = found;
          _deep = skipped;
          _failed = coverMissing;
          _publish(throttleMs: 2000);
        });
      } finally {
        coverClient.close();
      }

      debugPrint(
        'CoverScan complete found=$found missing=$coverMissing skipped=$skipped',
      );
      final coverElapsedMs = math.max(
        1,
        DateTime.now().difference(coverStart).inMilliseconds,
      );
      final avgCoverMs = coverTargets.isEmpty
          ? 0
          : (coverElapsedMs / coverTargets.length).round();
      debugPrint(
        'ArtworkHydration perf albumsDone=${coverTargets.length} coversFound=$found avgCoverMs=$avgCoverMs skippedCached=$skipped noCover=$coverMissing',
      );

      await _metaStore.persistNow();
      await _persistAlbumsBackground(albums);

      _enrichAlbumsBackground(albums, albumTracks);
      await _metaStore.persistNow();
      await _persistAlbumsBackground(albums);
      debugPrint('UI refresh after cover scan');

      _phase = _cancelled ? 'Cancelled' : 'Complete';
      _publish(running: false, force: true);
      await FlutterForegroundTask.stopService();
    } catch (_) {
      _phase = 'Failed';
      _failed++;
      _publish(running: false, force: true);
      await FlutterForegroundTask.stopService();
    }
  }

  Future<List<drive.File>> _fetchTracksForAlbumRecordBackground(
    drive.DriveApi api,
    Map<String, String> album,
  ) async {
    final List<drive.File> tracks = [];
    final folderIds = _albumCacheKey(
      album,
      source: 'fetch_tracks_album_id',
    ).split(',').where((id) => id.trim().isNotEmpty);

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

  Future<bool> _loadFastTextMetadataBackground(
    drive.File file,
    String token, {
    http.Client? client,
  }) async {
    try {
      final fallback = DriveUtils.getTrackMeta(file);
      final fastResult = await FastTagReader.read(
        file: file,
        token: token,
        readCover: false,
        client: client,
      );

      final hasFastText = fastResult != null && fastResult.hasUsefulText;
      final durationMs = _validDurationMsFromBackgroundValue(
        fastResult?.duration?.inMilliseconds,
      );

      _metaStore.putMemory(
        file,
        TrackMetadata(
          title: hasFastText && fastResult!.title?.trim().isNotEmpty == true
              ? fastResult.title!.trim()
              : fallback['title'] ?? file.name ?? 'Unknown',
          artist: hasFastText && fastResult!.artist?.trim().isNotEmpty == true
              ? fastResult.artist!.trim()
              : fallback['artist'] ?? 'Unknown Artist',
          album: hasFastText && fastResult!.album?.trim().isNotEmpty == true
              ? fastResult.album!.trim()
              : null,
          year: hasFastText ? fastResult!.year : null,
          genre: hasFastText ? fastResult!.genre : null,
          trackNumber: hasFastText ? fastResult!.trackNumber : null,
          discNumber: hasFastText ? fastResult!.discNumber : null,
          modifiedTime: file.modifiedTime?.toIso8601String(),
          size: file.size,
          durationMs: durationMs,
        ),
      );

      return true;
    } catch (_) {
      try {
        final fallback = DriveUtils.getTrackMeta(file);
        _metaStore.putMemory(
          file,
          TrackMetadata(
            title: fallback['title'] ?? file.name ?? 'Unknown',
            artist: fallback['artist'] ?? 'Unknown Artist',
            album: null,
            year: null,
            genre: null,
            trackNumber: null,
            discNumber: null,
            modifiedTime: file.modifiedTime?.toIso8601String(),
            size: file.size,
          ),
        );
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> _loadDeepMetadataBackground(
    drive.File file,
    String token,
  ) async {
    File? tempFile;

    try {
      final fileId = DriveUtils.effectiveId(file);
      if (fileId == null) return false;

      final fallback = DriveUtils.getTrackMeta(file);
      tempFile = await _downloadTrackToTempBackground(
        fileId,
        token,
        _audioExtensionFromFile(file),
      );
      final metadata = readMetadata(tempFile, getImage: false);

      _metaStore.putMemory(
        file,
        TrackMetadata(
          title: metadata.title?.trim().isNotEmpty == true
              ? metadata.title!.trim()
              : fallback['title'] ?? file.name ?? 'Unknown',
          artist: metadata.artist?.trim().isNotEmpty == true
              ? metadata.artist!.trim()
              : fallback['artist'] ?? 'Unknown Artist',
          album: metadata.album?.trim().isNotEmpty == true
              ? metadata.album!.trim()
              : null,
          year: null,
          genre: null,
          trackNumber: metadata.trackNumber,
          discNumber: metadata.discNumber,
          modifiedTime: file.modifiedTime?.toIso8601String(),
          size: file.size,
        ),
      );

      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  String? _firstCachedAlbumCoverPathBackground(List<drive.File> tracks) {
    for (final track in tracks) {
      final coverPath = _metaStore.peek(track)?.coverPath;
      if (coverPath != null &&
          coverPath.isNotEmpty &&
          (!(_isLocalCover(coverPath)) ||
              File(_localCoverPath(coverPath)).existsSync())) {
        return coverPath;
      }
    }
    return null;
  }

  void _applyAlbumCoverPathToTrackCacheBackground(
    List<drive.File> tracks,
    String coverPath,
  ) {
    if (coverPath.isEmpty) return;

    for (final track in tracks) {
      final fallback = DriveUtils.getTrackMeta(track);
      final cached = _metaStore.peek(track);

      if (cached != null && cached.coverPath == coverPath) continue;

      _metaStore.putMemory(
        track,
        TrackMetadata(
          title: cached?.title ?? fallback['title'] ?? track.name ?? 'Unknown',
          artist: cached?.artist ?? fallback['artist'] ?? 'Unknown Artist',
          album: cached?.album,
          trackNumber: cached?.trackNumber,
          discNumber: cached?.discNumber,
          coverPath: coverPath,
          year: cached?.year,
          genre: cached?.genre,
          modifiedTime:
              cached?.modifiedTime ?? track.modifiedTime?.toIso8601String(),
          size: cached?.size ?? track.size,
        ),
      );
    }
  }

  bool _isAlbumCoverScanStale(Map<String, String> album) {
    final fingerprint = _albumCoverScanFingerprint(album);
    final cachedFingerprint = _cleanBackgroundValue(
      album[_embeddedCoverScanFingerprintKey],
    );
    return cachedFingerprint != fingerprint;
  }

  Future<String?> _probeAlbumEmbeddedCoverBackground(
    Map<String, String> album,
    List<drive.File> tracks,
    String token, {
    http.Client? client,
  }) async {
    final albumKey = _albumCoverScanKey(album);

    final cachedCover = _firstCachedAlbumCoverPathBackground(tracks);
    if (cachedCover != null &&
        (!(_isLocalCover(cachedCover)) ||
            File(_localCoverPath(cachedCover)).existsSync())) {
      debugPrint('CoverScan found album=$albumKey from cache');
      return cachedCover;
    }

    for (final track in tracks.take(3)) {
      debugPrint(
        'CoverScan probe album=$albumKey track=${track.name ?? 'unknown'}',
      );
      final result = await FastTagReader.read(
        file: track,
        token: token,
        readCover: true,
        client: client,
      );
      final bytes = result?.coverBytes;
      if (bytes == null || bytes.isEmpty) continue;
      debugPrint('CoverScan found album=$albumKey bytes=${bytes.length}');
      final coverPath = await _saveEmbeddedCoverBackground(track, bytes);
      if (coverPath != null && coverPath.isNotEmpty) {
        return coverPath;
      }
    }

    return null;
  }

  String _cleanBackgroundValue(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty ||
        v.toLowerCase() == 'unknown' ||
        v.toLowerCase() == 'unknown artist') {
      return '';
    }
    return v;
  }

  String _mostCommonBackground(List<String> values) {
    final counts = <String, int>{};
    for (final raw in values) {
      final value = _cleanBackgroundValue(raw);
      if (value.isEmpty) continue;
      counts[value] = (counts[value] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        if (c != 0) return c;
        return a.key.compareTo(b.key);
      });
    return entries.first.key;
  }

  String _yearBackground(String? value) {
    if (value == null) return '';
    final match = RegExp(r'(19|20)\d{2}').firstMatch(value);
    return match?.group(0) ?? '';
  }

  String _genreBackground(String? value) {
    final g = _cleanBackgroundValue(value);
    if (g.isEmpty) return '';

    final first = g.split('/').first.split(';').first.split(',').first.trim();
    final t = first.toLowerCase();
    final normalized = t.replaceAll(RegExp(r'[^a-z0-9&]+'), ' ').trim();
    final words =
        normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();

    bool has(String word) => words.contains(word);

    if (normalized.contains('hip hop') ||
        t.contains('hip-hop') ||
        has('rap') ||
        has('trap')) {
      return 'Hip-Hop';
    }
    if (t.contains('r&b') || has('rnb') || has('soul') || has('funk'))
      return 'Soul / R&B';
    if (has('jazz')) return 'Jazz';
    if (has('rock') || has('metal') || has('punk')) return 'Rock';
    if (has('electronic') || has('house') || has('techno') || has('dance'))
      return 'Electronic';
    if (has('soundtrack') || has('score')) return 'Soundtracks';
    if (has('pop')) return 'Pop';
    return first;
  }

  void _enrichAlbumsBackground(
    List<Map<String, String>> albums,
    Map<String, List<drive.File>> albumTracks,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch.toString();

    for (final album in albums) {
      final albumId = _albumCacheKey(album, source: 'enrich_album_id');
      if (albumId.isEmpty) continue;
      final tracks = albumTracks[albumId] ?? <drive.File>[];
      if (tracks.isEmpty) continue;

      final artists = <String>[];
      final albumNames = <String>[];
      final years = <String>[];
      final genres = <String>[];

      for (final track in tracks) {
        final cached = _metaStore.peek(track);
        if (cached == null) continue;
        artists.add(cached.artist);
        if (cached.album != null) albumNames.add(cached.album!);
        if (cached.year != null) years.add(cached.year!);
        if (cached.genre != null) genres.add(cached.genre!);
      }

      final folderName = album['name'] ?? 'Album';
      final folderGuess = _artistAlbumFromFolderBackground(folderName);
      final displayName = _mostCommonBackground(albumNames).isNotEmpty
          ? _mostCommonBackground(albumNames)
          : folderGuess['album'] ?? folderName;
      final artist = _mostCommonBackground(artists).isNotEmpty
          ? _mostCommonBackground(artists)
          : folderGuess['artist'] ?? '';
      final year = _mostCommonBackground(years).isNotEmpty
          ? _yearBackground(_mostCommonBackground(years))
          : _yearBackground('$displayName $folderName');
      final genre = _genreBackground(_mostCommonBackground(genres));

      album['displayName'] = displayName;
      album['artist'] = artist;
      album['year'] = year;
      album['genre'] = genre;
      album['trackCount'] = tracks.length.toString();
      album['dateAdded'] = album['dateAdded'] ?? now;
    }
  }
}

Map<String, String> _artistAlbumFromFolderBackground(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'\s*\[(19|20)\d{2}\]\s*'), ' ')
      .replaceAll(RegExp(r'\s*\((19|20)\d{2}\)\s*'), ' ')
      .trim();

  final parts = cleaned.split(RegExp(r'\s+[â€“â€”-]\s+'));
  if (parts.length < 2) return const <String, String>{};

  final artist = _cleanMetadataValue(parts.first);
  final album = _cleanMetadataValue(parts.sublist(1).join(' - '));
  if (artist.isEmpty || album.isEmpty) return const <String, String>{};

  return {'artist': artist, 'album': album};
}

String _cleanMetadataValue(String? value) {
  final cleaned = (value ?? '')
      .replaceAll('\u0000', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (cleaned.isEmpty) return '';

  final lower = cleaned.toLowerCase();
  if (lower == 'unknown' ||
      lower == 'unknown artist' ||
      lower == 'untitled' ||
      lower == 'null' ||
      lower == 'none') {
    return '';
  }

  return cleaned;
}

String _safeCacheNameGlobal(String id) {
  return id
      .replaceAll('/', '_')
      .replaceAll(':', '_')
      .replaceAll('?', '_')
      .replaceAll('&', '_')
      .replaceAll('=', '_');
}

String _audioExtensionFromFile(drive.File file) {
  final name = file.name ?? 'track.mp3';
  final dot = name.lastIndexOf('.');
  if (dot == -1) return '.mp3';
  return name.substring(dot).toLowerCase();
}

String _coverExtensionFromBytesGlobal(Uint8List bytes) {
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

Future<File> _downloadTrackToTempBackground(
  String fileId,
  String token,
  String extension,
) async {
  final dir = await getTemporaryDirectory();
  final unique = DateTime.now().microsecondsSinceEpoch;
  final path =
      '${dir.path}/musix_deep_${_safeCacheNameGlobal(fileId)}_$unique$extension';
  final tempFile = File(path);

  final uri = Uri.parse(
    'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
  );
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
        'Could not download metadata file: ${finalResponse.statusCode}',
      );
    }

    final sink = tempFile.openWrite();
    await finalResponse.stream.pipe(sink);
    return tempFile;
  } finally {
    client.close();
  }
}

Future<String?> _saveEmbeddedCoverBackground(
  drive.File file,
  Uint8List bytes,
) async {
  final fileId = DriveUtils.effectiveId(file);
  if (fileId == null || bytes.isEmpty) return null;

  try {
    final dir = await getApplicationDocumentsDirectory();
    final coverDir = Directory('${dir.path}/musix_embedded_covers');
    if (!await coverDir.exists()) {
      await coverDir.create(recursive: true);
    }

    final ext = _coverExtensionFromBytesGlobal(bytes);
    final path = '${coverDir.path}/${_safeCacheNameGlobal(fileId)}$ext';
    final out = File(path);
    await out.writeAsBytes(bytes, flush: true);
    return 'file://$path';
  } catch (_) {
    return null;
  }
}

Future<void> _persistAlbumsBackground(List<Map<String, String>> albums) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_albumsPrefsKey, json.encode(albums));
}
