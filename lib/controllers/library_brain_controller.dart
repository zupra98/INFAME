part of '../main.dart';

extension _LibraryBrainControllerExtension on _MainScreenState {
  String _cleanBrainValue(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty ||
        v.toLowerCase() == 'unknown' ||
        v.toLowerCase() == 'unknown artist') {
      return '';
    }
    return v;
  }

  String _yearFromText(String value) {
    final match = RegExp(r'(19|20)\d{2}').firstMatch(value);
    return match?.group(0) ?? '';
  }

  String _decadeFromYear(String year) {
    final y = int.tryParse(year);
    if (y == null) return '';
    return '${(y ~/ 10) * 10}s';
  }

  Map<String, String> _artistAlbumFromFolder(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'\s*\[(19|20)\d{2}\]\s*'), ' ')
        .replaceAll(RegExp(r'\s*\((19|20)\d{2}\)\s*'), ' ')
        .trim();

    final parts = cleaned.split(RegExp(r'\s+[â€“â€”-]\s+'));
    if (parts.length < 2) return const <String, String>{};

    // Assume format is "Album - Artist" (not "Artist - Album")
    final album = _cleanBrainValue(parts.first);
    final artist = _cleanBrainValue(parts.sublist(1).join(' - '));
    if (artist.isEmpty || album.isEmpty) return const <String, String>{};

    return {
      'artist': artist,
      'album': album,
    };
  }

  bool _looksLikeOldNameGuessedGenre(String? genre, String context) {
    final g = _cleanBrainValue(genre);
    if (g.isEmpty) return false;

    final t = context.toLowerCase();
    if (g == 'Rock' &&
        (t.contains('pete rock') ||
            t.contains('a\$ap rock') ||
            t.contains('asap rock') ||
            t.contains('rocky') ||
            t.contains('metal fingers') ||
            t.contains('metalface') ||
            t.contains('mf doom'))) {
      return true;
    }

    if (g == 'Soul / R&B' && t.contains('de la soul')) return true;

    return false;
  }

  String _genreFromText(String text) {
    // Intentionally disabled. Infame should never guess genre from artist,
    // album, or folder names. Names like Pete Rock, A$AP Rocky, De La Soul,
    // and Metal Fingers made the old guessing system poison the library.
    // Only trusted embedded tag genres should be used.
    return '';
  }

  String _normalizeGenre(String value) {
    final g = _cleanBrainValue(value);
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
    if (has('electronic') || has('house') || has('techno') || has('dance')) {
      return 'Electronic';
    }
    if (has('soundtrack') || has('score')) return 'Soundtracks';
    if (has('pop')) return 'Pop';

    return first;
  }

  String _mostCommon(List<String> values) {
    final counts = <String, int>{};
    for (final raw in values) {
      final value = _cleanBrainValue(raw);
      if (value.isEmpty) continue;
      counts[value] = (counts[value] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';

    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });

    return entries.first.key;
  }

  int _brainInt(Map<String, String> info, String key) {
    return int.tryParse(info[key] ?? '') ?? 0;
  }

  Future<void> _loadLibraryBrainAndHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final brainRaw = prefs.getString(_libraryBrainPrefsKey);
      final historyRaw = prefs.getString(_playHistoryPrefsKey);

      final nextBrain = <String, Map<String, String>>{};
      if (brainRaw != null && brainRaw.isNotEmpty) {
        final decoded = json.decode(brainRaw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is String && value is Map) {
              nextBrain[key] = Map<String, String>.from(value);
            }
          });
        }
      }

      final nextHistory = <Map<String, String>>[];
      if (historyRaw != null && historyRaw.isNotEmpty) {
        final decoded = json.decode(historyRaw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) nextHistory.add(Map<String, String>.from(item));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _libraryBrain
          ..clear()
          ..addAll(nextBrain);
        _playHistory
          ..clear()
          ..addAll(nextHistory.take(40));
      });

      _invalidateHomeBrowseCache();
      unawaited(_rebuildBrainWithCorrectParsing());
      _buildBasicLibraryBrain(save: false);
      _queueArtistImagePrefetch();
      _prewarmHomeMetadataCache();
    } catch (_) {}
  }

  Future<void> _rebuildBrainWithCorrectParsing() async {
    // Fix any albums that have swapped artist/album from old folder parsing
    debugPrint(
        '[BrainFix] Checking for swapped metadata in ${_libraryBrain.length} albums');
    int fixed = 0;
    var processed = 0;

    for (final entry in _libraryBrain.entries.toList()) {
      processed++;
      if (processed % 24 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final id = entry.key;
      final brain = entry.value;
      final name = brain['name'] ?? '';

      // Re-parse folder name with correct logic
      final folderGuess = _artistAlbumFromFolder(name);
      if (folderGuess.isEmpty) continue;

      final currentDisplayName = brain['displayName'] ?? '';
      final currentArtist = brain['artist'] ?? '';
      final guessedAlbum = folderGuess['album'] ?? '';
      final guessedArtist = folderGuess['artist'] ?? '';

      // Check if metadata looks swapped (album name matches artist field, artist name matches displayName field)
      if (currentDisplayName.isNotEmpty &&
          currentArtist.isNotEmpty &&
          guessedAlbum.isNotEmpty &&
          guessedArtist.isNotEmpty) {
        // If current displayName looks like an artist and current artist looks like an album
        if (currentDisplayName
                .toLowerCase()
                .contains(guessedArtist.toLowerCase()) &&
            currentArtist.toLowerCase().contains(guessedAlbum.toLowerCase())) {
          // Swap them
          brain['displayName'] = guessedAlbum;
          brain['artist'] = guessedArtist;
          _libraryBrain[id] = brain;
          fixed++;
          debugPrint(
              '[BrainFix] Fixed $id: "$currentDisplayName" by "$currentArtist" â†’ "$guessedAlbum" by "$guessedArtist"');
        }
      }
    }

    if (fixed > 0) {
      debugPrint('[BrainFix] Fixed $fixed albums with swapped metadata');
      _saveLibraryBrain();
    }
  }

  void _prewarmHomeMetadataCache() {
    if (_albums.isEmpty) return;
    // Pre-resolve metadata for home tab albums in background
    // This prevents freeze on first home tab render
    Future.microtask(() {
      try {
        final recent = _recentBrainAlbums(limit: 14);
        final played = _lastPlayedAlbums(limit: 10);
        final primaryAlbums = played.isNotEmpty ? played : recent;

        // Resolve a few albums at a time to avoid blocking
        for (final album in primaryAlbums.take(5)) {
          _resolvedAlbumMap(album);
        }
        for (final album in _albums.take(10)) {
          _resolvedAlbumMap(album);
        }
      } catch (_) {}
    });
  }

  Future<void> _saveLibraryBrain() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_libraryBrainPrefsKey, json.encode(_libraryBrain));
  }

  Future<void> _savePlayHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _playHistoryPrefsKey, json.encode(_playHistory.take(40).toList()));
  }

  void _buildBasicLibraryBrain({bool save = true}) {
    if (_albums.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch.toString();
    bool changed = false;

    for (final album in _albums) {
      final id = _albumCacheKey(album, source: 'build_brain');
      if (id.isEmpty) continue;

      final existing = _libraryBrain[id] ?? <String, String>{};
      final name = album['name'] ?? existing['name'] ?? 'Album';
      final folderGuess = _artistAlbumFromFolder(name);
      final cover = album['cover'] ?? existing['cover'] ?? '';
      final dateAdded = album['dateAdded'] ?? existing['dateAdded'] ?? now;
      final savedArtist = _canonicalArtistName(
        albumArtist: album['artist'],
        trackArtist: existing['artist'] ?? '',
        albumName: name,
      );
      final savedDisplayName = _cleanBrainValue(album['displayName']).isNotEmpty
          ? album['displayName']!
          : _cleanBrainValue(existing['displayName']).isNotEmpty
              ? existing['displayName']!
              : folderGuess['album'] ?? name;
      final year = _cleanBrainValue(album['year']).isNotEmpty
          ? album['year']!
          : _cleanBrainValue(existing['year']).isNotEmpty
              ? existing['year']!
              : _yearFromText(name);
      final rawGenre = _cleanBrainValue(album['genre']).isNotEmpty
          ? _normalizeGenre(album['genre']!)
          : _cleanBrainValue(existing['genre']).isNotEmpty
              ? _normalizeGenre(existing['genre']!)
              : '';
      final genre =
          _looksLikeOldNameGuessedGenre(rawGenre, '$name $savedArtist')
              ? ''
              : rawGenre;

      album['dateAdded'] = dateAdded;
      album['id'] = id;
      album['albumKey'] = id;

      final next = <String, String>{
        'albumId': id,
        'name': name,
        'displayName': savedDisplayName,
        'artist': savedArtist,
        'year': year,
        'decade': _decadeFromYear(year),
        'genre': genre,
        'cover': cover,
        'trackCount': album['trackCount'] ?? existing['trackCount'] ?? '',
        'playCount': existing['playCount'] ?? '0',
        'lastPlayed': existing['lastPlayed'] ?? '',
        'dateAdded': dateAdded,
      };

      if (json.encode(existing) != json.encode(next)) {
        _libraryBrain[id] = next;
        changed = true;
      }
    }

    if (changed && save) {
      if (mounted) setState(() {});
      _saveLibraryBrain();
      _persistAlbums();
    }
  }

  void _indexAlbumFromTracks(Map<String, String> album, List<drive.File> tracks,
      {bool save = true}) {
    final id = _albumCacheKey(album, source: 'index_album');
    if (id.isEmpty) return;

    final existing = _libraryBrain[id] ?? <String, String>{};
    final artists = <String>[];
    final albumNames = <String>[];
    final years = <String>[];
    final genres = <String>[];

    for (final track in tracks) {
      final cached = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      if (cached == null) continue;
      artists.add(cached.artist);
      if (cached.album != null) albumNames.add(cached.album!);
      if (cached.year != null) years.add(cached.year!);
      if (cached.genre != null) genres.add(cached.genre!);
    }

    final folderName = album['name'] ?? existing['name'] ?? 'Album';
    final folderGuess = _artistAlbumFromFolder(folderName);
    final commonArtist = _mostCommonCleanValue(
      artists,
      accept: (value) => !_isBadArtistName(value),
    );
    final commonAlbum = _mostCommonCleanValue(
      albumNames,
      accept: (value) => !_isWeakAlbumDisplayTitle(value, artist: commonArtist),
    );
    final displayName = commonAlbum.isNotEmpty
        ? commonAlbum
        : (!_isWeakAlbumDisplayTitle(existing['displayName'],
                artist: commonArtist)
            ? existing['displayName']!
            : (folderGuess['album'] ?? folderName));
    final artist = _canonicalArtistName(
      albumArtist: commonArtist,
      trackArtist: existing['artist'] ?? '',
      albumName: displayName,
    );
    final rawYear = _mostCommon(years).isNotEmpty
        ? _mostCommon(years)
        : _yearFromText('$displayName $folderName');
    final rawGenre = _normalizeGenre(_mostCommon(genres));

    final next = <String, String>{
      'albumId': id,
      'name': folderName,
      'displayName': displayName,
      'artist': artist,
      'year': rawYear,
      'decade': _decadeFromYear(rawYear),
      'genre': rawGenre,
      'cover': album['cover'] ?? existing['cover'] ?? '',
      'trackCount': tracks.length.toString(),
      'playCount': existing['playCount'] ?? '0',
      'lastPlayed': existing['lastPlayed'] ?? '',
      'dateAdded': album['dateAdded'] ??
          existing['dateAdded'] ??
          DateTime.now().millisecondsSinceEpoch.toString(),
    };

    album['displayName'] = displayName;
    album['artist'] = artist;
    album['year'] = rawYear;
    album['genre'] = rawGenre;
    album['trackCount'] = tracks.length.toString();
    album['id'] = id;
    album['albumKey'] = id;

    _libraryBrain[id] = next;
    if (save) {
      _saveLibraryBrain();
      _persistAlbums();
      if (mounted) setState(() {});
    }
  }

  Future<void> _recordPlay(drive.File file, {String? coverUrl}) async {
    final fileId = DriveUtils.effectiveId(file);
    if (fileId == null) return;

    final meta = DriveUtils.getTrackMeta(file);
    final safeCoverUrl = _sanitizeCoverSource(coverUrl);
    final currentAlbum = _viewingAlbum;
    final albumId = currentAlbum == null
        ? ''
        : _albumCacheKey(currentAlbum, source: 'record_play');
    final albumName =
        currentAlbum == null ? '' : _resolvedAlbumTitle(currentAlbum);
    final now = DateTime.now().millisecondsSinceEpoch.toString();

    _playHistory.removeWhere((item) => item['fileId'] == fileId);
    _playHistory.insert(0, {
      'fileId': fileId,
      'title': meta['title'] ?? file.name ?? 'Unknown',
      'artist': meta['artist'] ?? 'Unknown Artist',
      'albumId': albumId,
      'albumName': albumName.isNotEmpty ? albumName : (meta['album'] ?? ''),
      'albumKey': albumId,
      'cover': safeCoverUrl.isNotEmpty
          ? safeCoverUrl
          : _sanitizeCoverSource(currentAlbum?['cover']),
      'playedAt': now,
    });

    if (_playHistory.length > 40) {
      _playHistory.removeRange(40, _playHistory.length);
    }

    if (albumId.isNotEmpty) {
      final existing = _libraryBrain[albumId] ?? <String, String>{};
      existing['albumId'] = albumId;
      existing['name'] = existing['name'] ?? albumName;
      existing['displayName'] = existing['displayName'] ?? albumName;
      existing['cover'] = safeCoverUrl.isNotEmpty
          ? safeCoverUrl
          : _sanitizeCoverSource(existing['cover'] ?? currentAlbum?['cover']);
      existing['playCount'] =
          ((_brainInt(existing, 'playCount')) + 1).toString();
      existing['lastPlayed'] = now;
      existing['dateAdded'] =
          existing['dateAdded'] ?? _viewingAlbum?['dateAdded'] ?? now;
      _libraryBrain[albumId] = Map<String, String>.from(existing);
      _saveLibraryBrain();
    }

    _savePlayHistory();
    _invalidateHomeBrowseCache();
    if (mounted) setState(() {});
  }

  List<Map<String, String>> _brainAlbums() {
    _buildBasicLibraryBrain(save: false);

    final items = _albums
        .map((album) {
          final key = _albumCacheKey(album, source: 'brain_album');
          final brain = Map<String, String>.from(
              _libraryBrain[key] ?? <String, String>{});
          final resolved = _resolvedAlbumMap({
            ...album,
            'id': key,
            'albumKey': key,
            ...brain,
          });
          resolved['albumId'] = key;
          resolved['dateAdded'] =
              album['dateAdded'] ?? brain['dateAdded'] ?? '0';
          return resolved;
        })
        .where((item) => (item['albumId'] ?? '').isNotEmpty)
        .toList();

    return items;
  }

  Map<String, String>? _albumById(String id) {
    for (final album in _albums) {
      if (_albumCacheKey(album, source: 'album_by_id') == id ||
          (album['id'] ?? '') == id) {
        return album;
      }
    }
    return null;
  }

  void _openAlbumByBrain(Map<String, String> info) {
    final id = _albumCacheKey(info, source: 'open_by_brain');
    final album = _albumById(id);
    if (album != null) _openAlbum(album);
  }

  List<Map<String, String>> _recentBrainAlbums({int limit = 8}) {
    final items = _brainAlbums()
      ..sort((a, b) =>
          _brainInt(b, 'dateAdded').compareTo(_brainInt(a, 'dateAdded')));
    return items.take(limit).toList();
  }

  List<Map<String, String>> _lastPlayedAlbums({int limit = 8}) {
    final items = _brainAlbums()
        .where((a) => _brainInt(a, 'lastPlayed') > 0)
        .toList()
      ..sort((a, b) =>
          _brainInt(b, 'lastPlayed').compareTo(_brainInt(a, 'lastPlayed')));
    return items.take(limit).toList();
  }

  List<Map<String, String>> _albumsForGenre(String genre, {int limit = 8}) {
    final items = _brainAlbums()
        .where((a) => (a['genre'] ?? '') == genre)
        .toList()
      ..sort((a, b) =>
          _brainInt(b, 'dateAdded').compareTo(_brainInt(a, 'dateAdded')));
    return items.take(limit).toList();
  }

  List<Map<String, String>> _albumsForDecade(String decade, {int limit = 8}) {
    final items = _brainAlbums()
        .where((a) => (a['decade'] ?? '') == decade)
        .toList()
      ..sort(
          (a, b) => (a['displayName'] ?? '').compareTo(b['displayName'] ?? ''));
    return items.take(limit).toList();
  }

  List<String> _topGenres({int limit = 3}) {
    final counts = <String, int>{};
    for (final album in _brainAlbums()) {
      final genre = album['genre'] ?? '';
      if (genre.isEmpty) continue;
      counts[genre] = (counts[genre] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList();
  }

  List<String> _topDecades({int limit = 3}) {
    final counts = <String, int>{};
    for (final album in _brainAlbums()) {
      final decade = album['decade'] ?? '';
      if (decade.isEmpty) continue;
      counts[decade] = (counts[decade] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return entries.take(limit).map((e) => e.key).toList();
  }

  List<Map<String, String>> _topArtists({int limit = 12}) {
    final counts = <String, int>{};
    for (final album in _brainAlbums()) {
      final artist = _cleanBrainValue(album['artist']);
      if (artist.isEmpty) continue;
      counts[artist] = (counts[artist] ?? 0) + 1;
    }

    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });

    return entries
        .take(limit)
        .map((e) => {'artist': e.key, 'count': e.value.toString()})
        .toList();
  }

  Future<void> _rebuildSmartHomeIndex() async {
    _libraryBrain.clear();
    _buildBasicLibraryBrain(save: false);

    for (final album in _albums) {
      final tracks = _albumTracksCache[album['id'] ?? ''];
      if (tracks != null && tracks.isNotEmpty) {
        _indexAlbumFromTracks(album, tracks, save: false);
      }
    }

    await _saveLibraryBrain();
    await _persistAlbums();
    if (mounted) setState(() {});
    _showSuccess('Smart Home index rebuilt from cached metadata.');
  }
}
