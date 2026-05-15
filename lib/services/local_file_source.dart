part of '../main.dart';

// ─── Local Files Source ────────────────────────────────────────────────────
// Keeps local files inside the same album/track model as Drive tracks by
// representing them as drive.File objects with source=local app properties.
//
// v2 adds:
// - selected local folders
// - recursive folder rescans
// - unchanged-file metadata cache reuse
// - folder.jpg/cover.jpg artwork
// - light embedded artwork fallback
// - missing-file cleanup

const String _localFoldersPrefsKey = 'infame_selected_local_folders_v1';
const MethodChannel _localMusicChannel = MethodChannel('musix/local_music');

class _LocalAudioEntry {
  const _LocalAudioEntry({
    required this.sourceRef,
    required this.displayName,
    this.importBatchId = '',
    this.importGroupKey = '',
    this.importGroupTitle = '',
    this.parentFolderRef = '',
    this.relativePath = '',
    this.size,
    this.modifiedTimeMs,
    this.mimeType = '',
    this.isContentUri = false,
  });

  final String sourceRef;
  final String displayName;
  final String importBatchId;
  final String importGroupKey;
  final String importGroupTitle;
  final String parentFolderRef;
  final String relativePath;
  final int? size;
  final int? modifiedTimeMs;
  final String mimeType;
  final bool isContentUri;
}

extension _LocalFileSourceExtension on _MainScreenState {
  static const Set<String> _supportedLocalAudioExtensions = <String>{
    'mp3',
    'flac',
    'wav',
    'm4a',
    'aac',
    'ogg',
    'opus',
    'wma',
    'alac',
    'aiff',
    'aif',
  };

  static const Set<String> _ignoredLocalExtensions = <String>{
    'cue',
    'jpg',
    'jpeg',
    'png',
    'txt',
    'log',
    'm3u',
    'm3u8',
  };

  static const List<String> _localFolderCoverNames = <String>[
    'cover.jpg',
    'folder.jpg',
    'front.jpg',
    'album.jpg',
    'artwork.jpg',
    'cover.jpeg',
    'folder.jpeg',
    'front.jpeg',
    'album.jpeg',
    'artwork.jpeg',
    'cover.png',
    'folder.png',
    'front.png',
    'album.png',
    'artwork.png',
  ];

  bool _isLocalAlbumRecord(Map<String, String> album) {
    return (album['source'] ?? '').trim() == 'local' ||
        (album['id'] ?? '').startsWith('local_album:');
  }

