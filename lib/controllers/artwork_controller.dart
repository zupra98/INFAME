part of '../main.dart';

extension _ArtworkControllerExtension on _MainScreenState {
  Future<String?> _findEmbeddedCoverForAlbum(Map<String, String> album) async {
    final tracks = _tracksForAlbumArtwork(album);

    for (final track in tracks) {
      final cached = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      final cover = cached?.coverPath ?? '';
      if (cover.isNotEmpty) return cover;
    }

    if (_user == null || tracks.isEmpty) return null;

    try {
      final authHeaders = await _user!.authHeaders;
      final bearer =
          authHeaders['Authorization'] ?? authHeaders['authorization'] ?? '';
      if (!bearer.startsWith('Bearer ')) return null;
      final token = bearer.substring(7);

      for (final track in tracks.take(8)) {
        final result = await FastTagReader.read(file: track, token: token);
        final bytes = result?.coverBytes;
        if (bytes == null || bytes.isEmpty) continue;

        final saved = await _saveEmbeddedCover(track, bytes);
        if (saved == null || saved.isEmpty) continue;

        _applyEmbeddedCoverToAlbum(track, saved, albumRecord: album);
        return saved;
      }
    } catch (_) {}

    return null;
  }

  List<drive.File> _tracksForAlbumArtwork(Map<String, String> album) {
    final albumId = _albumCacheKey(album, source: 'album_artwork_tracks');
    final cachedTracks = _albumTracksCache[albumId];
    if (cachedTracks != null && cachedTracks.isNotEmpty) {
      return _sortTracksForAlbum(cachedTracks);
    }

    if (_viewingAlbum != null &&
        _albumCacheKey(_viewingAlbum!, source: 'album_artwork_tracks_view') ==
            albumId) {
      if (_albumTracks.isNotEmpty) return _sortTracksForAlbum(_albumTracks);
    }

    return const <drive.File>[];
  }

  String _albumArtworkLookupKey(Map<String, String> album) {
    final id = _albumCacheKey(album, source: 'album_artwork_key');
    if (id.isNotEmpty) return id;
    final title = _albumTitleForArtwork(album);
    final artist = _albumArtistForArtwork(album);
    return _safeArtworkFileName('$artist::$title');
  }

  String _albumArtworkLookupQuery(
    Map<String, String> album, {
    String? title,
    String? artist,
    String? year,
  }) {
    final albumName = (title ?? _albumTitleForArtwork(album)).trim();
    final artistName = (artist ?? _albumArtistForArtwork(album)).trim();
    final albumYear = (year ?? _albumYearForArtwork(album)).trim();
    final parts = <String>[
      if (artistName.isNotEmpty && artistName != 'Unknown Artist') artistName,
      if (albumName.isNotEmpty) albumName,
      if (albumYear.isNotEmpty) albumYear,
      'album cover',
    ];
    return parts.join(' ').trim();
  }

  bool _albumArtworkMatchesCandidate({
    required String albumName,
    required String artistName,
    required _ArtworkCandidate candidate,
  }) {
    final wantedAlbum = _normalizeArtworkMatch(albumName);
    final wantedArtist = _normalizeArtworkMatch(artistName);
    final candAlbum = _normalizeArtworkMatch(candidate.title);
    final candArtist = _normalizeArtworkMatch(candidate.artist);

    if (wantedAlbum.isEmpty || candAlbum.isEmpty) return false;
    final albumMatch = wantedAlbum == candAlbum ||
        candAlbum.contains(wantedAlbum) ||
        wantedAlbum.contains(candAlbum);
    if (!albumMatch) return false;

    if (wantedArtist.isNotEmpty && wantedArtist != 'unknown artist') {
      if (candArtist.isEmpty) return false;
      final artistMatch = wantedArtist == candArtist ||
          candArtist.contains(wantedArtist) ||
          wantedArtist.contains(candArtist);
      if (!artistMatch) return false;
    }

    return candidate.confidence >= 0.72;
  }

