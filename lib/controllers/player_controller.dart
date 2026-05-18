part of '../main.dart';

extension _PlayerControllerExtension on _MainScreenState {
  String _resolveCurrentTrackCover(
    drive.File file, {
    List<drive.File>? queue,
    int? idx,
    String? fallbackCoverUrl,
  }) {
    final fileId = DriveUtils.effectiveId(file) ?? '';
    final trackRecord = fileId.isNotEmpty ? _libraryTrackIndex[fileId] : null;

    final recordCover = trackRecord?['albumCover']?.trim() ?? '';
    if (recordCover.isNotEmpty) return recordCover;

    final albumId = trackRecord?['albumId']?.trim() ?? '';
    if (albumId.isNotEmpty) {
      for (final album in _albums) {
        if ((album['id'] ?? '') == albumId) {
          final albumCover = _albumCoverForIndex(album).trim();
          if (albumCover.isNotEmpty) return albumCover;
          break;
        }
      }
    }

    if ((file.thumbnailLink ?? '').trim().isNotEmpty) {
      return file.thumbnailLink!.trim();
    }

    if (queue != null && idx != null && idx >= 0 && idx < queue.length) {
      final queuedFile = queue[idx];
      final queuedId = DriveUtils.effectiveId(queuedFile) ?? '';
      final queuedRecord =
          queuedId.isNotEmpty ? _libraryTrackIndex[queuedId] : null;
      final queuedCover = queuedRecord?['albumCover']?.trim() ?? '';
      if (queuedCover.isNotEmpty) return queuedCover;
      if ((queuedFile.thumbnailLink ?? '').trim().isNotEmpty) {
        return queuedFile.thumbnailLink!.trim();
      }
    }

    final directCover = fallbackCoverUrl?.trim() ?? '';
    if (directCover.isNotEmpty) return directCover;

    return '';
  }

  Uri? _safeArtUri(String? source) {
    final value = source?.trim() ?? '';
    if (value.isEmpty) return null;
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) return parsed;
    return Uri.file(value);
  }

  MediaItem _mediaItemForCurrentTrack(
    drive.File file, {
    required List<drive.File> queue,
    required int queueIndex,
    required String coverUrl,
  }) {
    final fileId = DriveUtils.effectiveId(file) ?? _trackKey(file);
    final trackRecord = fileId.isNotEmpty ? _libraryTrackIndex[fileId] : null;
    final meta = DriveUtils.getTrackMeta(file);
    final albumName =
        (trackRecord?['album'] ?? trackRecord?['albumName'] ?? '').trim();
    final title =
        (meta['title'] ?? trackRecord?['title'] ?? file.name ?? '').trim();
    final artist = (meta['artist'] ?? trackRecord?['artist'] ?? '').trim();

    return MediaItem(
      id: fileId,
      title: title.isNotEmpty ? title : (file.name ?? 'Unknown Track'),
      artist: artist.isNotEmpty ? artist : 'Unknown Artist',
      album: albumName,
      artUri: _safeArtUri(
        _resolveCurrentTrackCover(
          file,
          queue: queue,
          idx: queueIndex,
          fallbackCoverUrl: coverUrl,
        ),
      ),
      duration: _knownTrackDurations[_trackKey(file)],
    );
  }

  void _syncAudioServicePlaybackState() {
    final handler = _infameAudioHandlerInstance;
    if (handler == null) return;

    // Throttle notification updates to at most once per 200ms
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastNotificationUpdateMs < 200) return;
    _lastNotificationUpdateMs = nowMs;

    handler.updatePlaybackState(
      isPlaying: _player.playing,
      processingState: _player.processingState,
      position: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    );
  }

  void _indexTracksForAlbum(
      Map<String, String> album, List<drive.File> tracks) {
    final albumKey = _albumCacheKey(album, source: 'index_tracks');
    for (final track in tracks) {
      final trackId = DriveUtils.effectiveId(track);
      if (trackId == null || trackId.isEmpty) continue;

      final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      final trackMeta = DriveUtils.getTrackMeta(track);

      final albumCover = _albumCoverForIndex(album);

      // Preserve any duration that was already indexed, then prefer the
      // in-memory/persistent known-duration cache. If this track already has
      // parsed metadata duration, include it so album rows can show duration
      // without waiting for playback.
      final previousDurationMs =
          _validDurationMsFromValue(_libraryTrackIndex[trackId]?['durationMs']);
      final metadataDurationMs = _validDurationMsFromValue(meta?.durationMs) ??
          _validDurationMsFromValue(trackMeta['durationMs']);
      final durationMs = _knownTrackDurationsMs[trackId] ??
          previousDurationMs ??
          metadataDurationMs;
      if (durationMs != null) _setKnownTrackDuration(trackId, durationMs);

      final record = <String, String>{
        'id': trackId,
        'name': track.name ?? '',
        'albumId': albumKey,
        'albumName': (meta?.album?.trim().isNotEmpty == true)
            ? meta!.album!.trim()
            : (album['displayName'] ?? album['name'] ?? ''),
        'albumArtist': _canonicalArtistName(
          albumArtist: album['artist'],
          trackArtist: meta?.artist ?? trackMeta['artist']?.toString() ?? '',
          albumName: (meta?.album?.trim().isNotEmpty == true)
              ? meta!.album!.trim()
              : (album['displayName'] ?? album['name'] ?? ''),
        ),
        'albumCover': albumCover,
        'mimeType': track.mimeType ?? '',
        'thumbnailLink': track.thumbnailLink ?? '',
        'size': track.size ?? '0',
        'modifiedTime':
            track.modifiedTime?.millisecondsSinceEpoch.toString() ?? '',
        if (DriveUtils.isLocalFile(track)) 'source': 'local',
        if ((DriveUtils.localSourceRef(track) ?? '').isNotEmpty &&
            !DriveUtils.isContentUriString(DriveUtils.localSourceRef(track)!))
          'localPath': DriveUtils.localSourceRef(track)!,
        if ((DriveUtils.localSourceRef(track) ?? '').isNotEmpty &&
            DriveUtils.isContentUriString(DriveUtils.localSourceRef(track)!))
          'localUri': DriveUtils.localSourceRef(track)!,
        if (durationMs != null && durationMs > 0)
          'durationMs': durationMs.toString(),
      };

      if (meta != null) {
        final metaMap = meta.toMap();
        record['title'] = metaMap['title'] ?? '';
        record['artist'] = metaMap['artist'] ?? '';
        record['album'] = metaMap['album'] ?? '';
        record['year'] = metaMap['year'] ?? '';
        record['genre'] = metaMap['genre'] ?? '';
        record['trackNumber'] = metaMap['trackNumber'] ?? '';
        record['discNumber'] = metaMap['discNumber'] ?? '';
      } else {
        record['title'] = trackMeta['title']?.toString() ?? track.name ?? '';
        record['artist'] = trackMeta['artist']?.toString() ?? '';
        record['album'] = album['displayName'] ?? album['name'] ?? '';
        record['year'] = trackMeta['year']?.toString() ?? '';
        record['genre'] = trackMeta['genre']?.toString() ?? '';
        record['trackNumber'] = trackMeta['trackNumber']?.toString() ?? '';
        record['discNumber'] = trackMeta['discNumber']?.toString() ?? '';
      }

      _libraryTrackIndex[trackId] = record;
      _albumTracksCache[albumKey] = tracks;
    }
  }
}
