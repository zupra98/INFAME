part of '../main.dart';

extension _DriveLibraryControllerExtension on _MainScreenState {
  Future<void> _shuffleLibrary() async {
    if (_user == null || _albums.isEmpty) return;

    try {
      final authHeaders = await _user!.authHeaders;
      final api = drive.DriveApi(GoogleAuthClient(authHeaders));
      final random = math.Random();
      final albums = List<Map<String, String>>.from(_albums)..shuffle(random);

      for (final album in albums) {
        final tracks = await _fetchTracksForAlbumRecord(api, album);
        if (tracks.isEmpty) continue;

        final trackIndex = random.nextInt(tracks.length);
        final coverUrl = album['cover'];
        final colors = coverUrl != null && coverUrl.isNotEmpty
            ? getAlbumGradient(album['name'] ?? '')
            : getAlbumGradient(album['name'] ?? '');

        await _playSong(
          tracks[trackIndex],
          queue: tracks,
          idx: trackIndex,
          coverUrl: coverUrl,
          colors: colors,
        );
        return;
      }

      _showError('No playable tracks found in your library.');
    } catch (e) {
      _showError('Could not shuffle library: $e');
    }
  }

  Future<void> _clearLibrary() async {
    await _clearLibraryCacheSafely();
  }

  void _showSuccess(String msg) => _showSuccessFromPart(msg);