  Future<_ArtworkCandidate?> _fetchCoverArtCandidate(
    Map<String, String> album, {
    String? title,
    String? artist,
    String? year,
  }) async {
    final albumName = (title ?? _albumTitleForArtwork(album)).trim();
    final artistName = (artist ?? _albumArtistForArtwork(album)).trim();
    final albumYear = (year ?? _albumYearForArtwork(album)).trim();
    if (albumName.isEmpty) return null;

    final candidates = <_ArtworkCandidate>[];
    try {
      candidates.addAll(
        await _searchTheAudioDbArtworkCandidates(
            albumName, artistName, albumYear),
      );
    } catch (_) {}
    try {
      candidates.addAll(
        await _searchITunesArtworkCandidates(albumName, artistName, albumYear),
      );
    } catch (_) {}
    try {
      candidates.addAll(
        await _searchMusicBrainzArtworkCandidates(
          albumName,
          artistName,
          albumYear,
        ),
      );
    } catch (_) {}

    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    for (final candidate in candidates) {
      if (_albumArtworkMatchesCandidate(
        albumName: albumName,
        artistName: artistName,
        candidate: candidate,
      )) {
        return candidate;
      }
    }

    return null;
  }

  Future<void> _findCoversForAllAlbums() async {
    if (_user == null || _albums.isEmpty) {
      _showError('Please sign in first.');
      return;
    }

    _showSuccess('Starting cover search for ${_albums.length} albums...');
    int found = 0;
    int failed = 0;
    final usedRemoteUrls = <String, String>{};
    final coverUsage = <String, Set<String>>{};
    for (final existingAlbum in _albums) {
      final existingCover = _albumCoverForIndex(existingAlbum).trim();
      if (existingCover.isEmpty) continue;
      final signature =
          '${_normalizeArtworkMatch(_albumTitleForArtwork(existingAlbum))}::${_normalizeArtworkMatch(_albumArtistForArtwork(existingAlbum))}';
      coverUsage.putIfAbsent(existingCover, () => <String>{}).add(signature);
    }
    final suspiciousCovers = coverUsage.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => entry.key)
        .toSet();

    for (final album in _albums) {
      final albumName = _albumTitleForArtwork(album);
      final artist = _albumArtistForArtwork(album);
      final year = _albumYearForArtwork(album);
      final albumKey = _albumArtworkLookupKey(album);
      final query = _albumArtworkLookupQuery(
        album,
        title: albumName,
        artist: artist,
        year: year,
      );

      _verboseScanLog('Cover lookup albumKey=$albumKey');
      _verboseScanLog('Cover lookup query=$query');

      final existingCover = _albumCoverForIndex(album).trim();
      if (existingCover.isNotEmpty &&
          !suspiciousCovers.contains(existingCover)) {
        _verboseScanLog('Cover skipped album=$albumKey reason=existing_cover');
        continue;
      } else if (existingCover.isNotEmpty) {
        _verboseScanLog(
            'Cover lookup albumKey=$albumKey reason=suspicious_existing_cover');
      }

      final embedded = await _findEmbeddedCoverForAlbum(album);
      if (embedded != null && embedded.isNotEmpty) {
        album['cover'] = embedded;
        found++;
        _verboseScanLog(
            'Cover accepted album=$albumKey url=$embedded source=embedded');
        await _extractAlbumColors(embedded, albumName);
        continue;
      }

      final candidate = await _fetchCoverArtCandidate(
        album,
        title: albumName,
        artist: artist,
        year: year,
      );
      if (candidate != null && candidate.imageUrl.isNotEmpty) {
        final remoteUrl = candidate.imageUrl;
        final normalizedAlbum =
            '${_normalizeArtworkMatch(albumName)}::${_normalizeArtworkMatch(artist)}';
        final existingAlbum = usedRemoteUrls[remoteUrl];
        if (existingAlbum != null && existingAlbum != normalizedAlbum) {
          _verboseScanLog(
              'Cover rejected album=$albumKey reason=duplicate_remote_url');
          failed++;
          continue;
        }
        usedRemoteUrls[remoteUrl] = normalizedAlbum;
        album['cover'] = remoteUrl;
        found++;
        _verboseScanLog(
            'Cover accepted album=$albumKey url=$remoteUrl source=${candidate.source}');
        await _extractAlbumColors(remoteUrl, albumName);
      } else {
        _verboseScanLog(
            'Cover skipped album=$albumKey reason=no_confident_match');
        failed++;
      }
    }

