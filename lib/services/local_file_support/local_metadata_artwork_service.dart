part of '../../main.dart';

extension _LocalMetadataArtworkServiceExtension on _MainScreenState {
  Future<TrackMetadata> _readLocalTrackMetadataFromEntry(
    drive.File localFile,
    _LocalAudioEntry entry,
  ) async {
    final sourceRef = entry.sourceRef.trim();
    final isContentUri =
        entry.isContentUri || DriveUtils.isContentUriString(sourceRef);
    if (isContentUri) {
      final keepTempForSession = _localImportInProgress;
      final tempPath = await _copyLocalMusicFileToTempPath(
        sourceRef,
        entry.displayName,
        keepForSession: keepTempForSession,
      );
      if (tempPath != null && tempPath.isNotEmpty) {
        final tempFile = File(tempPath);
        try {
          if (await tempFile.exists()) {
            return _readLocalTrackMetadata(localFile, tempFile);
          }
        } finally {
          if (!keepTempForSession) {
            try {
              if (await tempFile.exists()) {
                await tempFile.delete();
              }
            } catch (_) {}
          }
        }
      }

      final fallback = DriveUtils.getTrackMeta(localFile);
      final displayName = entry.displayName.trim().isNotEmpty
          ? entry.displayName.trim()
          : localFile.name ?? 'Unknown';
      final groupTitle = _localGroupTitleForEntry(entry);
      return TrackMetadata(
        title: fallback['title'] ?? displayName,
        artist: fallback['artist'] ?? 'Unknown Artist',
        album: groupTitle,
        albumArtist: fallback['albumArtist'] ?? fallback['artist'],
        modifiedTime: entry.modifiedTimeMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                entry.modifiedTimeMs!,
              ).toIso8601String(),
        size: entry.size?.toString() ?? localFile.size,
      );
    }

    final file = File(sourceRef);
    if (!await file.exists()) {
      return TrackMetadata(
        title: localFile.name ?? 'Unknown',
        artist: 'Unknown Artist',
        album: _localAlbumFallbackFromPath(sourceRef),
        modifiedTime: localFile.modifiedTime?.toIso8601String(),
        size: localFile.size,
      );
    }

