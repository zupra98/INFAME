part of '../main.dart';

extension _ArtistControllerExtension on _MainScreenState {
  String _normalizeArtistText(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _artistImageCacheKey(String artistName) {
    return _normalizeArtistText(artistName).toLowerCase();
  }

  bool _isBadArtistName(String value) {
    final text = _normalizeArtistText(value);
    if (text.isEmpty) return true;

    final lower = text.toLowerCase();
    if (lower == 'unknown' ||
        lower == 'unknown artist' ||
        lower == 'various artists' ||
        lower == 'various artist' ||
        lower == 'miscellaneous') {
      return true;
    }

    if (text.length > 80) return true;
    return false;
  }

  String _stripFeaturedArtistSuffix(String value) {
    final text = _normalizeArtistText(value);
    if (text.isEmpty) return '';

    final match = RegExp(
      r'^(.*?)\s+(?:feat\.?|ft\.?|featuring|with)\s+.+$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      final cleaned = _normalizeArtistText(match.group(1) ?? '');
      if (cleaned.isNotEmpty) return cleaned;
    }

    return text;
  }

  String _canonicalArtistName({
    String? albumArtist,
    String? trackArtist,
    String? albumName,
  }) {
    final albumCandidate = _normalizeArtistText(albumArtist ?? '');
    if (albumCandidate.isNotEmpty && !_isBadArtistName(albumCandidate)) {
      final cleaned = _stripFeaturedArtistSuffix(albumCandidate);
      if (cleaned.isNotEmpty && !_isBadArtistName(cleaned)) return cleaned;
      return albumCandidate;
    }

    final folderGuess = _artistAlbumFromFolder(albumName ?? '')['artist'] ?? '';
    if (folderGuess.isNotEmpty && !_isBadArtistName(folderGuess)) {
      final cleaned = _stripFeaturedArtistSuffix(folderGuess);
      if (cleaned.isNotEmpty && !_isBadArtistName(cleaned)) return cleaned;
      return folderGuess;
    }

    final trackCandidate = _normalizeArtistText(trackArtist ?? '');
    if (trackCandidate.isEmpty || _isBadArtistName(trackCandidate)) return '';
    final cleaned = _stripFeaturedArtistSuffix(trackCandidate);
    return cleaned.isNotEmpty ? cleaned : trackCandidate;
  }

  String _artistSearchTextForRecord(Map<String, String> record) {
    final albumId = record['albumId'] ?? '';
    final brain = albumId.isNotEmpty ? _libraryBrain[albumId] : null;
    final canonical = _canonicalArtistName(
      albumArtist: record['albumArtist'] ?? brain?['artist'] ?? '',
      trackArtist: record['artist'] ?? '',
      albumName: record['albumName'] ?? brain?['displayName'] ?? '',
    );

    return [
      canonical,
      record['artist'] ?? '',
      record['albumArtist'] ?? '',
      record['albumName'] ?? '',
      record['album'] ?? '',
      record['name'] ?? '',
      record['title'] ?? '',
      brain?['artist'] ?? '',
      brain?['displayName'] ?? '',
    ].join(' ').toLowerCase();
  }

  List<String> _canonicalArtistNamesFromLibrary() {
    final names = <String>{};
    for (final record in _libraryTrackIndex.values) {
      final albumId = record['albumId'] ?? '';
      final brain = albumId.isNotEmpty ? _libraryBrain[albumId] : null;
      final canonical = _canonicalArtistName(
        albumArtist: record['albumArtist'] ?? brain?['artist'] ?? '',
        trackArtist: record['artist'] ?? '',
        albumName: record['albumName'] ?? brain?['displayName'] ?? '',
      );
      if (canonical.isNotEmpty) names.add(canonical);
    }

    final list = names.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<void> _loadArtistImageCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawCache = prefs.getString(_artistImageCachePrefsKey);
      final rawFailures = prefs.getString(_artistImageFailurePrefsKey);

      final nextCache = <String, String>{};
      if (rawCache != null && rawCache.isNotEmpty) {
        final decoded = json.decode(rawCache);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is String && value is String) {
              final trimmedKey = key.trim();
              final trimmedValue = value.trim();
              if (trimmedKey.isNotEmpty && trimmedValue.isNotEmpty) {
                nextCache[trimmedKey] = trimmedValue;
              }
            }
          });
        }
      }

      final nextFailures = <String, int>{};
      if (rawFailures != null && rawFailures.isNotEmpty) {
        final decoded = json.decode(rawFailures);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is! String) return;
            final until = int.tryParse(value.toString());
            if (until != null && until > 0) {
              nextFailures[key.trim()] = until;
            }
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _artistImageCache
          ..clear()
          ..addAll(nextCache);
        _artistImageFailureCooldown
          ..clear()
          ..addAll(nextFailures);
      });
      _queueArtistImagePrefetch();
    } catch (_) {}
  }

  Future<void> _saveArtistImageCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _artistImageCachePrefsKey,
        json.encode(_artistImageCache),
      );
      await prefs.setString(
        _artistImageFailurePrefsKey,
        json.encode(_artistImageFailureCooldown),
      );
    } catch (_) {}
  }

  bool _artistImageLookupOnCooldown(String artistName) {
    final key = _artistImageCacheKey(artistName);
    final until = _artistImageFailureCooldown[key] ?? 0;
    return until > DateTime.now().millisecondsSinceEpoch;
  }

  void _markArtistImageLookupFailed(String artistName) {
    final key = _artistImageCacheKey(artistName);
    if (key.isEmpty) return;
    _artistImageFailureCooldown[key] =
        DateTime.now().add(const Duration(hours: 12)).millisecondsSinceEpoch;
  }

  void _markArtistImageLookupSucceeded(String artistName, String imageUrl) {
    final key = _artistImageCacheKey(artistName);
    if (key.isEmpty) return;
    _artistImageCache[key] = imageUrl;
    _artistImageFailureCooldown.remove(key);
  }

  Future<String?> _fetchArtistImageUrl(String artistName) async {
    final trimmed = _normalizeArtistText(artistName);
    if (trimmed.isEmpty || _isBadArtistName(trimmed)) return null;

    final query = Uri.encodeComponent(trimmed);
    final uris = <Uri>[
      Uri.parse(
        'https://www.theaudiodb.com/api/v2/json/search/artist/$query',
      ),
      Uri.parse(
        'https://www.theaudiodb.com/api/v1/json/2/search.php?s=$query',
      ),
    ];

    String? chooseUrl(Map item) {
      final candidates = [
        item['strArtistThumb'],
        item['strArtistLogo'],
        item['strArtistCutOut'],
        item['strArtistWideThumb'],
        item['strArtistBanner'],
        item['strArtistFanart1'],
      ];
      for (final candidate in candidates) {
        final value = candidate?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return null;
    }

    for (final uri in uris) {
      try {
        final response =
            await http.get(uri).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;

        final decoded = json.decode(response.body);
        if (decoded is! Map) continue;

        final data = decoded['data'] ?? decoded['artists'];
        if (data is! List || data.isEmpty) continue;

        for (final item in data) {
          if (item is! Map) continue;
          final imageUrl = chooseUrl(item);
          if (imageUrl != null && imageUrl.isNotEmpty) return imageUrl;
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  Future<void> _ensureArtistImageCached(String artistName) async {
    final normalized = _normalizeArtistText(artistName);
    if (normalized.isEmpty || _isBadArtistName(normalized)) return;

    final cacheKey = _artistImageCacheKey(normalized);
    if (cacheKey.isEmpty) return;
    if (_artistImageCache.containsKey(cacheKey)) return;
    if (_artistImageFetchInFlight.contains(cacheKey)) return;
    if (_artistImageLookupOnCooldown(normalized)) return;

    _artistImageFetchInFlight.add(cacheKey);
    try {
      final imageUrl = await _fetchArtistImageUrl(normalized);
      if (!mounted) return;

      setState(() {
        if (imageUrl != null && imageUrl.isNotEmpty) {
          _markArtistImageLookupSucceeded(normalized, imageUrl);
        } else {
          _markArtistImageLookupFailed(normalized);
        }
      });
      await _saveArtistImageCache();
    } catch (_) {
      if (mounted) {
        setState(() => _markArtistImageLookupFailed(normalized));
        await _saveArtistImageCache();
      }
    } finally {
      _artistImageFetchInFlight.remove(cacheKey);
    }
  }

  void _queueArtistImagePrefetch() {
    if (_artistImagePrefetchRunning) return;
    if (_libraryTrackIndex.isEmpty) return;
    _artistImagePrefetchRunning = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _artistImagePrefetchRunning = false;
        return;
      }
      unawaited(_prefetchArtistImages());
    });
  }

  Future<void> _prefetchArtistImages() async {
    try {
      final artists = _canonicalArtistNamesFromLibrary();
      final missing = artists
          .where((artist) {
            final key = _artistImageCacheKey(artist);
            return key.isNotEmpty &&
                !_artistImageCache.containsKey(key) &&
                !_artistImageLookupOnCooldown(artist);
          })
          .take(24)
          .toList();

      for (final artist in missing) {
        if (!mounted) break;
        await _ensureArtistImageCached(artist);
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    } finally {
      _artistImagePrefetchRunning = false;
    }
  }

  bool _isTrackLiked(drive.File file) {
    final key = _trackKey(file);
    return key.isNotEmpty && _likedTrackKeys.contains(key);
  }

  void _toggleLikedTrack(drive.File file) {
    final key = _trackKey(file);
    if (key.isEmpty) return;

    final liked = !_likedTrackKeys.contains(key);
    setState(() {
      if (liked) {
        _likedTrackKeys.add(key);
      } else {
        _likedTrackKeys.remove(key);
      }
      _likedTracksVersion++;
    });
    _invalidateLibraryBrowseCache();
    _saveLikedTracks();
    _nowPlaying.refresh();
    _showSuccess(liked ? 'Added to liked songs' : 'Removed from liked songs');
  }
}