    await _persistAlbums();
    _showSuccess('Cover search complete: $found found, $failed failed.');
  }

  String _albumTitleForArtwork(Map<String, String> album) {
    return _resolvedAlbumTitle(album);
  }

  String _albumArtistForArtwork(Map<String, String> album) {
    return _resolvedAlbumArtist(album);
  }

  String _albumYearForArtwork(Map<String, String> album) {
    final id = _albumCacheKey(album, source: 'album_artwork_year');
    final brain = _libraryBrain[id] ?? const <String, String>{};
    return (brain['year'] ?? album['year'] ?? '').trim();
  }

  Future<List<_ArtworkCandidate>> _searchITunesArtworkCandidates(
    String albumName,
    String artistName,
    String year,
  ) async {
    final cleanAlbum = _cleanCoverSearchTerm(albumName);
    final cleanArtist = _coverSearchAlias(_cleanCoverSearchTerm(artistName));
    final term = [cleanArtist, cleanAlbum]
        .where((v) => v.trim().isNotEmpty && v != 'Unknown Artist')
        .join(' ');
    if (term.trim().isEmpty) return const <_ArtworkCandidate>[];

    final url = Uri.parse(
      'https://itunes.apple.com/search?term=${Uri.encodeComponent(term)}&entity=album&limit=18',
    );
    final res = await http.get(url, headers: {'User-Agent': 'InfameApp/1.0'});
    if (res.statusCode != 200) return const <_ArtworkCandidate>[];

    final data = json.decode(res.body);
    final results = data['results'];
    if (results is! List) return const <_ArtworkCandidate>[];

    final candidates = <_ArtworkCandidate>[];
    for (final item in results) {
      if (item is! Map) continue;
      final artwork = item['artworkUrl100'];
      if (artwork is! String || artwork.isEmpty) continue;
      final title = (item['collectionName'] ?? '').toString();
      final artist = (item['artistName'] ?? '').toString();
      final releaseDate = (item['releaseDate'] ?? '').toString();
      final full = artwork
          .replaceAll('100x100bb.jpg', '1200x1200bb.jpg')
          .replaceAll('100x100bb.png', '1200x1200bb.png');
      candidates.add(
        _ArtworkCandidate(
          source: 'iTunes',
          title: title.isEmpty ? albumName : title,
          artist: artist.isEmpty ? artistName : artist,
          year: releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '',
          imageUrl: full,
          thumbnailUrl: artwork,
          confidence: _artworkConfidence(
            wantedAlbum: albumName,
            wantedArtist: artistName,
            wantedYear: year,
            candidateAlbum: title,
            candidateArtist: artist,
            candidateYear: releaseDate,
          ),
        ),
      );
    }
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    return candidates.take(12).toList();
  }

  Future<List<_ArtworkCandidate>> _searchTheAudioDbArtworkCandidates(
    String albumName,
    String artistName,
    String year,
  ) async {
    final cleanAlbum = _cleanCoverSearchTerm(albumName);
    final cleanArtist = _coverSearchAlias(_cleanCoverSearchTerm(artistName));
    if (cleanAlbum.isEmpty ||
        cleanArtist.isEmpty ||
        cleanArtist == 'Unknown Artist') {
      return const <_ArtworkCandidate>[];
    }

    final url = Uri.parse(
      'https://www.theaudiodb.com/api/v1/json/2/searchalbum.php?s=${Uri.encodeComponent(cleanArtist)}&a=${Uri.encodeComponent(cleanAlbum)}',
    );
    final res = await http.get(url, headers: {'User-Agent': 'InfameApp/1.0'});
    if (res.statusCode != 200) return const <_ArtworkCandidate>[];

    final data = json.decode(res.body);
    final albums = data['album'];
    if (albums is! List) return const <_ArtworkCandidate>[];

    final candidates = <_ArtworkCandidate>[];
    for (final item in albums) {
      if (item is! Map) continue;
      final image =
          (item['strAlbumThumb'] ?? item['strAlbumCDart'] ?? '').toString();
      if (image.isEmpty) continue;
      final title = (item['strAlbum'] ?? '').toString();
      final artist = (item['strArtist'] ?? '').toString();
      final released = (item['intYearReleased'] ?? '').toString();
      candidates.add(
        _ArtworkCandidate(
          source: 'TheAudioDB',
          title: title.isEmpty ? albumName : title,
          artist: artist.isEmpty ? artistName : artist,
          year: released,
          imageUrl: image,
          thumbnailUrl: image,
          confidence: _artworkConfidence(
            wantedAlbum: albumName,
            wantedArtist: artistName,
            wantedYear: year,
            candidateAlbum: title,
            candidateArtist: artist,
            candidateYear: released,
          ),
        ),
      );
    }
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    return candidates.take(12).toList();
  }

  Future<List<_ArtworkCandidate>> _searchMusicBrainzArtworkCandidates(
    String albumName,
    String artistName,
    String year,
  ) async {
    final cleanAlbum = _cleanCoverSearchTerm(albumName);
    final cleanArtist = _coverSearchAlias(_cleanCoverSearchTerm(artistName));
    final queries = <String>[
      if (cleanArtist.isNotEmpty && cleanArtist != 'Unknown Artist')
        'releasegroup:"$cleanAlbum" AND artist:"$cleanArtist"',
      if (cleanArtist.isNotEmpty && cleanArtist != 'Unknown Artist')
        '$cleanAlbum $cleanArtist',
      cleanAlbum,
    ];
    final candidates = <_ArtworkCandidate>[];
    final seen = <String>{};

    for (final query in queries) {
      if (query.trim().isEmpty || seen.contains(query)) continue;
      seen.add(query);
      final mbUrl = Uri.parse(
        'https://musicbrainz.org/ws/2/release-group/?query=${Uri.encodeComponent(query)}&fmt=json&limit=10',
      );
      final mbRes = await http.get(
        mbUrl,
        headers: {'User-Agent': 'InfameApp/1.0 (artwork source picker)'},
      );
      if (mbRes.statusCode != 200) continue;

      final data = json.decode(mbRes.body);
      final groups = data['release-groups'];
      if (groups is! List) continue;

      for (final group in groups.take(8)) {
        if (group is! Map) continue;
        final mbid = (group['id'] ?? '').toString();
        if (mbid.isEmpty) continue;
        final title = (group['title'] ?? '').toString();
        final firstDate = (group['first-release-date'] ?? '').toString();
        var artist = artistName;
        final credits = group['artist-credit'];
        if (credits is List && credits.isNotEmpty && credits.first is Map) {
          artist = ((credits.first as Map)['name'] ?? artistName).toString();
        }

        // Keep MusicBrainz gentle; this is only run after the user taps the source.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final caaUrl =
            Uri.parse('https://coverartarchive.org/release-group/$mbid');
        final caaRes =
            await http.get(caaUrl, headers: {'Accept': 'application/json'});
        if (caaRes.statusCode != 200) continue;

        final caaData = json.decode(caaRes.body);
        final images = caaData['images'];
        if (images is! List || images.isEmpty) continue;
        for (final img in images.take(3)) {
          if (img is! Map) continue;
          if (img['front'] != true && candidates.isNotEmpty) continue;
          final thumbnails = img['thumbnails'];
          final full = (img['image'] ?? '').toString();
          final thumb = thumbnails is Map
              ? (thumbnails['500'] ??
                      thumbnails['250'] ??
                      thumbnails['small'] ??
                      full)
                  .toString()
              : full;
          if (full.isEmpty) continue;
          candidates.add(
            _ArtworkCandidate(
              source: 'MusicBrainz',
              title: title.isEmpty ? albumName : title,
              artist: artist.isEmpty ? artistName : artist,
              year: firstDate.length >= 4 ? firstDate.substring(0, 4) : '',
              imageUrl: full,
              thumbnailUrl: thumb.isEmpty ? full : thumb,
              confidence: _artworkConfidence(
                wantedAlbum: albumName,
                wantedArtist: artistName,
                wantedYear: year,
                candidateAlbum: title,
                candidateArtist: artist,
                candidateYear: firstDate,
              ),
            ),
          );
          break;
        }
      }
      if (candidates.isNotEmpty) break;
    }

    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    return candidates.take(12).toList();
  }
}