  String _localAlbumId(String album, String artist) {
    final key = [artist, album]
        .where((value) => value.trim().isNotEmpty)
        .join('::')
        .trim();
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
      return _sortTracksForAlbum(cached.where((track) {
        return _localTrackIsAvailable(track);
      }).toList());
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
        _localAlbumId(
          album['displayName']!.trim(),
          album['artist'] ?? '',
        ),
      if ((album['name'] ?? '').trim().isNotEmpty)
        _localAlbumId(
          album['name']!.trim(),
          album['artist'] ?? '',
        ),
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
        .where((key) =>
            key.startsWith('local_album:') || key.startsWith('local_folder:'))
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
          'Startup _libraryTrackIndex count=${_libraryTrackIndex.length}');
      debugPrint('Startup _albumTracksCache album count=$restoredAlbums');
      debugPrint('Startup local album cache restored tracks=$restoredTracks');
    }

    return restoredTracks;
  }

  Future<void> _loadSelectedLocalFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs
              .getStringList(_localFoldersPrefsKey)
              ?.map((path) => path.trim())
              .where((path) => path.isNotEmpty)
              .toSet()
              .toList() ??
          <String>[];
      saved.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) {
        _selectedLocalFolders = saved;
        return;
      }
      setState(() => _selectedLocalFolders = saved);
    } catch (_) {
      return;
    }
  }

  Future<void> _saveSelectedLocalFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final folders = _selectedLocalFolders
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    await prefs.setStringList(_localFoldersPrefsKey, folders);
  }

  Future<Map<String, dynamic>?> _pickLocalMusicFolderAndroid() async {
    try {
      final result = await _localMusicChannel.invokeMapMethod<String, dynamic>(
        'pickLocalMusicFolder',
      );
      return result;
    } catch (e) {
      _showError('Local folder picker failed: $e');
      return null;
    }
  }

  Future<void> _showLocalImportChooser() async {
    if (_isScanning || _loadingMetadata) {
      _showError('Wait for the current scan to finish first.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.72),
      builder: (sheetContext) {
        final colors = _safeColors(_currentDynamicColors);
        final accent = colors[1];
        final bgColor = _isDarkMode ? _darkBg : _lightBg;
        final textColor = _isDarkMode ? _textPri : _lightText;
        final subColor = _isDarkMode ? _textSub : _lightSubtext;

        Widget buildAction({
          required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap,
        }) {
          return GestureDetector(
            onTap: onTap,
            child: GlassyContainer(
              radius: 24,
              padding: const EdgeInsets.all(16),
              customBorder: accent.withOpacity(0.24),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withOpacity(0.12),
                    ),
                    child: Icon(icon, color: accent, size: 25),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            color: subColor,
                            fontSize: 13,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            margin: const EdgeInsets.only(top: 110),
            decoration: BoxDecoration(
              color: bgColor.withOpacity(0.98),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border(
                top: BorderSide(
                  color: (_isDarkMode ? Colors.white : Colors.black)
                      .withOpacity(0.08),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Spacer(),
                        Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: subColor.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Add local music',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pick individual files or scan a whole folder.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: subColor,
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    buildAction(
                      icon: Icons.audio_file_rounded,
                      title: 'Choose music files',
                      subtitle: 'Select FLAC, MP3, WAV, OGG, OPUS and more.',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _importLocalAudioFiles();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    buildAction(
                      icon: Icons.folder_open_rounded,
                      title: 'Choose folder',
                      subtitle:
                          'Scan album folders recursively for supported audio files.',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _pickLocalMusicFolder();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _scanLocalAudioFolderAndroid(
      String folderUri) async {
    try {
      final result = await _localMusicChannel.invokeMapMethod<String, dynamic>(
            'scanLocalMusicFolder',
            <String, dynamic>{'folderUri': folderUri},
          ) ??
          <String, dynamic>{};
      return result;
    } catch (e) {
      debugPrint('LocalScan error=android_scan folder=$folderUri error=$e');
      return <String, dynamic>{
        'folderUri': folderUri,
        'pickerType': 'saf',
        'usingSaf': true,
        'childCount': 0,
        'entityCount': 0,
        'supportedCount': 0,
        'firstChild': '',
        'firstSupported': '',
        'files': <Map<String, dynamic>>[],
        'error': e.toString(),
      };
    }
  }

  List<_LocalAudioEntry> _localAudioEntriesFromScanResult(
    List<dynamic> rawFiles, {
    required String importRootKey,
    required String importRootTitle,
  }) {
    return rawFiles.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final uri = (map['uri'] ?? map['path'] ?? '').toString().trim();
      final name = (map['name'] ?? '').toString().trim();
      final relPath = (map['relativePath'] ?? '').toString().trim();
      final mimeType = (map['mimeType'] ?? '').toString().trim();
      final size = int.tryParse((map['size'] ?? '').toString());
      final modifiedTimeMs =
          int.tryParse((map['modifiedTimeMs'] ?? '').toString());
      final isContentUri = DriveUtils.isContentUriString(uri);
      final groupRelative =
          relPath.trim().isNotEmpty ? _localDirname(relPath) : '';
      final importGroupKey = groupRelative.isNotEmpty
          ? '$importRootKey::$groupRelative'
          : importRootKey;
      final importGroupTitle = groupRelative.isNotEmpty
          ? _localBasename(groupRelative)
          : importRootTitle;
      return _LocalAudioEntry(
        sourceRef: uri,
        displayName: name.isNotEmpty ? name : _localBasename(uri),
        importBatchId: importRootKey,
        relativePath: relPath,
        importGroupKey: importGroupKey,
        importGroupTitle: importGroupTitle,
        parentFolderRef: importRootKey,
        size: size,
        modifiedTimeMs: modifiedTimeMs,
        mimeType: mimeType,
        isContentUri: isContentUri,
      );
    }).toList();
  }

  Future<List<_LocalAudioEntry>> _scanLocalAudioEntriesForFolder(
    String folder,
  ) async {
    if (_isAndroidSafFolderRef(folder)) {
      debugPrint('LocalScan start uri=$folder');
      final result = await _scanLocalAudioFolderAndroid(folder);
      final childCount =
          int.tryParse(result['childCount']?.toString() ?? '') ?? 0;
      final entityCount =
          int.tryParse(result['entityCount']?.toString() ?? '') ?? 0;
      final supportedCount =
          int.tryParse(result['supportedCount']?.toString() ?? '') ?? 0;
      final firstChild = (result['firstChild'] ?? '').toString();
      final firstSupported = (result['firstSupported'] ?? '').toString();
      final permissionStatus = (result['permissionStatus'] ?? '').toString();
      final selectedPath = (result['selectedPath'] ?? '').toString();
      final selectedUri = (result['selectedUri'] ?? '').toString();
      final selectedName = (result['selectedName'] ?? '').toString();
      final pickerType = (result['pickerType'] ?? 'saf').toString();
      final usingSaf = result['usingSaf'] == true;
      final files = (result['files'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .toList();
      final rootKey = selectedUri.isNotEmpty ? selectedUri : selectedPath;
      final rootTitle = selectedName.trim().isNotEmpty
          ? selectedName.trim()
          : _localBasename(rootKey);

      debugPrint('LocalScan pickerType=$pickerType');
      debugPrint('LocalScan androidSdk=${result['androidSdk'] ?? ''}');
      debugPrint('LocalScan permissionStatus=$permissionStatus');
      debugPrint('LocalScan selectedPath=$selectedPath');
      debugPrint('LocalScan selectedUri=$selectedUri');
      debugPrint('LocalScan selectedName=$selectedName');
      debugPrint('LocalScan usingSaf=$usingSaf');
      debugPrint('LocalScan childCount=$childCount entityCount=$entityCount');
      debugPrint('LocalScan supportedCount=$supportedCount');
      debugPrint('LocalScan firstChild=$firstChild');
      debugPrint('LocalScan firstSupported=$firstSupported');
      final sampleSupported = files
          .take(5)
          .map((item) => (item['name'] ?? '').toString().trim())
          .where((name) => name.isNotEmpty)
          .toList();
      debugPrint('LocalScan sampleSupported=${sampleSupported.join(' | ')}');
      debugPrint('LocalScan sampleUnsupported=');
      return _localAudioEntriesFromScanResult(
        files,
        importRootKey: rootKey.isNotEmpty ? rootKey : selectedUri,
        importRootTitle: rootTitle.isNotEmpty ? rootTitle : 'Local Files',
      );
    }

    final dir = Directory(folder);
    final exists = await dir.exists();
    debugPrint('LocalScan pickerType=filesystem');
    debugPrint(
        'LocalScan androidSdk=${Platform.isAndroid ? Platform.operatingSystemVersion : 'desktop'}');
    debugPrint('LocalScan permissionStatus=filesystem');
    debugPrint('LocalScan selectedPath=$folder');
    debugPrint('LocalScan selectedUri=');
    debugPrint('LocalScan usingSaf=false');
    debugPrint('LocalScan exists=$exists');

    if (!exists) {
      throw FileSystemException('Folder does not exist', folder);
    }

    final entries = <_LocalAudioEntry>[];
    var childCount = 0;
    var entityCount = 0;
    var supportedCount = 0;
    var skippedUnsupported = 0;
    final sampleSupported = <String>[];
    final sampleUnsupported = <String>[];
    String firstChild = '';

    try {
      final rootPath = dir.path.replaceAll('\\', '/').replaceFirst(
            RegExp(r'/+$'),
            '',
          );
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        entityCount++;
        final path = entity.path.trim();
        if (path.isEmpty) continue;
        final normalizedPath = path.replaceAll('\\', '/');
        final relativePath = normalizedPath.startsWith('$rootPath/')
            ? normalizedPath.substring(rootPath.length + 1)
            : '';
        if (relativePath.isEmpty || !relativePath.contains('/')) {
          childCount++;
        }
        if (entity is! File) continue;
        if (firstChild.isEmpty) firstChild = _localBasename(path);

        if (_isIgnoredLocalPath(path)) {
          skippedUnsupported++;
          if (sampleUnsupported.length < 5)
            sampleUnsupported.add(_localBasename(path));
          continue;
        }

        if (!_isSupportedLocalAudioPath(path)) {
          skippedUnsupported++;
          if (sampleUnsupported.length < 5)
            sampleUnsupported.add(_localBasename(path));
          continue;
        }

        supportedCount++;
        if (sampleSupported.length < 5)
          sampleSupported.add(_localBasename(path));
        entries.add(_LocalAudioEntry(
          sourceRef: path.replaceAll('\\', '/'),
          displayName: _localBasename(path),
          importBatchId: folder,
          relativePath: path.replaceAll('\\', '/'),
          importGroupKey: _localGroupKeyFromPath(path),
          importGroupTitle: _localGroupTitleFromPath(path),
          parentFolderRef: _localGroupKeyFromPath(path),
        ));
      }
    } catch (e) {
      debugPrint('LocalScan error=scan folder=$folder error=$e');
    }

    _logLocalScanSummary(
      folder: folder,
      exists: exists,
      entityCount: entityCount,
      supportedCount: supportedCount,
      skippedUnsupported: skippedUnsupported,
      sampleSupported: sampleSupported,
      sampleUnsupported: sampleUnsupported,
    );

    debugPrint('LocalScan childCount=$childCount entityCount=$entityCount');
    debugPrint('LocalScan firstChild=$firstChild');
    debugPrint(
        'LocalScan firstSupported=${sampleSupported.isNotEmpty ? sampleSupported.first : ''}');

    return entries;
  }

  Future<void> _pickLocalMusicFolder() async {
    if (_isScanning || _loadingMetadata) {
      _showError('Wait for the current scan to finish first.');
      return;
    }

    debugPrint('LocalImport source=folder');

    if (Platform.isAndroid) {
      final pickerResult = await _pickLocalMusicFolderAndroid();
      if (pickerResult == null) return;

      final selectedUri = (pickerResult['selectedUri'] ?? '').toString().trim();
      final selectedPath =
          (pickerResult['selectedPath'] ?? '').toString().trim();
      final usingSaf = pickerResult['usingSaf'] == true;
      final permissionStatus =
          (pickerResult['permissionStatus'] ?? 'unknown').toString();
      final permissionPersisted = permissionStatus == 'granted';
      final pickerType = (pickerResult['pickerType'] ?? 'saf').toString();
      final androidSdk =
          int.tryParse((pickerResult['androidSdk'] ?? '').toString()) ?? 0;

      debugPrint('LocalImport pickerResult path=$selectedPath');
      debugPrint('LocalImport pickerResult uri=$selectedUri');
      debugPrint('LocalImport usingSaf=$usingSaf');
      debugPrint('LocalImport permissionPersisted=$permissionPersisted');
      debugPrint('LocalScan pickerType=$pickerType');
      debugPrint('LocalScan androidSdk=$androidSdk');
      debugPrint('LocalScan permissionStatus=$permissionStatus');
      debugPrint('LocalScan selectedPath=$selectedPath');
      debugPrint('LocalScan selectedUri=$selectedUri');
      debugPrint('LocalScan usingSaf=$usingSaf');

      final folderRef = selectedUri.isNotEmpty ? selectedUri : selectedPath;
      if (folderRef.isEmpty) return;

      if (!_selectedLocalFolders.contains(folderRef)) {
        setState(() => _selectedLocalFolders = [
              ..._selectedLocalFolders,
              folderRef,
            ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
        await _saveSelectedLocalFolders();
      }

      await _rescanLocalMusicFolders(pathsOverride: <String>[folderRef]);
      return;
    }

    String? folderPath;
    try {
      folderPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose a local music folder',
      );
    } catch (e) {
      _showError('Local folder picker failed: $e');
      return;
    }

    final folder = folderPath?.trim() ?? '';
    if (folder.isEmpty) return;

    final normalized = folder.replaceAll('\\', '/');
    if (_isUnsupportedLocalFolderUriPath(normalized)) {
      debugPrint('LocalScan unsupported folder URI/path path=$normalized');
      _showError(
        'Could not read this folder. Try choosing another folder or granting file access.',
      );
      return;
    }

    if (!_selectedLocalFolders.contains(normalized)) {
      setState(() => _selectedLocalFolders = [
            ..._selectedLocalFolders,
            normalized,
          ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
      await _saveSelectedLocalFolders();
    }

    await _rescanLocalMusicFolders(pathsOverride: <String>[normalized]);
  }

  Future<void> _rescanLocalMusicFolders({List<String>? pathsOverride}) async {
    if (_isScanning || _loadingMetadata) {
      _showError('Wait for the current scan to finish first.');
      return;
    }

    final folders = (pathsOverride ?? _selectedLocalFolders)
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList();

    if (folders.isEmpty) {
      _showError('Choose a local music folder first.');
      return;
    }

    final scanStopwatch = Stopwatch()..start();
    setState(() => _isScanning = true);
    _setLocalImportProgress('Scanning folder...', inProgress: true);
    _showSuccess(
        'Scanning ${folders.length} local folder${folders.length == 1 ? '' : 's'}...');

    try {
      final entries = <_LocalAudioEntry>[];
      final missingFolders = <String>[];
      final unreadableFolders = <String>[];

      for (final folder in folders) {
        try {
          final folderEntries = await _scanLocalAudioEntriesForFolder(folder);
          if (folderEntries.isEmpty) {
            if (_isAndroidSafFolderRef(folder)) {
              unreadableFolders.add(folder);
            } else {
              missingFolders.add(folder);
            }
          } else {
            entries.addAll(folderEntries);
          }
        } catch (e) {
          debugPrint('LocalScan error=scan folder=$folder error=$e');
          unreadableFolders.add(folder);
        }
      }

      debugPrint(
          'LocalImport source=folder scannedCount=${entries.length} supportedCount=${entries.length}');

      if (missingFolders.isNotEmpty || unreadableFolders.isNotEmpty) {
        _selectedLocalFolders = _selectedLocalFolders
            .where((folder) =>
                !missingFolders.contains(folder) &&
                !unreadableFolders.contains(folder))
            .toList();
        await _saveSelectedLocalFolders();
      }

      debugPrint('LocalImport folder scanComplete count=${entries.length}');
      debugPrint(
          'Perf LocalImport scanMs=${scanStopwatch.elapsedMilliseconds}');

      if (entries.isEmpty) {
        _setLocalImportProgress(null);
        if (unreadableFolders.isNotEmpty || missingFolders.isNotEmpty) {
          _showError(
            'Could not read this folder. Try choosing another folder or granting file access.',
          );
          return;
        }
        _showError(
          folders.length == 1
              ? 'No supported audio files found in this folder.'
              : 'No supported audio files found in these folders.',
        );
        return;
      }

      _setLocalImportProgress('Found ${entries.length} tracks',
          inProgress: true);
      await _importLocalAudioEntries(
        entries,
        source: 'folder',
        successPrefix: 'Scanned',
      );
    } catch (e) {
      _setLocalImportProgress(null);
      _showError('Local folder scan failed: $e');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _importLocalAudioFiles() async {
    if (_isScanning || _loadingMetadata) {
      _showError('Wait for the current scan to finish first.');
      return;
    }

    debugPrint('LocalImport source=files');

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: _supportedLocalAudioExtensions.toList(),
      );
    } catch (e) {
      _showError('Local file picker failed: $e');
      return;
    }

    final paths = result?.files
            .map((file) => file.path?.trim() ?? '')
            .where(
                (path) => path.isNotEmpty && _isSupportedLocalAudioPath(path))
            .toSet()
            .toList() ??
        <String>[];

    debugPrint('LocalImport pickerResult path=${paths.take(3).join(' | ')}');
    debugPrint('LocalImport pickerResult uri=');
    debugPrint('LocalImport usingSaf=false');
    debugPrint('LocalImport permissionPersisted=false');
    debugPrint(
        'LocalImport source=files scannedCount=${paths.length} supportedCount=${paths.length}');

    if (paths.isEmpty) return;

    setState(() => _isScanning = true);
    _setLocalImportProgress(
      'Found ${paths.length} tracks',
      inProgress: true,
    );
    _showSuccess('Importing ${paths.length} local audio files...');

    try {
      await _importLocalAudioPaths(paths, successPrefix: 'Imported');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _importLocalAudioEntries(
    List<_LocalAudioEntry> entries, {
    required String source,
    String successPrefix = 'Imported',
  }) async {
    debugPrint(
        'LocalImport sharedPipeline=true source=$source count=${entries.length}');
    final totalStopwatch = Stopwatch()..start();
    final albumsById = <String, Map<String, String>>{};
    final tracksByAlbum = <String, List<drive.File>>{};
    var importedTracks = 0;
    var reusedCached = 0;
    var metadataMsTotal = 0;
    var artworkMsTotal = 0;
    final batchSize = source == 'folder' ? 2 : 4;
    _resetLocalImportSessionState();
    _setLocalImportProgress(
      source == 'folder'
          ? 'Importing 0 / ${entries.length} tracks...'
          : 'Importing local tracks...',
      inProgress: true,
    );

    try {
      for (var start = 0; start < entries.length; start += batchSize) {
        final end = math.min(start + batchSize, entries.length);
        final batch = entries.sublist(start, end);
        debugPrint(
            'LocalImport metadataBatch start index=$start count=${batch.length}');

        for (final entry in batch) {
          final sourceRef = entry.sourceRef.trim().replaceAll('\\', '/');
          if (sourceRef.isEmpty) continue;

          final isContentUri =
              entry.isContentUri || DriveUtils.isContentUriString(sourceRef);
          var localFile = isContentUri
              ? _localDriveFileFromUri(
                  sourceRef,
                  displayName: entry.displayName,
                  mimeType: entry.mimeType,
                  size: entry.size,
                  modifiedTime: entry.modifiedTimeMs == null
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(
                          entry.modifiedTimeMs!),
                )
              : _localDriveFileFromPath(sourceRef);
          if (!DriveUtils.isAudio(localFile)) continue;

          final metadataStopwatch = Stopwatch()..start();
          final metadata = await _readLocalTrackMetadataFromEntry(
            localFile,
            entry,
          );
          metadataMsTotal += metadataStopwatch.elapsedMilliseconds;
          if (_metaStore.peekFresh(localFile) != null) {
            reusedCached++;
          }

          if (source == 'files' && !isContentUri) {
            final persistedPath = await _persistImportedLocalFile(
              sourceRef,
              entry.displayName,
              metadata,
              existingLocalFile: File(sourceRef),
            );
            if (persistedPath != null &&
                persistedPath.trim().isNotEmpty &&
                persistedPath.trim() != sourceRef) {
              localFile = _localDriveFileFromPath(persistedPath.trim());
            }
          }

          _metaStore.putMemory(localFile, metadata);

          final albumArtist = _cleanBrainValue(metadata.albumArtist).isNotEmpty
              ? metadata.albumArtist!.trim()
              : (_cleanBrainValue(metadata.artist).isNotEmpty
                  ? metadata.artist.trim()
                  : 'Unknown Artist');
          final albumTitle = _cleanBrainValue(metadata.album).isNotEmpty &&
                  !_isWeakAlbumDisplayTitle(metadata.album, artist: albumArtist)
              ? metadata.album!.trim()
              : _localGroupTitleForEntry(entry);
          final albumId = _localAlbumKeyForTrack(entry, metadata);
          final existingAlbum = albumsById[albumId] ??
              _albums.firstWhere(
                (album) => (album['id'] ?? '') == albumId,
                orElse: () => <String, String>{},
              );
          final dateAdded = existingAlbum['dateAdded'] ??
              DateTime.now().millisecondsSinceEpoch.toString();

          final albumRecord = <String, String>{
            ...existingAlbum,
            'id': albumId,
            'albumKey': albumId,
            'source': 'local',
            'name': albumTitle,
            'displayName': albumTitle,
            'artist': albumArtist,
            'albumArtist': albumArtist,
            'cover': existingAlbum['cover'] ?? '',
            'dateAdded': dateAdded,
          };

          albumsById[albumId] = albumRecord;
          tracksByAlbum
              .putIfAbsent(albumId, () => <drive.File>[])
              .add(localFile);
          importedTracks++;
        }

        debugPrint(
            'LocalImport metadataBatch done index=$start count=${batch.length}');
        _setLocalImportProgress(
          'Importing ${math.min(end, entries.length)} / ${entries.length} tracks...',
          inProgress: true,
        );
        await Future<void>.delayed(Duration.zero);
      }

      if (importedTracks == 0) {
        _setLocalImportProgress(null);
        _showError('No supported local audio files were imported.');
        return;
      }

      debugPrint(
          'LocalImport grouping albums=${albumsById.length} tracks=$importedTracks');

      final existingById = <String, Map<String, String>>{
        for (final album in _albums) (album['id'] ?? ''): album,
      };

      for (final entry in albumsById.entries) {
        final albumId = entry.key;
        final album = entry.value;
        final tracks = _sortTracksForAlbum(tracksByAlbum[albumId] ?? []);
        if (tracks.isEmpty) continue;

        debugPrint(
            'LocalAlbumGroup key=$albumId album=${album['displayName'] ?? album['name'] ?? ''} albumArtist=${album['artist'] ?? ''} count=${tracks.length}');

        final artworkStopwatch = Stopwatch()..start();
        final cover = album['cover']?.trim().isNotEmpty == true
            ? album['cover']!.trim()
            : await _resolveLocalAlbumCover(albumId, tracks);
        artworkMsTotal += artworkStopwatch.elapsedMilliseconds;
        if (cover.trim().isNotEmpty) album['cover'] = cover.trim();

        _albumTracksCache[albumId] = tracks;
        _indexAlbumFromTracks(album, tracks, save: false);
        _indexTracksForAlbum(album, tracks);
        if (cover.trim().isNotEmpty) {
          _applyAlbumCoverFromMetadataScan(
            albumId,
            cover.trim(),
            persistChanges: false,
            refreshUi: false,
          );
        }
        existingById[albumId] = album;
      }

      _albums = existingById.values
          .where((album) => (album['id'] ?? '').trim().isNotEmpty)
          .toList()
        ..sort((a, b) => (a['displayName'] ?? a['name'] ?? '').compareTo(
              b['displayName'] ?? b['name'] ?? '',
            ));

      final saveStopwatch = Stopwatch()..start();
      await _metaStore.persistNow();
      await _saveLibraryTrackIndex(logLocalPersistence: true);
      await _saveLibraryBrain();
      await _persistAlbums();
      await _saveKnownTrackDurations();
      final saveMs = saveStopwatch.elapsedMilliseconds;
      debugPrint('LocalImport cacheRebuild once=true');

      _localImportInProgress = false;
      final cacheRebuildStopwatch = Stopwatch()..start();
      _librarySearchTextCache.clear();
      _invalidateHomeBrowseCache(force: true);
      _invalidateLibraryBrowseCache();
      _nowPlaying.refresh();
      final cacheRebuildMs = cacheRebuildStopwatch.elapsedMilliseconds;

      if (mounted) setState(() {});
      final cacheText = reusedCached > 0 ? ' ($reusedCached cached)' : '';
      final copyAvg = _localImportCopyCount == 0
          ? 0
          : (_localImportCopyMsTotal / _localImportCopyCount)
              .toStringAsFixed(1);
      final metadataAvg = importedTracks == 0
          ? 0
          : (metadataMsTotal / importedTracks).toStringAsFixed(1);
      debugPrint(
          'Perf LocalImport copyMs total=$_localImportCopyMsTotal perFileAvg=$copyAvg');
      debugPrint(
          'Perf LocalImport metadataMs total=$metadataMsTotal perFileAvg=$metadataAvg');
      debugPrint('Perf LocalImport artworkMs=$artworkMsTotal');
      debugPrint('Perf LocalImport saveMs=$saveMs');
      debugPrint('Perf LocalImport cacheRebuildMs=$cacheRebuildMs');
      debugPrint(
          'Perf LocalImport totalMs=${totalStopwatch.elapsedMilliseconds}');
      debugPrint(
          'LocalImport savedAlbums=${albumsById.length} savedTracks=$importedTracks');
      _setLocalImportProgress(null);
      _showSuccess('$successPrefix $importedTracks local songs$cacheText.');
    } catch (e) {
      _setLocalImportProgress(null);
      _showError('Local import failed: $e');
    } finally {
      _localImportInProgress = false;
      await _cleanupLocalImportTempFiles();
    }
  }

  Future<void> _importLocalAudioPaths(
    List<String> paths, {
    String successPrefix = 'Imported',
  }) async {
    final entries = paths
        .map(
          (path) => _LocalAudioEntry(
            sourceRef: path.trim(),
            displayName: _localBasename(path.trim()),
            importBatchId: _localGroupKeyFromPath(path.trim()),
            relativePath: path.trim(),
            importGroupKey: _localGroupKeyFromPath(path.trim()),
            importGroupTitle: _localGroupTitleFromPath(path.trim()),
            parentFolderRef: _localGroupKeyFromPath(path.trim()),
            isContentUri: DriveUtils.isContentUriString(path),
          ),
        )
        .toList();
    await _importLocalAudioEntries(
      entries,
      source: 'files',
      successPrefix: successPrefix,
    );
  }

  Future<String?> _persistImportedLocalFile(
    String sourceRef,
    String displayName,
    TrackMetadata metadata, {
    File? existingLocalFile,
  }) async {
    final source = sourceRef.trim().replaceAll('\\', '/');
    if (source.isEmpty || DriveUtils.isContentUriString(source)) {
      return source;
    }

    final sourceFile = existingLocalFile ?? File(source);
    if (!await sourceFile.exists()) return source;
    final sourceStat = await sourceFile.stat();

    final supportDir = await getApplicationSupportDirectory();
    final localDir = Directory('${supportDir.path}/infame/local_music');
    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }

    final sourceExt = _localExtension(
      displayName.isNotEmpty ? displayName : sourceFile.path,
    );
    final metaTitle = _safeCacheName(
      _cleanBrainValue(metadata.title).isNotEmpty
          ? metadata.title!.trim()
          : _localBasename(sourceFile.path),
    );
    final metaArtist = _safeCacheName(
      _cleanBrainValue(metadata.artist).isNotEmpty
          ? metadata.artist!.trim()
          : 'Unknown Artist',
    );
    final metaAlbum = _safeCacheName(
      _cleanBrainValue(metadata.album).isNotEmpty
          ? metadata.album!.trim()
          : 'Local',
    );
    final metaTrack = metadata.trackNumber?.toString().trim() ?? '';
    final metaDisc = metadata.discNumber?.toString().trim() ?? '';
    final sourceSize = sourceStat.size.toString();
    final sourceModified =
        sourceStat.modified.millisecondsSinceEpoch.toString();
    final fileName = [
      metaArtist,
      metaAlbum,
      if (metaDisc.isNotEmpty) 'd$metaDisc',
      if (metaTrack.isNotEmpty) 't$metaTrack',
      's$sourceSize',
      'm$sourceModified',
      metaTitle,
    ].where((part) => part.trim().isNotEmpty).join('_');
    final safeName = fileName.isNotEmpty
        ? _safeCacheName(fileName)
        : _safeCacheName(displayName);
    final targetName =
        safeName.isNotEmpty ? safeName : _safeCacheName(_localBasename(source));
    final targetPath = '${localDir.path}/$targetName$sourceExt';
    final targetFile = File(targetPath);
    if (await targetFile.exists()) {
      return targetFile.path;
    }

    try {
      await sourceFile.copy(targetFile.path);
      debugPrint('LocalImport persistentCopy created path=${targetFile.path}');
      return targetFile.path;
    } catch (e) {
      debugPrint('LocalImport persistentCopy failed source=$source error=$e');
      return source;
    }
  }

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
            : DateTime.fromMillisecondsSinceEpoch(entry.modifiedTimeMs!)
                .toIso8601String(),
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
          'LocalMetadata result title=${result.title} artist=${result.artist} album=${result.album} albumArtist=${result.albumArtist ?? ''} track=${result.trackNumber ?? ''} disc=${result.discNumber ?? ''}');
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
      String uriString, String displayName,
      {bool keepForSession = false}) async {
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
        <String, dynamic>{
          'uri': normalizedUri,
          'displayName': displayName,
        },
      );
      if (result == null) return null;
      if (result['ok'] != true) {
        debugPrint(
            'LocalMetadata tempCopy failed uri=$normalizedUri error=${result['error'] ?? ''}');
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
            'LocalArtwork folderImage found name=${_localBasename(folderCover)} bytes=${File(folderCover).lengthSync()}');
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
            'LocalArtwork embedded found track=$displayName bytes=$bytes');
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
      String albumId, File file) async {
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

    _albums.removeWhere((album) =>
        _isLocalAlbumRecord(album) &&
        !localAlbumIdsWithTracks.contains((album['id'] ?? '').trim()));

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
          'LocalImport tempCleanup remainingCount=$remainingCount remainingBytes=$remainingBytes');
    } catch (e) {
      debugPrint('LocalImport tempCleanup error=$e');
    }
  }
}