    return _readLocalTrackMetadata(localFile, file);
  }

  Future<TrackMetadata> _readLocalTrackMetadata(
    drive.File localFile,
    File file,
  ) async {
    final cachedFresh = _metaStore.peekFresh(localFile);
    if (cachedFresh != null) return cachedFresh;

    final fallback = DriveUtils.getTrackMeta(localFile);
    try {
      debugPrint('LocalMetadata start file=${file.path}');
      final raw = readMetadata(file, getImage: false);
      final durationMs = _durationMsFromDynamic(raw.duration);
      final titleValue = _metadataField(raw, 'title');
      final artistValue = _metadataField(raw, 'artist');
      final albumValue = _metadataField(raw, 'album');
      final albumArtistValue = _metadataField(raw, 'albumArtist');
      final trackNumberValue = _metadataField(raw, 'trackNumber');
      final discNumberValue = _metadataField(raw, 'discNumber');
      final albumArtist = _cleanBrainValue(albumArtistValue?.toString());
      final artist = _cleanBrainValue(artistValue?.toString());
      final album = _cleanBrainValue(albumValue?.toString());
      final resolvedAlbumArtist = albumArtist.isNotEmpty ? albumArtist : artist;
      final resolvedAlbum =
          album.isNotEmpty ? album : _localAlbumFallbackFromPath(file.path);
      final result = TrackMetadata(
        title: titleValue?.toString().trim().isNotEmpty == true
            ? titleValue.toString().trim()
            : fallback['title'] ?? localFile.name ?? 'Unknown',
        artist: artist.isNotEmpty
            ? artist
            : (fallback['artist'] ?? 'Unknown Artist'),
        album: resolvedAlbum,
        albumArtist:
            resolvedAlbumArtist.isNotEmpty ? resolvedAlbumArtist : null,
        trackNumber: trackNumberValue is int
            ? trackNumberValue
            : int.tryParse(trackNumberValue?.toString() ?? '') ??
                raw.trackNumber,
        discNumber: discNumberValue is int
            ? discNumberValue
            : int.tryParse(discNumberValue?.toString() ?? '') ?? raw.discNumber,
        modifiedTime: localFile.modifiedTime?.toIso8601String(),
        size: localFile.size,
        durationMs: durationMs,
      );
      debugPrint(
        'LocalMetadata result title=${result.title} artist=${result.artist} album=${result.album} albumArtist=${result.albumArtist ?? ''} track=${result.trackNumber ?? ''} disc=${result.discNumber ?? ''}',
      );
      return result;
    } catch (_) {
      return TrackMetadata(
        title: fallback['title'] ?? localFile.name ?? 'Unknown',
        artist: fallback['artist'] ?? 'Unknown Artist',
        album: _localAlbumFallbackFromPath(file.path),
        modifiedTime: localFile.modifiedTime?.toIso8601String(),
        size: localFile.size,
      );
    }
  }

  dynamic _metadataField(dynamic raw, String key) {
    try {
      switch (key) {
        case 'title':
          return raw.title;
        case 'artist':
          return raw.artist;
        case 'album':
          return raw.album;
        case 'albumArtist':
          return raw.albumArtist;
        case 'trackNumber':
          return raw.trackNumber;
        case 'discNumber':
          return raw.discNumber;
        case 'year':
          return raw.year;
        case 'genre':
          return raw.genre;
      }
    } catch (_) {}

    return null;
  }

  Future<String?> _copyLocalMusicFileToTempPath(
    String uriString,
    String displayName, {
    bool keepForSession = false,
  }) async {
    final normalizedUri = uriString.trim();
    if (normalizedUri.isEmpty) return null;
    if (keepForSession) {
      final cachedPath = _localImportTempPathCache[normalizedUri];
      if (cachedPath != null && cachedPath.isNotEmpty) {
        final cachedFile = File(cachedPath);
        if (await cachedFile.exists()) {
          return cachedPath;
        }
        _localImportTempPathCache.remove(normalizedUri);
      }
    }
    final stopwatch = Stopwatch()..start();
    try {
      final result = await _localMusicChannel.invokeMapMethod<String, dynamic>(
        'copyLocalMusicFileToTemp',
        <String, dynamic>{'uri': normalizedUri, 'displayName': displayName},
      );
      if (result == null) return null;
      if (result['ok'] != true) {
        debugPrint(
          'LocalMetadata tempCopy failed uri=$normalizedUri error=${result['error'] ?? ''}',
        );
        return null;
      }
      final tempPath = (result['tempPath'] ?? '').toString().trim();
      if (tempPath.isEmpty) return null;
      _localImportCopyMsTotal += stopwatch.elapsedMilliseconds;
      _localImportCopyCount++;
      debugPrint('LocalImport tempCopy created path=$tempPath');
      if (keepForSession) {
        _localImportTempPathCache[normalizedUri] = tempPath;
        _localImportTempFiles.add(tempPath);
      }
      return tempPath;
    } catch (e) {
      debugPrint('LocalMetadata tempCopy error uri=$normalizedUri error=$e');
      return null;
    }
  }

  int? _durationMsFromDynamic(dynamic value) {
    if (value == null) return null;
    if (value is Duration) return value.inMilliseconds;
    if (value is int) return value > 0 ? value : null;
    final parsed = int.tryParse(value.toString());
    return parsed != null && parsed > 0 ? parsed : null;
  }

  String _localAlbumFallbackFromPath(String path) {
    if (DriveUtils.isContentUriString(path)) {
      return _localAlbumFallbackFromRelativePath('');
    }
    final dir = _localDirname(path);
    if (dir.isEmpty) return 'Local Files';
    final album = _localBasename(dir);
    return album.trim().isEmpty ? 'Local Files' : album.trim();
  }

  String _localAlbumFallbackFromRelativePath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) return 'Local Files';
    final segments = normalized
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    if (segments.length < 2) {
      final base = _localBasename(normalized);
      return base.trim().isEmpty ? 'Local Files' : base.trim();
    }
    final album = segments[segments.length - 2].trim();
    return album.isEmpty ? 'Local Files' : album;
  }

  String _localAlbumFallbackFromEntry(_LocalAudioEntry entry) {
    final relative = entry.relativePath.trim();
    if (relative.isNotEmpty) {
      return _localAlbumFallbackFromRelativePath(relative);
    }
    return _localAlbumFallbackFromPath(entry.sourceRef);
  }

  Future<String> _resolveLocalAlbumCover(
    String albumId,
    List<drive.File> tracks,
  ) async {
    if (tracks.isEmpty) return '';
    debugPrint('LocalArtwork start albumKey=$albumId');

    final hasFilePaths = tracks.any((track) {
      final ref = DriveUtils.localSourceRef(track)?.trim() ?? '';
      return ref.isNotEmpty && !DriveUtils.isContentUriString(ref);
    });

    if (hasFilePaths) {
      final folderCover = await _findLocalFolderCover(tracks);
      if (folderCover.isNotEmpty) {
        debugPrint(
          'LocalArtwork folderImage found name=${_localBasename(folderCover)} bytes=${File(folderCover).lengthSync()}',
        );
        return folderCover;
      }
    }

    for (final track in tracks.take(4)) {
      final sourceRef = DriveUtils.localSourceRef(track);
      if (sourceRef == null || sourceRef.trim().isEmpty) continue;
      final displayName = track.name ?? _localBasename(sourceRef);
      final cover = await _readAndCacheEmbeddedLocalCoverFromSource(
        albumId,
        sourceRef,
        displayName,
      );
      if (cover.isNotEmpty) {
        final bytes = await File(cover).length();
        debugPrint(
          'LocalArtwork embedded found track=$displayName bytes=$bytes',
        );
        return cover;
      }
    }

    debugPrint('LocalArtwork none albumKey=$albumId');
    return '';
  }

  Future<String> _findLocalFolderCover(List<drive.File> tracks) async {
    final checkedDirs = <String>{};

    for (final track in tracks.take(6)) {
      final path = DriveUtils.localSourceRef(track);
      if (path == null || path.isEmpty) continue;
      if (DriveUtils.isContentUriString(path)) continue;
      final dir = _localDirname(path);
      if (dir.isEmpty || !checkedDirs.add(dir)) continue;

      for (final name in _localFolderCoverNames) {
        final candidate = File('$dir/$name');
        if (await candidate.exists()) return candidate.path;
      }
    }

    return '';
  }

  Future<String> _readAndCacheEmbeddedLocalCover(
    String albumId,
    File file,
  ) async {
    if (!await file.exists()) return '';

    try {
      final dynamic raw = readMetadata(file, getImage: true);
      final bytes = _coverBytesFromDynamic(raw);
      if (bytes == null || bytes.isEmpty) return '';

      final dir = await getApplicationDocumentsDirectory();
      final coverDir = Directory('${dir.path}/infame_local_covers');
      if (!await coverDir.exists()) await coverDir.create(recursive: true);

      final safeName = _safeCacheName(albumId);
      final coverFile = File('${coverDir.path}/$safeName.jpg');
      await coverFile.writeAsBytes(bytes, flush: false);
      debugPrint('LocalArtwork saveCover key=$albumId bytes=${bytes.length}');
      return coverFile.path;
    } catch (_) {
      return '';
    }
  }

  Future<String> _readAndCacheEmbeddedLocalCoverFromSource(
    String albumId,
    String sourceRef,
    String displayName,
  ) async {
    final normalized = sourceRef.trim();
    if (normalized.isEmpty) return '';

    if (!DriveUtils.isContentUriString(normalized)) {
      return _readAndCacheEmbeddedLocalCover(albumId, File(normalized));
    }

    final keepTempForSession = _localImportInProgress;
    final tempPath = await _copyLocalMusicFileToTempPath(
      normalized,
      displayName,
      keepForSession: keepTempForSession,
    );
    if (tempPath == null || tempPath.isEmpty) return '';
    final tempFile = File(tempPath);
    try {
      return await _readAndCacheEmbeddedLocalCover(albumId, tempFile);
    } finally {
      if (!keepTempForSession) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
      }
    }
  }

  Uint8List? _coverBytesFromDynamic(dynamic raw) {
    dynamic value;

    try {
      value = raw.pictures;
      final bytes = _bytesFromPictureCollection(value);
      if (bytes != null) return bytes;
    } catch (_) {}

    try {
      value = raw.images;
      final bytes = _bytesFromPictureCollection(value);
      if (bytes != null) return bytes;
    } catch (_) {}

    try {
      value = raw.picture;
      final bytes = _bytesFromDynamicPicture(value);
      if (bytes != null) return bytes;
    } catch (_) {}

    try {
      value = raw.image;
      final bytes = _bytesFromDynamicPicture(value);
      if (bytes != null) return bytes;
    } catch (_) {}

    try {
      value = raw.coverBytes;
      final bytes = _bytesFromDynamicPicture(value);
      if (bytes != null) return bytes;
    } catch (_) {}

    return null;
  }

  Uint8List? _bytesFromPictureCollection(dynamic value) {
    if (value == null) return null;
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    if (value is Iterable && value.isNotEmpty) {
      for (final item in value) {
        final bytes = _bytesFromDynamicPicture(item);
        if (bytes != null && bytes.isNotEmpty) return bytes;
      }
    }
    return _bytesFromDynamicPicture(value);
  }

  Uint8List? _bytesFromDynamicPicture(dynamic value) {
    if (value == null) return null;
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);

    try {
      final dynamic bytes = value.bytes;
      if (bytes is Uint8List) return bytes;
      if (bytes is List<int>) return Uint8List.fromList(bytes);
    } catch (_) {}

    try {
      final dynamic bytes = value.data;
      if (bytes is Uint8List) return bytes;
      if (bytes is List<int>) return Uint8List.fromList(bytes);
    } catch (_) {}

    try {
      final dynamic bytes = value.pictureData;
      if (bytes is Uint8List) return bytes;
      if (bytes is List<int>) return Uint8List.fromList(bytes);
    } catch (_) {}

    return null;
  }

  Future<void> _removeMissingLocalFiles() async {
    if (_isScanning || _loadingMetadata) {
      _showError('Wait for the current scan to finish first.');
      return;
    }

    final missingIds = <String>[];
    for (final entry in _libraryTrackIndex.entries) {
      final record = entry.value;
      if ((record['source'] ?? '') != 'local') continue;
      final path = (record['localPath'] ?? '').trim();
      final uri = (record['localUri'] ?? '').trim();
      if (uri.isNotEmpty) continue;
      if (path.isEmpty || !File(path).existsSync()) missingIds.add(entry.key);
    }

    if (missingIds.isEmpty) {
      _showSuccess('No missing local files found.');
      return;
    }

    for (final id in missingIds) {
      _libraryTrackIndex.remove(id);
    }

    final localAlbumIdsWithTracks = _libraryTrackIndex.values
        .where((record) => (record['source'] ?? '') == 'local')
        .map((record) => (record['albumId'] ?? '').trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    _albums.removeWhere(
      (album) =>
          _isLocalAlbumRecord(album) &&
          !localAlbumIdsWithTracks.contains((album['id'] ?? '').trim()),
    );

    final emptyLocalAlbumCaches = <String>[];
    final updatedLocalAlbumCaches = <String, List<drive.File>>{};
    _albumTracksCache.forEach((albumId, tracks) {
      if (!albumId.startsWith('local_album:')) return;
      final kept = tracks.where((track) {
        final id = DriveUtils.effectiveId(track);
        return id != null &&
            _libraryTrackIndex.containsKey(id) &&
            _localTrackIsAvailable(track);
      }).toList();
      if (kept.isEmpty) {
        emptyLocalAlbumCaches.add(albumId);
      } else {
        updatedLocalAlbumCaches[albumId] = kept;
      }
    });
    for (final albumId in emptyLocalAlbumCaches) {
      _albumTracksCache.remove(albumId);
    }
    updatedLocalAlbumCaches.forEach((albumId, tracks) {
      _albumTracksCache[albumId] = tracks;
    });

    await _saveLibraryTrackIndex();
    await _saveLibraryBrain();
    await _persistAlbums();

    _librarySearchTextCache.clear();
    _invalidateHomeBrowseCache();
    _invalidateLibraryBrowseCache();
    _nowPlaying.refresh();
    if (mounted) setState(() {});

    _showSuccess('Removed ${missingIds.length} missing local songs.');
  }

  Future<void> _loadMetadataForLocal(
    drive.File file, {
    Map<String, String>? albumRecord,
  }) async {
    final localPath = DriveUtils.localSourceRef(file);
    if (localPath == null || localPath.isEmpty) return;
    if (DriveUtils.isContentUriString(localPath)) return;

    try {
      final localFile = File(localPath);
      if (!await localFile.exists()) return;

      final metadata = await _readLocalTrackMetadata(file, localFile);
      await _metaStore.put(file, metadata);
      _indexTracksForAlbum(albumRecord ?? _viewingAlbum ?? <String, String>{}, [
        file,
      ]);
      _nowPlaying.refresh();
      if (mounted) setState(() {});
    } catch (_) {
      return;
    }
  }

  Future<void> _cleanupStaleLocalImportTempFiles() async {
    try {
      final dir = await getTemporaryDirectory();
      final tempDir = Directory(dir.path);
      var remainingCount = 0;
      var remainingBytes = 0;

      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.last
              : entity.path;
          if (!name.startsWith('infame_local_')) continue;

          try {
            remainingBytes += await entity.length();
            await entity.delete();
            debugPrint('LocalImport tempCopy deleted path=${entity.path}');
          } catch (_) {}
        }
      }

      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.last
              : entity.path;
          if (!name.startsWith('infame_local_')) continue;
          remainingCount++;
        }
      }

      debugPrint(
        'LocalImport tempCleanup remainingCount=$remainingCount remainingBytes=$remainingBytes',
      );
    } catch (e) {
      debugPrint('LocalImport tempCleanup error=$e');
    }
  }
}
