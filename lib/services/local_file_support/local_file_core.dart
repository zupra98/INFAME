part of '../../main.dart';

extension _LocalFileCoreExtension on _MainScreenState {
  bool _isLocalAlbumRecord(Map<String, String> album) {
    return (album['source'] ?? '').trim() == 'local' ||
        (album['id'] ?? '').startsWith('local_album:');
  }

  String _localAlbumId(String album, String artist) {
    final key = [
      artist,
      album,
    ].where((value) => value.trim().isNotEmpty).join('::').trim();
    return 'local_album:${_normalizeAlbumKeySegment(key.isEmpty ? album : key)}';
  }

  String _localGroupKeyFromPath(String path) {
    final normalized = path.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) return '';
    final dir = _localDirname(normalized);
    if (dir.isNotEmpty) return dir;
    return normalized;
  }

  String _localGroupTitleFromPath(String path) {
    final normalized = path.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) return 'Local Files';
    final dir = _localDirname(normalized);
    final candidate =
        dir.isNotEmpty ? _localBasename(dir) : _localBasename(normalized);
    return candidate.trim().isNotEmpty ? candidate.trim() : 'Local Files';
  }

  String _localGroupKeyForEntry(_LocalAudioEntry entry) {
    final key = entry.importGroupKey.trim();
    if (key.isNotEmpty) return key;
    final batchId = entry.importBatchId.trim();
    if (batchId.isNotEmpty) return batchId;
    final parent = entry.parentFolderRef.trim();
    if (parent.isNotEmpty) return parent;
    final relative = entry.relativePath.trim();
    if (relative.isNotEmpty) {
      final relativeDir = _localDirname(relative);
      if (relativeDir.isNotEmpty) return relativeDir;
    }
    return _localGroupKeyFromPath(entry.sourceRef);
  }

  String _localGroupTitleForEntry(_LocalAudioEntry entry) {
    final title = entry.importGroupTitle.trim();
    if (title.isNotEmpty) return title;
    final batchId = entry.importBatchId.trim();
    if (batchId.isNotEmpty) {
      final candidate = _localBasename(batchId);
      if (candidate.trim().isNotEmpty) return candidate.trim();
    }
    final parent = entry.parentFolderRef.trim();
    if (parent.isNotEmpty) {
      final candidate = _localBasename(parent);
      if (candidate.trim().isNotEmpty) return candidate.trim();
    }
    final key = _localGroupKeyForEntry(entry);
    if (key.isNotEmpty) return _localGroupTitleFromPath(key);
    return _localGroupTitleFromPath(entry.sourceRef);
  }

  String _localAlbumKeyForTrack(
    _LocalAudioEntry entry,
    TrackMetadata metadata,
  ) {
    final album = _cleanBrainValue(metadata.album);
    final albumArtist = _cleanBrainValue(metadata.albumArtist).isNotEmpty
        ? _cleanBrainValue(metadata.albumArtist)
        : _cleanBrainValue(metadata.artist);
    final albumTitle = album.isNotEmpty &&
            !_isWeakAlbumDisplayTitle(album, artist: albumArtist)
        ? album
        : '';
    if (albumTitle.isNotEmpty) {
      return 'local_album:${_normalizeAlbumKeySegment('$albumArtist::$albumTitle')}';
    }
    final fallbackGroupKey = _localGroupKeyForEntry(entry);
    final normalized = fallbackGroupKey.isEmpty
        ? _localGroupTitleForEntry(entry)
        : fallbackGroupKey;
    return 'local_folder:${_normalizeAlbumKeySegment(normalized)}';
  }

  String _localBasename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx >= 0 ? normalized.substring(idx + 1) : normalized;
  }

  String _localDirname(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx >= 0 ? normalized.substring(0, idx) : '';
  }

  String _localExtension(String path) {
    final name = _localBasename(path).toLowerCase();
    final idx = name.lastIndexOf('.');
    if (idx < 0 || idx == name.length - 1) return '';
    return name.substring(idx + 1);
  }

  bool _isSupportedLocalAudioPath(String path) {
    return _supportedLocalAudioExtensions.contains(_localExtension(path));
  }

  bool _isIgnoredLocalPath(String path) {
    final name = _localBasename(path).trim();
    if (name.isEmpty || name.startsWith('.')) return true;
    final ext = _localExtension(path);
    return ext.isNotEmpty && _ignoredLocalExtensions.contains(ext);
  }

  bool _isUnsupportedLocalFolderUriPath(String path) {
    final lower = path.trim().toLowerCase();
    return lower.startsWith('content://') ||
        lower.startsWith('content:') ||
        lower.contains('://');
  }

  bool _isAndroidSafFolderRef(String folder) {
    return Platform.isAndroid && _isUnsupportedLocalFolderUriPath(folder);
  }

  bool _localTrackIsAvailable(drive.File track) {
    final ref = DriveUtils.localSourceRef(track)?.trim() ?? '';
    if (ref.isEmpty) return false;
    if (DriveUtils.isContentUriString(ref)) return true;
    return File(ref).existsSync();
  }

  void _logLocalScanSummary({
    required String folder,
    required bool exists,
    required int entityCount,
    required int supportedCount,
    required int skippedUnsupported,
    required List<String> sampleSupported,
    required List<String> sampleUnsupported,
  }) {
    debugPrint('LocalScan start path=$folder');
    debugPrint('LocalScan exists=$exists');
    debugPrint('LocalScan entityCount=$entityCount');
    debugPrint('LocalScan supportedCount=$supportedCount');
    debugPrint('LocalScan skippedUnsupported=$skippedUnsupported');
    debugPrint('LocalScan sampleSupported=${sampleSupported.join(' | ')}');
    debugPrint('LocalScan sampleUnsupported=${sampleUnsupported.join(' | ')}');
  }

  drive.File _localDriveFileFromSource(
    String sourceRef, {
    String? displayName,
    bool isContentUri = false,
    String? mimeType,
    int? size,
    DateTime? modifiedTime,
  }) {
    File? file;
    FileStat? stat;
    if (!isContentUri) {
      file = File(sourceRef);
      try {
        stat = file.statSync();
      } catch (_) {}
    }

    final name = (displayName?.trim().isNotEmpty == true)
        ? displayName!.trim()
        : _localBasename(sourceRef);
    final localId = DriveUtils.localIdForSource(sourceRef);
    final localSize =
        size?.toString() ?? stat?.size.toString() ?? (isContentUri ? '0' : '0');
    final localModifiedTime = modifiedTime ?? stat?.modified;

    return drive.File()
      ..id = localId
      ..name = name
      ..mimeType =
          mimeType?.trim().isNotEmpty == true ? mimeType!.trim() : 'audio/local'
      ..size = localSize
      ..modifiedTime = localModifiedTime
      ..appProperties = <String, String>{
        'source': 'local',
        if (isContentUri) 'localUri': sourceRef else 'path': sourceRef,
      }
      ..properties = <String, String>{
        'source': 'local',
        if (isContentUri) 'localUri': sourceRef else 'path': sourceRef,
      };
  }

  drive.File _localDriveFileFromPath(String path) {
    return _localDriveFileFromSource(path);
  }

  drive.File _localDriveFileFromUri(
    String uri, {
    String? displayName,
    String? mimeType,
    int? size,
    DateTime? modifiedTime,
  }) {
    return _localDriveFileFromSource(
      uri,
      displayName: displayName,
      isContentUri: true,
      mimeType: mimeType,
      size: size,
      modifiedTime: modifiedTime,
    );
  }

  List<drive.File> _localTracksForAlbum(Map<String, String> album) {
    final albumId = _albumCacheKey(album, source: 'local_album_tracks');
    final cached = _albumTracksCache[albumId];
    if (cached != null && cached.isNotEmpty) {
      return _sortTracksForAlbum(
        cached.where((track) {
          return _localTrackIsAvailable(track);
        }).toList(),
      );
    }

    final rebuilt = _localTracksForAlbumFromIndex(album);
    if (rebuilt.isNotEmpty) {
      _albumTracksCache[albumId] = rebuilt;
      return rebuilt;
    }

    return const <drive.File>[];
  }

  List<drive.File> _localTracksForAlbumFromIndex(Map<String, String> album) {
    final candidates = <String>{
      _albumCacheKey(album, source: 'local_album_tracks_fallback'),
      (album['id'] ?? '').trim(),
      (album['albumKey'] ?? '').trim(),
      (album['albumId'] ?? '').trim(),
      if ((album['displayName'] ?? '').trim().isNotEmpty)
        _localAlbumId(album['displayName']!.trim(), album['artist'] ?? ''),
      if ((album['name'] ?? '').trim().isNotEmpty)
        _localAlbumId(album['name']!.trim(), album['artist'] ?? ''),
      if ((album['name'] ?? '').trim().isNotEmpty)
        _normalizeAlbumKeySegment(_localGroupKeyFromPath(album['name']!)),
    }.where((value) => value.trim().isNotEmpty).toSet();

    final tracks = <drive.File>[];
    for (final record in _libraryTrackIndex.values) {
      if ((record['source'] ?? '') != 'local') continue;

      final recordAlbumIds = <String>{
        (record['albumId'] ?? '').trim(),
        (record['albumKey'] ?? '').trim(),
        _albumCacheKey(record['albumId'] ?? '', source: 'local_track_album_id'),
        _albumCacheKey(
          record['albumKey'] ?? '',
          source: 'local_track_album_key',
        ),
      }.where((value) => value.trim().isNotEmpty).toSet();

      if (recordAlbumIds.intersection(candidates).isEmpty) continue;

      final localPath = (record['localPath'] ?? '').trim();
      final localUri = (record['localUri'] ?? '').trim();
      if (localPath.isEmpty && localUri.isEmpty) continue;
      if (localUri.isEmpty && !File(localPath).existsSync()) continue;
      tracks.add(_fileFromTrackIndexRecord(record));
    }

    final sorted = _sortTracksForAlbum(tracks);
    if (sorted.isNotEmpty) {
      _albumTracksCache[_albumCacheKey(album, source: 'local_album_tracks')] =
          sorted;
    }
    return sorted;
  }

  int _rebuildLocalAlbumTrackCacheFromIndex({bool log = false}) {
    final localAlbums = _albums.where(_isLocalAlbumRecord).toList();
    final localTrackCount = _libraryTrackIndex.values
        .where((record) => (record['source'] ?? '') == 'local')
        .length;

    final localCacheKeys = _albumTracksCache.keys
        .where(
          (key) =>
              key.startsWith('local_album:') || key.startsWith('local_folder:'),
        )
        .toList();
    for (final key in localCacheKeys) {
      _albumTracksCache.remove(key);
    }

    var restoredTracks = 0;
    var restoredAlbums = 0;
    for (final album in localAlbums) {
      final albumId = _albumCacheKey(album, source: 'local_rebuild_album');
      if (albumId.isEmpty) continue;
      final tracks = _localTracksForAlbumFromIndex(album);
      if (tracks.isEmpty) {
        if (log) {
          debugPrint(
            'DataIntegrityWarning local album missing tracks key=$albumId title=${album['displayName'] ?? album['name'] ?? ''} artist=${album['artist'] ?? ''}',
          );
        }
        continue;
      }

      _albumTracksCache[albumId] = tracks;
      restoredTracks += tracks.length;
      restoredAlbums++;

      if (log) {
        debugPrint(
          'Startup local album key=$albumId title=${album['displayName'] ?? album['name'] ?? ''} artist=${album['artist'] ?? ''} restoredTrackCount=${tracks.length}',
        );
      }
    }

    if (log) {
      debugPrint('Startup local albums loaded count=${localAlbums.length}');
      debugPrint('Startup local tracks loaded count=$localTrackCount');
      debugPrint(
        'Startup _libraryTrackIndex count=${_libraryTrackIndex.length}',
      );
      debugPrint('Startup _albumTracksCache album count=$restoredAlbums');
      debugPrint('Startup local album cache restored tracks=$restoredTracks');
    }

    return restoredTracks;
  }
}
