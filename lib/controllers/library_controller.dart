part of '../main.dart';

extension _LibraryControllerExtension on _MainScreenState {
  Future<void> _saveAlbumColorCache() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, List<String>>{};
    _albumColorCache.forEach((key, colors) {
      if (colors.length >= 4) {
        payload[key] = colors.take(4).map(_colorToHex).toList();
      }
    });
    await prefs.setString(_albumColorPrefsKey, json.encode(payload));
  }

  Future<void> _loadLibraryTrackIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_libraryTrackIndexKey);
      final rawExists = raw != null && raw.isNotEmpty;
      final rawLength = raw?.length ?? 0;

      debugPrint('LocalTrackRestore storageKey=$_libraryTrackIndexKey');
      debugPrint(
          'LocalTrackRestore storageLocation=prefs:$_libraryTrackIndexKey');
      debugPrint('LocalTrackRestore rawExists=$rawExists');
      debugPrint('LocalTrackRestore rawLength=$rawLength');

      if (raw == null || raw.isEmpty) {
        debugPrint('LocalTrackRestore decodedCount=0');
        debugPrint('LocalTrackRestore rejectedCount=0');
        return;
      }

      dynamic decoded;
      try {
        decoded = json.decode(raw);
      } catch (e) {
        debugPrint('LocalTrackRestore decodeError=$e');
        debugPrint(
            'LocalTrackRestore rawPreview=${raw.substring(0, math.min(500, raw.length))}');
        return;
      }
      if (decoded is Map) {
        var decodedCount = 0;
        var rejectedCount = 0;
        _libraryTrackIndex.clear();
        Map<String, String>? firstDecoded;
        decoded.forEach((key, value) {
          if (key is String && value is Map) {
            final record = Map<String, String>.from(value);
            if (record.isEmpty) {
              rejectedCount++;
              return;
            }
            final normalizedId = record['id']?.trim().isNotEmpty == true
                ? record['id']!.trim()
                : key.trim();
            if (normalizedId.isEmpty) {
              rejectedCount++;
              return;
            }
            record['id'] = normalizedId;
            _libraryTrackIndex[normalizedId] = record;
            firstDecoded ??= record;
            decodedCount++;
          } else {
            rejectedCount++;
          }
        });

        debugPrint('LocalTrackRestore decodedCount=$decodedCount');
        debugPrint('LocalTrackRestore rejectedCount=$rejectedCount');
        if (firstDecoded != null) {
          final decodedSample = firstDecoded!;
          debugPrint(
              'LocalTrackRestore firstDecoded albumKey=${decodedSample['albumId'] ?? decodedSample['albumKey'] ?? ''} title=${decodedSample['title'] ?? ''} uri=${decodedSample['localUri'] ?? ''} path=${decodedSample['localPath'] ?? decodedSample['path'] ?? ''} source=${decodedSample['source'] ?? ''}');
        }

        // Repair old records so Songs/Artists inherit current album covers and
        // durations without needing the album to be opened first.
        _repairLibraryTrackIndexFromAlbums();
        _queueArtistImagePrefetch();

        for (final entry in _libraryTrackIndex.entries) {
          final durationMs =
              _validDurationMsFromValue(entry.value['durationMs']);
          if (durationMs != null) {
            _setKnownTrackDuration(entry.key, durationMs);
          }
        }

        _invalidateLibraryBrowseCache();
        _queueArtistImagePrefetch();
      } else {
        debugPrint('LocalTrackRestore decodeError=decoded_not_map');
        debugPrint(
            'LocalTrackRestore rawPreview=${raw.substring(0, math.min(500, raw.length))}');
      }
    } catch (e) {
      debugPrint('LocalTrackRestore error=$e');
    }
  }

  Future<void> _saveLibraryTrackIndex(
      {bool logLocalPersistence = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = json.encode(_libraryTrackIndex);
      await prefs.setString(_libraryTrackIndexKey, raw);

      if (logLocalPersistence) {
        final localRecords = _libraryTrackIndex.values
            .where((record) => (record['source'] ?? '') == 'local')
            .toList();
        final storageKey = _libraryTrackIndexKey;
        debugPrint('LocalTrackPersist storageKey=$storageKey');
        debugPrint(
            'LocalTrackPersist storageLocation=prefs:$_libraryTrackIndexKey');
        debugPrint('LocalTrackPersist writeCount=${localRecords.length}');
        if (localRecords.isNotEmpty) {
          final first = localRecords.first;
          debugPrint(
              'LocalTrackPersist firstSaved albumKey=${first['albumId'] ?? first['albumKey'] ?? ''} title=${first['title'] ?? ''} uri=${first['localUri'] ?? ''} path=${first['localPath'] ?? first['path'] ?? ''} source=${first['source'] ?? ''}');
        }
        try {
          final persistedRaw = prefs.getString(_libraryTrackIndexKey) ?? '';
          var readBackCount = 0;
          if (persistedRaw.isNotEmpty) {
            final decoded = json.decode(persistedRaw);
            if (decoded is Map) {
              for (final entry in decoded.entries) {
                if (entry.key is String && entry.value is Map) {
                  final record = Map<String, dynamic>.from(entry.value as Map);
                  if ((record['source'] ?? '') == 'local') {
                    readBackCount++;
                  }
                }
              }
            }
          }
          debugPrint('LocalTrackPersist readBackCount=$readBackCount');
        } catch (e) {
          debugPrint('LocalTrackPersist readBackError=$e');
        }
      }
    } catch (_) {}
  }

  Future<void> _loadKnownTrackDurations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<dynamic, dynamic>? decoded;

      final raw = prefs.getString(_knownTrackDurationsKey);
      if (raw != null && raw.isNotEmpty) {
        final parsed = json.decode(raw);
        if (parsed is Map) decoded = parsed;
      }

      // Backward-compat migrations for older builds.
      if (decoded == null) {
        const legacyKeys = <String>[
          'known_track_durations',
          'known_track_durations_v1',
          'known_track_durations_ms_v1',
        ];
        for (final legacyKey in legacyKeys) {
          final legacyRaw = prefs.getString(legacyKey);
          if (legacyRaw == null || legacyRaw.isEmpty) continue;
          final parsed = json.decode(legacyRaw);
          if (parsed is Map) {
            decoded = parsed;
            break;
          }
        }
      }

      if (decoded == null) return;

      _knownTrackDurationsMs.clear();
      decoded.forEach((key, value) {
        if (key is! String) return;
        final durationMs = _validDurationMsFromValue(value) ??
            _validDurationMsFromValue(
              value is Map
                  ? (value['durationMs'] ??
                      value['inMilliseconds'] ??
                      value['milliseconds'] ??
                      value['duration'])
                  : null,
            );
        if (durationMs == null) return;
        _setKnownTrackDuration(key, durationMs);
      });

      final metadataChanged = _mergeCachedMetadataDurations();
      final repaired = _repairLibraryTrackIndexFromAlbums();
      if (repaired || metadataChanged) await _saveLibraryTrackIndex();
      if (metadataChanged) await _saveKnownTrackDurations();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveKnownTrackDurations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _knownTrackDurationsKey, json.encode(_knownTrackDurationsMs));
    } catch (_) {}
  }

  int? _validDurationMsFromValue(Object? value) {
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.toInt();
    } else if (value is String) {
      parsed = int.tryParse(value.trim());
    }

    if (parsed == null || parsed <= 0 || parsed >= 86400000) return null;
    return parsed;
  }

  void _setKnownTrackDuration(String trackId, int durationMs) {
    final valid = _validDurationMsFromValue(durationMs);
    if (trackId.trim().isEmpty || valid == null) return;

    _knownTrackDurationsMs[trackId] = valid;
    _knownTrackDurations[trackId] = Duration(milliseconds: valid);

    final record = _libraryTrackIndex[trackId];
    if (record != null) {
      record['durationMs'] = valid.toString();
    }
  }

  void _storeDurationForTrackId(
    String trackId,
    int durationMs, {
    bool persist = true,
    bool refreshVisibleAlbum = false,
  }) {
    final valid = _validDurationMsFromValue(durationMs);
    if (trackId.trim().isEmpty || valid == null) return;

    _setKnownTrackDuration(trackId, valid);

    if (persist) {
      unawaited(_saveKnownTrackDurations());
      unawaited(_saveLibraryTrackIndex());
    }

    if (refreshVisibleAlbum && mounted && _viewingAlbum != null) {
      setState(() {});
    }
  }

  void _cacheCurrentPlaybackDuration(Duration? duration) {
    final durationMs = _validDurationMsFromValue(duration?.inMilliseconds);
    if (durationMs == null) return;

    final current = _nowPlaying.track ?? _nowPlaying.currentTrack;
    if (current == null) return;

    final key = _trackKey(current);
    if (key.isEmpty) return;

    // During a track change just_audio can briefly re-emit the previous
    // source's duration after _nowPlaying has already been switched to the
    // next file. Only cache durations for the source that has finished
    // setAudioSource for the current track, otherwise album rows can show the
    // wrong length until the user taps the song again.
    if (_durationCacheTrackKey != key) return;

    final existingDurationMs = _knownTrackDurationsMs[key] ??
        _validDurationMsFromValue(_libraryTrackIndex[key]?['durationMs']);
    if (existingDurationMs != null &&
        existingDurationMs > 0 &&
        durationMs < (existingDurationMs * 0.85).round()) {
      return;
    }

    if (_knownTrackDurationsMs[key] == durationMs &&
        _libraryTrackIndex[key]?['durationMs'] == durationMs.toString()) {
      return;
    }

    _storeDurationForTrackId(
      key,
      durationMs,
      persist: true,
      refreshVisibleAlbum: true,
    );
    _invalidateLibraryBrowseCache();

    _verbosePlaybackLog(
        'Duration cached from player key=$key durationMs=$durationMs');
  }

  int? _durationMsFromTrackMetadata(drive.File file) {
    final meta = _metaStore.peekFresh(file) ?? _metaStore.peek(file);
    return _validDurationMsFromValue(meta?.durationMs);
  }

  int? _durationMsForTrack(drive.File file) {
    final trackId = _trackKey(file);
    if (trackId.isEmpty) return null;

    final fromMetadata = _durationMsFromTrackMetadata(file);
    final fromKnown =
        _validDurationMsFromValue(_knownTrackDurationsMs[trackId]);
    final fromIndex =
        _validDurationMsFromValue(_libraryTrackIndex[trackId]?['durationMs']);

    return fromMetadata ?? fromKnown ?? fromIndex;
  }

  List<drive.File> _tracksForAlbumKey(String albumKey) {
    final normalizedKey = _albumCacheKey(albumKey, source: 'album_tracks');
    final cachedTracks = _albumTracksCache[normalizedKey];
    if (cachedTracks != null && cachedTracks.isNotEmpty) {
      return _sortTracksForAlbum(cachedTracks);
    }

    if (_viewingAlbum != null &&
        _albumCacheKey(_viewingAlbum!, source: 'current_album') ==
            normalizedKey &&
        _albumTracks.isNotEmpty) {
      return _sortTracksForAlbum(_albumTracks);
    }

    return const <drive.File>[];
  }

  Map<String, String>? _brainForAlbum(Map<String, String> album) {
    final normalizedKey = _albumCacheKey(album, source: 'brain_lookup');
    final rawKey = (album['id'] ?? '').trim();
    return _libraryBrain[normalizedKey] ?? _libraryBrain[rawKey];
  }

  bool _isWeakAlbumDisplayTitle(String? value, {String? artist}) {
    final text = _cleanBrainValue(value);
    if (text.isEmpty) return true;
    final lower = text.toLowerCase().trim();
    if (RegExp(r'^disc\s*\d+([\s_-]*album)?$').hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'^cd\s*\d+([\s_-]*album)?$').hasMatch(lower)) {
      return true;
    }
    if (lower == 'album' || lower == 'unknown album') return true;

    final artistText = _cleanBrainValue(artist).toLowerCase();
    if (artistText.isNotEmpty) {
      final normalizedTitle =
          lower.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      final normalizedArtist =
          artistText.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      if (normalizedTitle == normalizedArtist ||
          normalizedTitle == '$normalizedArtist album') {
        return true;
      }
    }

    return false;
  }

  List<Map<String, String>> _trackRecordsForAlbumKey(String albumKey) {
    final normalizedKey =
        _albumCacheKey(albumKey, source: 'album_track_records');
    if (normalizedKey.isEmpty) return const <Map<String, String>>[];
    return _libraryTrackIndex.values
        .where((record) {
          final id = (record['albumId'] ?? record['albumKey'] ?? '').trim();
          if (id.isEmpty) return false;
          return id == normalizedKey ||
              _albumCacheKey(id, source: 'album_track_record_id') ==
                  normalizedKey;
        })
        .map((record) => Map<String, String>.from(record))
        .toList(growable: false);
  }

  String _mostCommonCleanValue(
    Iterable<String?> values, {
    bool Function(String value)? accept,
  }) {
    final counts = <String, int>{};
    final canonical = <String, String>{};
    for (final raw in values) {
      final value = _cleanBrainValue(raw);
      if (value.isEmpty) continue;
      if (accept != null && !accept(value)) continue;
      final key = value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      counts[key] = (counts[key] ?? 0) + 1;
      canonical.putIfAbsent(key, () => value);
    }
    if (counts.isEmpty) return '';
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return canonical[entries.first.key] ?? '';
  }

  String _albumTitleFromRecords(
    List<Map<String, String>> records, {
    String? fallbackArtist,
  }) {
    return _mostCommonCleanValue(
      records.map((record) => record['album']),
      accept: (value) =>
          !_isWeakAlbumDisplayTitle(value, artist: fallbackArtist),
    );
  }

  String _albumArtistFromRecords(List<Map<String, String>> records) {
    final albumArtist = _mostCommonCleanValue(
      records.map((record) => record['albumArtist']),
      accept: (value) => !_isBadArtistName(value),
    );
    if (albumArtist.isNotEmpty) return albumArtist;
    return _mostCommonCleanValue(
      records.map((record) => record['artist']),
      accept: (value) => !_isBadArtistName(value),
    );
  }

  String _albumCoverFromRecords(List<Map<String, String>> records) {
    return _mostCommonCleanValue(
      records.map((record) => record['albumCover']),
      accept: (value) => _sanitizeCoverSource(value).isNotEmpty,
    );
  }

  String _resolvedAlbumTitle(Map<String, String> album) {
    final key = _albumCacheKey(album, source: 'album_title');
    final brain = _brainForAlbum(album);
    final tracks = _tracksForAlbumKey(key);
    final records = _trackRecordsForAlbumKey(key);
    final artistHint = _firstNonEmptyString([
      _albumArtistFromRecords(records),
      _cleanBrainValue(brain?['artist']),
      _cleanBrainValue(album['artist']),
      if (tracks.isNotEmpty) _albumArtistFromTracks(tracks),
      _artistAlbumFromFolder(album['name'] ?? '')['artist'] ?? '',
    ]);

    final metadataTitle = _firstNonEmptyString([
      _albumTitleFromRecords(records, fallbackArtist: artistHint),
      if (tracks.isNotEmpty) _albumTitleFromTracks(tracks),
    ]);

    final savedTitle = _firstNonEmptyString([
      if (!_isWeakAlbumDisplayTitle(brain?['displayName'], artist: artistHint))
        _cleanBrainValue(brain?['displayName']),
      if (!_isWeakAlbumDisplayTitle(album['displayName'], artist: artistHint))
        _cleanBrainValue(album['displayName']),
      if (!_isWeakAlbumDisplayTitle(brain?['name'], artist: artistHint))
        _cleanBrainValue(brain?['name']),
      if (!_isWeakAlbumDisplayTitle(album['album'], artist: artistHint))
        _cleanBrainValue(album['album']),
      if (!_isWeakAlbumDisplayTitle(album['title'], artist: artistHint))
        _cleanBrainValue(album['title']),
      if (!_isWeakAlbumDisplayTitle(album['name'], artist: artistHint))
        _cleanBrainValue(album['name']),
    ]);

    final folderFallback = _cleanBackgroundValue(
      album['name'] ?? album['displayName'] ?? album['album'] ?? album['title'],
    );
    final value =
        _firstNonEmptyString([metadataTitle, savedTitle, folderFallback]);
    final titleSource = metadataTitle.isNotEmpty
        ? 'metadata'
        : savedTitle.isNotEmpty
            ? 'saved'
            : folderFallback.isNotEmpty
                ? 'folder_fallback'
                : 'none';
    final logKey = 'title|$key|$value|$titleSource';
    if (kAlbumDisplayDebug && _albumDisplayLogSeen.add(logKey)) {
      debugPrint(
          'AlbumDisplay resolved key=$key title="$value" artist="$artistHint" titleSource=$titleSource');
    }
    return value.isNotEmpty ? value : 'Album';
  }

  String _resolvedAlbumArtist(Map<String, String> album) {
    final key = _albumCacheKey(album, source: 'album_artist');
    final brain = _brainForAlbum(album);
    final tracks = _tracksForAlbumKey(key);
    final records = _trackRecordsForAlbumKey(key);

    final metadataArtist = _firstNonEmptyString([
      _albumArtistFromRecords(records),
      if (tracks.isNotEmpty) _albumArtistFromTracks(tracks),
    ]);

    final savedArtist = _firstNonEmptyString([
      if (!_isBadArtistName(_cleanBrainValue(brain?['artist'])))
        _cleanBrainValue(brain?['artist']),
      if (!_isBadArtistName(_cleanBrainValue(album['artist'])))
        _cleanBrainValue(album['artist']),
      if (!_isBadArtistName(
          _artistAlbumFromFolder(album['name'] ?? '')['artist'] ?? ''))
        _artistAlbumFromFolder(album['name'] ?? '')['artist'] ?? '',
    ]);

    final value = _firstNonEmptyString([metadataArtist, savedArtist]);
    final artistSource = metadataArtist.isNotEmpty
        ? 'metadata'
        : savedArtist.isNotEmpty
            ? 'saved'
            : 'none';
    final logKey = 'artist|$key|$value|$artistSource';
    if (kAlbumDisplayDebug && _albumDisplayLogSeen.add(logKey)) {
      debugPrint(
          'AlbumDisplay resolved key=$key artist="$value" artistSource=$artistSource');
    }
    return value.isNotEmpty ? value : 'Unknown Artist';
  }

  String _resolvedAlbumCover(Map<String, String> album) {
    final key = _albumCacheKey(album, source: 'album_cover');
    final brain = _brainForAlbum(album);
    final records = _trackRecordsForAlbumKey(key);

    final direct = _sanitizeCoverSource(
      album['cover'] ??
          album['coverUrl'] ??
          album['artwork'] ??
          brain?['cover'] ??
          brain?['coverUrl'] ??
          brain?['artwork'] ??
          '',
    );
    if (direct.isNotEmpty) {
      final logKey = 'cover|$key|$direct';
      if (kAlbumCoverDebug && _albumDisplayLogSeen.add(logKey)) {
        final directHasBytes =
            _isLocalCover(direct) ? File(direct).existsSync() : false;
        debugPrint(
            'AlbumCover lookup key=$key albumCoverBytes=$directHasBytes brainCoverBytes=$directHasBytes cacheCoverBytes=false');
        debugPrint(
            'AlbumCover key=$key source=album_or_brain hasBytes=$directHasBytes');
      }
      return direct;
    }

    final recordCover = _sanitizeCoverSource(_albumCoverFromRecords(records));
    if (recordCover.isNotEmpty) {
      final logKey = 'cover|$key|$recordCover';
      if (kAlbumCoverDebug && _albumDisplayLogSeen.add(logKey)) {
        debugPrint(
            'AlbumCover lookup key=$key albumCoverBytes=false brainCoverBytes=false cacheCoverBytes=true');
        debugPrint('AlbumCover key=$key source=track_index hasBytes=true');
      }
      return recordCover;
    }

    final tracks = _tracksForAlbumKey(key);
    for (final track in tracks) {
      final cached = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      final coverPath = _sanitizeCoverSource(cached?.coverPath);
      if (coverPath.isNotEmpty) {
        final logKey = 'cover|$key|$coverPath';
        if (kAlbumCoverDebug && _albumDisplayLogSeen.add(logKey)) {
          debugPrint(
              'AlbumCover lookup key=$key albumCoverBytes=false brainCoverBytes=false cacheCoverBytes=true');
          debugPrint('AlbumCover key=$key source=metadata hasBytes=true');
        }
        return coverPath;
      }
    }

    final logKey = 'cover|$key|none';
    if (kAlbumCoverDebug && _albumDisplayLogSeen.add(logKey)) {
      debugPrint(
          'AlbumCover lookup key=$key albumCoverBytes=false brainCoverBytes=false cacheCoverBytes=false');
      debugPrint('AlbumCover key=$key source=none hasBytes=false');
    }
    return '';
  }

  String _albumTitleFromTracks(List<drive.File> tracks) {
    final titles = <String>[];
    for (final track in tracks) {
      final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      final album = meta?.album?.trim() ?? '';
      if (album.isNotEmpty && !_isWeakAlbumDisplayTitle(album)) {
        titles.add(album);
      }
    }
    return _mostCommonCleanValue(titles);
  }

  String _albumArtistFromTracks(List<drive.File> tracks) {
    final artists = <String>[];
    for (final track in tracks) {
      final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      final artist = meta?.artist.trim() ?? '';
      if (artist.isNotEmpty && !_isBadArtistName(artist)) {
        artists.add(artist);
      }
    }
    return _mostCommonCleanValue(artists);
  }

  Map<String, String> _resolvedAlbumMap(Map<String, String> album) {
    final key = _albumCacheKey(album, source: 'album_map');
    final resolved = Map<String, String>.from(album);
    resolved['albumKey'] = key;
    if (resolved['id']?.trim().isNotEmpty == true) {
      resolved['id'] = key;
    } else {
      resolved['id'] = key;
    }
    resolved['displayName'] = _resolvedAlbumTitle(album);
    resolved['artist'] = _resolvedAlbumArtist(album);
    final cover = _resolvedAlbumCover(album);
    if (cover.isNotEmpty) {
      resolved['cover'] = cover;
      resolved['coverUrl'] = cover;
    }
    return resolved;
  }
}