  // â”€â”€ Cover Art Fetcher â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // â”€â”€ Cover Art Fetcher â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String _coverSearchAlias(String value) {
    final cleaned = value.trim();
    final lower = cleaned.toLowerCase();
    if (lower == 'clips') return 'Clipse';
    if (lower == r'a$ap rocky' || lower == 'asap rocky') return r'A$AP Rocky';
    if (lower == 'mf doom' || lower == 'madvillain') return cleaned;
    return cleaned;
  }

  String _cleanCoverSearchTerm(String value) {
    var cleaned = value
        .replaceAll(RegExp(r'\[.*?\]|\(.*?\)'), '')
        .replaceAll(RegExp(r'\b(19|20)\d{2}\b'), '')
        .replaceAll(
            RegExp(
                r'\b(deluxe|expanded|explicit|clean|remaster(ed)?|anniversary|edition|version)\b',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? value.trim() : cleaned;
  }

  Future<String?> _coverFromCoverArtArchive(
      String albumName, String artistName) async {
    final cleanAlbum = _cleanCoverSearchTerm(albumName);
    final cleanArtist = _coverSearchAlias(_cleanCoverSearchTerm(artistName));

    final queries = <String>[
      if (cleanArtist.isNotEmpty && cleanArtist != 'Unknown Artist')
        'releasegroup:"$cleanAlbum" AND artist:"$cleanArtist"',
      if (cleanArtist.isNotEmpty && cleanArtist != 'Unknown Artist')
        '$cleanAlbum $cleanArtist',
      cleanAlbum,
    ];

    final seen = <String>{};

    for (final query in queries) {
      if (query.trim().isEmpty || seen.contains(query)) continue;
      seen.add(query);

      final mbUrl = Uri.parse(
        'https://musicbrainz.org/ws/2/release-group/?query=${Uri.encodeComponent(query)}&fmt=json&limit=8',
      );

      final mbRes = await http.get(
        mbUrl,
        headers: {'User-Agent': 'InfameApp/1.0 (cover lookup)'},
      );

      if (mbRes.statusCode != 200) continue;

      final data = json.decode(mbRes.body);
      final groups = data['release-groups'];
      if (groups is! List || groups.isEmpty) continue;

      for (final group in groups.take(6)) {
        final mbid = group['id'];
        if (mbid == null) continue;

        final caaUrl =
            Uri.parse('https://coverartarchive.org/release-group/$mbid');
        final caaRes =
            await http.get(caaUrl, headers: {'Accept': 'application/json'});
        if (caaRes.statusCode != 200) continue;

        final caaData = json.decode(caaRes.body);
        final images = caaData['images'];
        if (images is! List || images.isEmpty) continue;

        final front = images.cast<dynamic>().firstWhere(
              (img) => img is Map && img['front'] == true,
              orElse: () => images.first,
            );
        if (front is Map) {
          final thumbnails = front['thumbnails'];
          final image = thumbnails is Map
              ? (thumbnails['large'] ??
                  thumbnails['500'] ??
                  thumbnails['250'] ??
                  front['image'])
              : front['image'];
          if (image is String && image.isNotEmpty) return image;
        }
      }
    }

    return null;
  }

  Future<String?> _coverFromITunes(String albumName, String artistName) async {
    final cleanAlbum = _cleanCoverSearchTerm(albumName);
    final cleanArtist = _coverSearchAlias(_cleanCoverSearchTerm(artistName));
    final term = [cleanArtist, cleanAlbum]
        .where((v) => v.trim().isNotEmpty && v != 'Unknown Artist')
        .join(' ');
    if (term.trim().isEmpty) return null;

    final url = Uri.parse(
      'https://itunes.apple.com/search?term=${Uri.encodeComponent(term)}&entity=album&limit=10',
    );

    final res = await http.get(url, headers: {'User-Agent': 'InfameApp/1.0'});
    if (res.statusCode != 200) return null;

    final data = json.decode(res.body);
    final results = data['results'];
    if (results is! List || results.isEmpty) return null;

    for (final item in results) {
      if (item is! Map) continue;
      final artwork = item['artworkUrl100'];
      if (artwork is String && artwork.isNotEmpty) {
        return artwork
            .replaceAll('100x100bb.jpg', '1200x1200bb.jpg')
            .replaceAll('100x100bb.png', '1200x1200bb.png');
      }
    }
    return null;
  }

  Future<String?> _fetchCoverArt(String albumName, String artistName) async {
    try {
      final candidate = await _fetchCoverArtCandidate(
        <String, String>{'name': albumName, 'artist': artistName},
        title: albumName,
        artist: artistName,
      );
      if (candidate != null && candidate.imageUrl.isNotEmpty) {
        return candidate.imageUrl;
      }
    } catch (_) {}

    return null;
  }

  // â”€â”€ Library Scanner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _scanFolderToLibrary(drive.File rootFolder) async {
    if (_user == null || DriveUtils.effectiveId(rootFolder) == null) return;

    debugPrint('scan started');
    debugPrint('[DriveScan] scan started for folder: ${rootFolder.name}');
    setState(() => _isScanning = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Scanning Drive and building album covers...',
          style: GoogleFonts.inter(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: _pink,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );

    try {
      final headers = await _user!.authHeaders;
      final api = drive.DriveApi(GoogleAuthClient(headers));

      final Map<String, Map<String, String>> discoveredMap = {};

      await _crawlDirectory(
        api,
        DriveUtils.effectiveId(rootFolder)!,
        rootFolder.name ?? 'Unknown',
        discoveredMap,
      );

      final discovered = discoveredMap.values.toList();

      if (!mounted) return;

      if (discovered.isEmpty) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No audio files found.',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final uniqueAlbums = <String, Map<String, String>>{};
      for (final a in _albums) {
        uniqueAlbums[a['id']!] = a;
      }
      for (final a in discovered) {
        final id = a['id']!;
        final existing = uniqueAlbums[id];
        if (existing != null) {
          a['dateAdded'] = existing['dateAdded'] ??
              a['dateAdded'] ??
              DateTime.now().millisecondsSinceEpoch.toString();
          if ((a['cover'] ?? '').isEmpty &&
              (existing['cover'] ?? '').isNotEmpty) {
            a['cover'] = existing['cover']!;
          }
        }
        uniqueAlbums[id] = a;
      }

      setState(() {
        _albums = uniqueAlbums.values.toList()
          ..forEach((album) {
            final normalizedId = _albumCacheKey(album, source: 'scan_album');
            if (normalizedId.isNotEmpty) {
              album['id'] = normalizedId;
              album['albumKey'] = normalizedId;
            }
          })
          ..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
        _librarySearchTextCache.clear();
        _shuffledExploreAlbums = (List<Map<String, String>>.from(_albums)
              ..shuffle())
            .take(14)
            .toList();
        _albumTracksCache.clear();
        _isScanning = false;
      });

      _buildBasicLibraryBrain(save: false);
      await _persistAlbums();
      await _saveLibraryBrain();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Scan complete! Found ${discovered.length} albums.',
            style: GoogleFonts.inter(
                color: Colors.black, fontWeight: FontWeight.w800),
          ),
          backgroundColor: _accentDefault,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (e.toString().contains('401')) {
        _showError('Session expired. Sign out and sign back in.');
      } else {
        _showError('Scan failed: $e');
      }

      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _crawlDirectory(
    drive.DriveApi api,
    String folderId,
    String folderName,
    Map<String, Map<String, String>> discovered,
  ) async {
    String? pageToken;
    bool containsAudio = false;
    String? localCoverUrl;
    String? firstArtistFound;
    final List<drive.File> subFolders = [];

    do {
      final res = await api.files.list(
        q: "'$folderId' in parents and trashed = false",
        $fields:
            'files(id,name,mimeType,thumbnailLink,shortcutDetails(targetId,targetMimeType)),nextPageToken',
        pageSize: 100,
        pageToken: pageToken,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );

      final files = res.files ?? <drive.File>[];

      for (final f in files) {
        if (DriveUtils.isAudio(f)) {
          containsAudio = true;
          firstArtistFound ??= DriveUtils.getTrackMeta(f)['artist'];
        } else if (DriveUtils.isFolder(f)) {
          subFolders.add(f);
        } else if (DriveUtils.effectiveMimeType(f)?.startsWith('image/') ==
            true) {
          localCoverUrl ??= f.thumbnailLink;
        }
      }

      pageToken = res.nextPageToken;
    } while (pageToken != null);

    if (containsAudio) {
      final baseAlbumName = folderName
          .replaceAll(
            RegExp(
              r'[\s\-\(\[\]]*(disc|cd)\.?\s*\d+[\s\-\)\[\]]*',
              caseSensitive: false,
            ),
            '',
          )
          .trim();

      String finalCover = localCoverUrl ?? '';

      if (discovered.containsKey(baseAlbumName)) {
        discovered[baseAlbumName]!['id'] =
            '${discovered[baseAlbumName]!['id']!},$folderId';

        if (discovered[baseAlbumName]!['cover']!.isEmpty &&
            finalCover.isNotEmpty) {
          discovered[baseAlbumName]!['cover'] = finalCover;
        }
      } else {
        // Do not call online cover APIs while crawling Drive. That made the
        // first library scan feel much slower, and embedded album art is the
        // preferred source anyway. The manual "Refresh cover" action still
        // uses online lookup as a fallback when needed.

        discovered[baseAlbumName] = {
          'id': folderId,
          'name': baseAlbumName.isEmpty ? folderName : baseAlbumName,
          'cover': finalCover,
          'dateAdded': DateTime.now().millisecondsSinceEpoch.toString(),
        };
      }
    }

    for (final sub in subFolders) {
      final subId = DriveUtils.effectiveId(sub);
      if (subId != null) {
        await _crawlDirectory(api, subId, sub.name ?? 'Unknown', discovered);
      }
    }
  }
}
