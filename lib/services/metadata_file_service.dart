part of '../main.dart';

extension _MetadataFileServiceExtension on _MainScreenState {
  Future<void> _loadMetadataFor(
    drive.File file,
    String token, {
    Map<String, String>? albumRecord,
    bool textOnly = false,
    bool persistImmediately = true,
    bool refreshUi = true,
    http.Client? client,
  }) async {
    final fileId = DriveUtils.effectiveId(file);
    if (fileId == null) return;

    final cachedFresh = _metaStore.peekFresh(file);
    if (cachedFresh != null &&
        _validDurationMsFromValue(cachedFresh.durationMs) != null) {
      return;
    }

    final albumKey = albumRecord == null
        ? ''
        : _albumCacheKey(albumRecord, source: 'metadata_scan');
    final albumTitle =
        albumRecord == null ? '' : _resolvedAlbumTitle(albumRecord);
    final albumArtist =
        albumRecord == null ? '' : _resolvedAlbumArtist(albumRecord);
    var metadataAppliedLogged = false;
    void logApplied() {
      if (metadataAppliedLogged || albumKey.isEmpty) return;
      metadataAppliedLogged = true;
      debugPrint(
          'MetadataScan applied albumKey=$albumKey albumTitle=$albumTitle albumArtist=$albumArtist');
      debugPrint('UI refresh after metadata scan');
    }

    File? tempFile;

    try {
      final fallback = DriveUtils.getTrackMeta(file);
      TrackReadResult? fastResult = await FastTagReader.read(
        file: file,
        token: token,
        readCover: !textOnly,
        client: client,
      );
      String? embeddedCoverPath;

      if (!textOnly && fastResult?.coverBytes != null) {
        embeddedCoverPath =
            await _saveEmbeddedCover(file, fastResult!.coverBytes!);
        if (embeddedCoverPath != null) {
          _applyEmbeddedCoverToAlbum(file, embeddedCoverPath,
              albumRecord: albumRecord);
        }
      }

      final fastDurationMs =
          _validDurationMsFromValue(fastResult?.duration?.inMilliseconds);

      // Avoid the slow player-based fallback when the tag reader already found
      // the duration. This keeps album metadata refreshes independent of active
      // playback and avoids waiting on the audio player for common formats.
      if (!textOnly &&
          _knownTrackDurationsMs[fileId] == null &&
          fastDurationMs == null) {
        final duration = await _getDurationWithTemporaryPlayer(file, token);
        if (duration != null &&
            duration.inMilliseconds > 0 &&
            duration.inMilliseconds < 86400000) {
          _storeDurationForTrackId(
            fileId,
            duration.inMilliseconds,
            persist: false,
            refreshVisibleAlbum: false,
          );
        }
      }
      final knownDurationMs = _validDurationMsFromValue(
        _knownTrackDurationsMs[fileId] ??
            _libraryTrackIndex[fileId]?['durationMs'],
      );
      final metadataDurationMs = fastDurationMs ?? knownDurationMs;
      if (metadataDurationMs != null) {
        _storeDurationForTrackId(
          fileId,
          metadataDurationMs,
          persist: false,
          refreshVisibleAlbum: false,
        );
      }

      Future<void> writeMetadata(TrackMetadata metadata) async {
        if (persistImmediately) {
          await _metaStore.put(file, metadata);
        } else {
          _metaStore.putMemory(file, metadata);
        }
      }

      if (fastResult != null && fastResult.hasUsefulText) {
        await writeMetadata(
          TrackMetadata(
            title: fastResult.title?.trim().isNotEmpty == true
                ? fastResult.title!.trim()
                : fallback['title'] ?? file.name ?? 'Unknown',
            artist: fastResult.artist?.trim().isNotEmpty == true
                ? fastResult.artist!.trim()
                : fallback['artist'] ?? 'Unknown Artist',
            album: fastResult.album?.trim().isNotEmpty == true
                ? fastResult.album!.trim()
                : null,
            year: fastResult.year,
            genre: fastResult.genre,
            trackNumber: fastResult.trackNumber,
            discNumber: fastResult.discNumber,
            coverPath: embeddedCoverPath,
            modifiedTime: file.modifiedTime?.toIso8601String(),
            size: file.size,
            durationMs: metadataDurationMs,
          ),
        );

        if (refreshUi) {
          _nowPlaying.refresh();
          if (mounted) setState(() {});
        }
        logApplied();
        return;
      }

      if (textOnly) {
        await writeMetadata(
          TrackMetadata(
            title: fallback['title'] ?? file.name ?? 'Unknown',
            artist: fallback['artist'] ?? 'Unknown Artist',
            album: null,
            year: null,
            genre: null,
            trackNumber: null,
            discNumber: null,
            coverPath: null,
            modifiedTime: file.modifiedTime?.toIso8601String(),
            size: file.size,
            durationMs: metadataDurationMs,
          ),
        );
        if (refreshUi) {
          _nowPlaying.refresh();
          if (mounted) setState(() {});
        }
        logApplied();
        return;
      }

      tempFile =
          await _downloadTrackToTemp(fileId, token, _audioExtension(file));
      final metadata = readMetadata(tempFile, getImage: false);

      final title = metadata.title?.trim().isNotEmpty == true
          ? metadata.title!.trim()
          : fallback['title'] ?? file.name ?? 'Unknown';

      final artist = metadata.artist?.trim().isNotEmpty == true
          ? metadata.artist!.trim()
          : fallback['artist'] ?? 'Unknown Artist';

      final album = metadata.album?.trim().isNotEmpty == true
          ? metadata.album!.trim()
          : null;

      await writeMetadata(
        TrackMetadata(
          title: title,
          artist: artist,
          album: album,
          year: null,
          genre: null,
          trackNumber: metadata.trackNumber,
          discNumber: metadata.discNumber,
          coverPath: embeddedCoverPath,
          modifiedTime: file.modifiedTime?.toIso8601String(),
          size: file.size,
          durationMs: metadataDurationMs,
        ),
      );

      if (refreshUi) {
        _nowPlaying.refresh();
        if (mounted) setState(() {});
      }
      logApplied();
    } catch (_) {
      return;
    } finally {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _prefetchMetadataForTracks(List<drive.File> tracks) async {
    if (_user == null || tracks.isEmpty) return;

    try {
      final authHeaders = await _user!.authHeaders;
      final bearer =
          authHeaders['Authorization'] ?? authHeaders['authorization'] ?? '';
      if (!bearer.startsWith('Bearer ')) return;
      final token = bearer.substring(7);

      final client = http.Client();
      final controller = _ScanConcurrencyController(
        initialConcurrency: 6,
        maxConcurrency: 8,
      );

      try {
        await _runWithConcurrency<drive.File>(
          tracks,
          controller,
          (track, index) async {
            if (!mounted) return;
            await _loadMetadataFor(
              track,
              token,
              client: client,
              refreshUi: false,
            );
          },
        );
      } finally {
        client.close();
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _loadMetadataForCurrentAlbum() async {
    if (_user == null || _albumTracks.isEmpty || _albumMetadataLoading) return;

    if (_loadingMetadata) {
      _showError(
          'Library metadata scan is already running. Cancel it in Settings first.');
      return;
    }

    final missing = _albumTracks.where((track) {
      final metadata = _metaStore.peekFresh(track);
      final trackId = DriveUtils.effectiveId(track);
      final durationMissing = trackId == null
          ? true
          : _validDurationMsFromValue(
                    _knownTrackDurationsMs[trackId] ??
                        _libraryTrackIndex[trackId]?['durationMs'],
                  ) ==
                  null &&
              _validDurationMsFromValue(metadata?.durationMs) == null;
      return metadata == null || durationMissing;
    }).toList();

    if (missing.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Metadata is already loaded for this album.',
            style: GoogleFonts.inter(
                color: Colors.black, fontWeight: FontWeight.w800),
          ),
          backgroundColor: _accentDefault,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _albumMetadataLoading = true;
      _albumMetadataDone = 0;
      _albumMetadataTotal = missing.length;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Loading metadata for this album...',
          style: GoogleFonts.inter(
              color: Colors.black, fontWeight: FontWeight.w800),
        ),
        backgroundColor: _accentDefault,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final authHeaders = await _user!.authHeaders;
      final bearer =
          authHeaders['Authorization'] ?? authHeaders['authorization'] ?? '';
      if (!bearer.startsWith('Bearer ')) {
        throw Exception('Could not get Google token.');
      }

      final token = bearer.substring(7);
      final client = http.Client();
      final controller = _ScanConcurrencyController(
        initialConcurrency: 6,
        maxConcurrency: 8,
      );
      int tracksProcessed = 0;

      try {
        await _runWithConcurrency<drive.File>(
          missing,
          controller,
          (track, index) async {
            if (!mounted) return;
            await _loadMetadataFor(
              track,
              token,
              albumRecord: _viewingAlbum,
              textOnly: true,
              persistImmediately: false,
              refreshUi: false,
              client: client,
            );
            if (mounted) {
              setState(() => _albumMetadataDone++);
            }
            tracksProcessed++;
            if (tracksProcessed % 100 == 0) {
              await _metaStore.persistNow();
            }
          },
        );
      } finally {
        client.close();
      }

      if (!mounted) return;

      // Final metadata cache flush.
      await _metaStore.persistNow();

      if (_viewingAlbum != null) {
        final sorted = _sortTracksForAlbum(_albumTracks);
        _albumTracksCache[_viewingAlbum!['id'] ?? ''] = sorted;
        _albumTracks = sorted;
        _indexAlbumFromTracks(_viewingAlbum!, sorted, save: true);
        _indexTracksForAlbum(_viewingAlbum!, sorted);
        await _saveLibraryTrackIndex();
      }

      setState(() => _albumMetadataLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Metadata loaded and cached for ${missing.length} tracks.',
            style: GoogleFonts.inter(
                color: Colors.black, fontWeight: FontWeight.w800),
          ),
          backgroundColor: _accentDefault,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _albumMetadataLoading = false);
        _showError('Metadata load failed: $e');
      }
    }
  }
}
