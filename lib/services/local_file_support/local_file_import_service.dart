part of '../../main.dart';

extension _LocalFileImportServiceExtension on _MainScreenState {
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
      'Scanning ${folders.length} local folder${folders.length == 1 ? '' : 's'}...',
    );

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
        'LocalImport source=folder scannedCount=${entries.length} supportedCount=${entries.length}',
      );

      if (missingFolders.isNotEmpty || unreadableFolders.isNotEmpty) {
        _selectedLocalFolders = _selectedLocalFolders
            .where(
              (folder) =>
                  !missingFolders.contains(folder) &&
                  !unreadableFolders.contains(folder),
            )
            .toList();
        await _saveSelectedLocalFolders();
      }

      debugPrint('LocalImport folder scanComplete count=${entries.length}');
      debugPrint(
        'Perf LocalImport scanMs=${scanStopwatch.elapsedMilliseconds}',
      );

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

      _setLocalImportProgress(
        'Found ${entries.length} tracks',
        inProgress: true,
      );
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
              (path) => path.isNotEmpty && _isSupportedLocalAudioPath(path),
            )
            .toSet()
            .toList() ??
        <String>[];

    debugPrint('LocalImport pickerResult path=${paths.take(3).join(' | ')}');
    debugPrint('LocalImport pickerResult uri=');
    debugPrint('LocalImport usingSaf=false');
    debugPrint('LocalImport permissionPersisted=false');
    debugPrint(
      'LocalImport source=files scannedCount=${paths.length} supportedCount=${paths.length}',
    );

    if (paths.isEmpty) return;

    setState(() => _isScanning = true);
    _setLocalImportProgress('Found ${paths.length} tracks', inProgress: true);
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
      'LocalImport sharedPipeline=true source=$source count=${entries.length}',
    );
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
          'LocalImport metadataBatch start index=$start count=${batch.length}',
        );

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
                          entry.modifiedTimeMs!,
                        ),
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
          'LocalImport metadataBatch done index=$start count=${batch.length}',
        );
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
        'LocalImport grouping albums=${albumsById.length} tracks=$importedTracks',
      );

      final existingById = <String, Map<String, String>>{
        for (final album in _albums) (album['id'] ?? ''): album,
      };

      for (final entry in albumsById.entries) {
        final albumId = entry.key;
        final album = entry.value;
        final tracks = _sortTracksForAlbum(tracksByAlbum[albumId] ?? []);
        if (tracks.isEmpty) continue;

        debugPrint(
          'LocalAlbumGroup key=$albumId album=${album['displayName'] ?? album['name'] ?? ''} albumArtist=${album['artist'] ?? ''} count=${tracks.length}',
        );

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
        ..sort(
          (a, b) => (a['displayName'] ?? a['name'] ?? '').compareTo(
            b['displayName'] ?? b['name'] ?? '',
          ),
        );

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
          : (_localImportCopyMsTotal / _localImportCopyCount).toStringAsFixed(
              1,
            );
      final metadataAvg = importedTracks == 0
          ? 0
          : (metadataMsTotal / importedTracks).toStringAsFixed(1);
      debugPrint(
        'Perf LocalImport copyMs total=$_localImportCopyMsTotal perFileAvg=$copyAvg',
      );
      debugPrint(
        'Perf LocalImport metadataMs total=$metadataMsTotal perFileAvg=$metadataAvg',
      );
      debugPrint('Perf LocalImport artworkMs=$artworkMsTotal');
      debugPrint('Perf LocalImport saveMs=$saveMs');
      debugPrint('Perf LocalImport cacheRebuildMs=$cacheRebuildMs');
      debugPrint(
        'Perf LocalImport totalMs=${totalStopwatch.elapsedMilliseconds}',
      );
      debugPrint(
        'LocalImport savedAlbums=${albumsById.length} savedTracks=$importedTracks',
      );
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
}
