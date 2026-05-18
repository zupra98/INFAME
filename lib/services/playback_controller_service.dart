part of '../main.dart';

extension _PlaybackControllerServiceExtension on _MainScreenState {
  Future<void> _playSong(
    drive.File file, {
    List<drive.File>? queue,
    int? idx,
    String? coverUrl,
    List<Color>? colors,
    bool autoPlay = true,
    String? triggerReason,
  }) async {
    _ensureAudioServicePlayerAttached();
    final fileId = DriveUtils.effectiveId(file);
    if (fileId == null) return;
    final isLocalTrack = DriveUtils.isLocalFile(file);
    if (!isLocalTrack && _user == null) return;

    final requestSerial = ++_playRequestSerial;
    final activeQueue = _cleanPlaybackQueue(queue, file);
    debugPrint(
        'Queue set from album length=${activeQueue.length} index=${idx ?? 0}');
    final wantedKey = _trackKey(file);

    var activeIndex = -1;
    if (idx != null &&
        idx >= 0 &&
        idx < activeQueue.length &&
        _trackKey(activeQueue[idx]) == wantedKey) {
      activeIndex = idx;
    }
    if (activeIndex < 0) {
      activeIndex = activeQueue.indexWhere((f) => _trackKey(f) == wantedKey);
    }
    if (activeIndex < 0 || activeIndex >= activeQueue.length) activeIndex = 0;

    final activeFile = activeQueue[activeIndex];
    final activeFileId = DriveUtils.effectiveId(activeFile) ?? fileId;
    final activeColors = List<Color>.from(colors ?? _currentDynamicColors);
    final resolvedCoverUrl = _resolveCurrentTrackCover(
      activeFile,
      queue: activeQueue,
      idx: activeIndex,
      fallbackCoverUrl: coverUrl,
    );

    try {
      _changingTrack = true;

      String token = '';
      if (!isLocalTrack) {
        final authHeaders = await _user!.authHeaders;
        if (requestSerial != _playRequestSerial) return;

        final bearer =
            authHeaders['Authorization'] ?? authHeaders['authorization'] ?? '';
        if (bearer.startsWith('Bearer ')) token = bearer.substring(7);
      }

      _nowPlaying.setTrack(
        activeFile,
        activeQueue,
        activeIndex,
        coverUrl: resolvedCoverUrl,
        colors: activeColors,
      );
      _infameAudioHandler?.updateMediaItem(
        _mediaItemForCurrentTrack(
          activeFile,
          queue: activeQueue,
          queueIndex: activeIndex,
          coverUrl: resolvedCoverUrl,
        ),
      );
      assert(() {
        final mediaTitle = (DriveUtils.getTrackMeta(activeFile)['title'] ?? '')
                .trim()
                .isNotEmpty
            ? (DriveUtils.getTrackMeta(activeFile)['title'] ?? '').trim()
            : (activeFile.name ?? 'Unknown Track');
        debugPrint('AudioService media item -> title=$mediaTitle');
        return true;
      }());
      _syncAudioServicePlaybackState();
      _saveLastPlayed(activeFile, coverUrl: resolvedCoverUrl);
      if (isLocalTrack) {
        _loadMetadataForLocal(activeFile, albumRecord: _viewingAlbum);
      } else {
        _loadMetadataFor(activeFile, token, albumRecord: _viewingAlbum);
      }

      final knownSourceLength = int.tryParse(activeFile.size ?? '') ??
          int.tryParse(_libraryTrackIndex[activeFileId]?['size'] ?? '');
      final source = isLocalTrack
          ? AudioSource.uri(DriveUtils.localAudioUri(activeFile)!)
          : DriveAudioSource(
              activeFileId,
              token,
              knownSourceLength: knownSourceLength,
            );
      debugPrint(
        'Infame _playSong loading ${source.runtimeType} '
        'id=$activeFileId name=${activeFile.name}',
      );
      _durationCacheTrackKey = '';
      await _player.stop();
      if (requestSerial != _playRequestSerial) return;

      await _player
          .setLoopMode(_nowPlaying.repeatOne ? LoopMode.one : LoopMode.off);
      try {
        await _player.setAudioSource(source);
      } catch (e, st) {
        debugPrint('Infame _playSong setAudioSource failed: $e');
        debugPrint('$st');
        rethrow;
      }
      if (requestSerial != _playRequestSerial) return;

      _durationCacheTrackKey = _trackKey(activeFile);
      _cacheCurrentPlaybackDuration(_player.duration);

      if (autoPlay) {
        if (triggerReason != null) {
          debugPrint('AutoAdvance calling player.play after load');
        }
        await _player.play();
        if (triggerReason != null) {
          unawaited(_ensureAutoAdvancedTrackAudiblyStarts(
            requestSerial,
            _trackKey(activeFile),
          ));
        }
      }
      await Future<void>.delayed(Duration.zero);
      _infameAudioHandler?.syncPlaybackStateFromPlayer();
      _syncAudioServicePlaybackState();
      _recordPlay(activeFile, coverUrl: resolvedCoverUrl);
      if (triggerReason != null) {
        debugPrint(
            'AutoAdvance completed next started playing=${_player.playing}');
      }
      debugPrint(
          'Infame playback -> index=$activeIndex/${activeQueue.length} id=$activeFileId name=${activeFile.name}');
    } catch (e, st) {
      debugPrint('Infame _playSong failed: $e');
      debugPrint('$st');
      _showError('Playback error: $e');
    } finally {
      _changingTrack = false;
    }
  }

  int _currentQueueIndex(List<drive.File> queue) {
    final current = _nowPlaying.track;
    final currentKey = current == null ? '' : _trackKey(current);

    if (currentKey.isNotEmpty) {
      final actualIndex =
          queue.indexWhere((track) => _trackKey(track) == currentKey);
      if (actualIndex >= 0) return actualIndex;
    }

    if (_nowPlaying.queueIndex >= 0 && _nowPlaying.queueIndex < queue.length) {
      return _nowPlaying.queueIndex;
    }

    return 0;
  }

  int _nextPlayableIndex(List<drive.File> queue, int baseIndex,
      {required bool reverse}) {
    if (queue.isEmpty) return -1;
    final current = _nowPlaying.track;
    final currentKey = current == null ? '' : _trackKey(current);

    for (int step = 1; step <= queue.length; step++) {
      final raw = reverse ? baseIndex - step : baseIndex + step;
      final idx = raw % queue.length;
      final normalized = idx < 0 ? idx + queue.length : idx;
      if (normalized < 0 || normalized >= queue.length) continue;
      if (queue.length == 1) return normalized;
      if (_trackKey(queue[normalized]) != currentKey) return normalized;
    }

    return queue.length == 1 ? 0 : -1;
  }

  Future<void> _playNext({bool autoAdvance = false}) async {
    final queue = _cleanPlaybackQueue(
        _nowPlaying.queue,
        _nowPlaying.track ??
            (_albumTracks.isNotEmpty ? _albumTracks.first : drive.File()));
    if (queue.isEmpty) return;

    if (_nowPlaying.repeatOne && autoAdvance) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    final baseIndex = _currentQueueIndex(queue);
    int nextIndex;

    if (_nowPlaying.shuffleEnabled && queue.length > 1) {
      final random = math.Random();
      final currentKey =
          _nowPlaying.track == null ? '' : _trackKey(_nowPlaying.track!);
      do {
        nextIndex = random.nextInt(queue.length);
      } while (queue.length > 1 && _trackKey(queue[nextIndex]) == currentKey);
    } else {
      nextIndex = _nextPlayableIndex(queue, baseIndex, reverse: false);
      if (autoAdvance &&
          (nextIndex < 0 || nextIndex <= baseIndex && queue.length > 1)) {
        await _player.pause();
        await _player.seek(Duration.zero);
        return;
      }
    }

    if (nextIndex < 0 || nextIndex >= queue.length) return;

    debugPrint(
        'Infame next -> base=$baseIndex next=$nextIndex len=${queue.length} current=${_nowPlaying.track?.name} nextName=${queue[nextIndex].name}');
    final nextFile = queue[nextIndex];
    await _playSong(
      nextFile,
      queue: queue,
      idx: nextIndex,
      coverUrl: _resolveCurrentTrackCover(
        nextFile,
        queue: queue,
        idx: nextIndex,
        fallbackCoverUrl: _nowPlaying.currentCoverUrl,
      ),
      colors: _nowPlaying.dynamicColors,
    );
  }

  Future<void> _playPrev() async {
    final pos = _player.position;

    if (pos.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }

    final fallback = _nowPlaying.track ??
        (_albumTracks.isNotEmpty ? _albumTracks.first : drive.File());
    final queue = _cleanPlaybackQueue(_nowPlaying.queue, fallback);
    if (queue.isEmpty) return;

    final baseIndex = _currentQueueIndex(queue);
    final prevIndex = _nextPlayableIndex(queue, baseIndex, reverse: true);
    if (prevIndex < 0 || prevIndex >= queue.length) return;

    debugPrint(
        'Infame prev -> base=$baseIndex prev=$prevIndex len=${queue.length} current=${_nowPlaying.track?.name} prevName=${queue[prevIndex].name}');
    final prevFile = queue[prevIndex];
    await _playSong(
      prevFile,
      queue: queue,
      idx: prevIndex,
      coverUrl: _resolveCurrentTrackCover(
        prevFile,
        queue: queue,
        idx: prevIndex,
        fallbackCoverUrl: _nowPlaying.currentCoverUrl,
      ),
      colors: _nowPlaying.dynamicColors,
    );
  }

  String _formatDurationLabel(Duration duration) =>
      _formatDurationLabelFromPart(duration);

  String _trackDurationLabel(drive.File file) {
    final key = _trackKey(file);
    if (key.isEmpty) return '--:--';

    // Priority:
    // 1) TrackMetadata duration (if present)
    // 2) known/cache duration by stable file id
    // 3) currently loaded player duration, but only for this exact current track
    // 4) placeholder
    final durationMs = _durationMsForTrack(file);
    if (durationMs != null && durationMs > 0) {
      _setKnownTrackDuration(key, durationMs);
      return _formatDurationMs(durationMs);
    }

    final current = _nowPlaying.track ?? _nowPlaying.currentTrack;
    final currentKey = current == null ? '' : _trackKey(current);
    if (currentKey == key) {
      final liveDurationMs =
          _validDurationMsFromValue(_player.duration?.inMilliseconds);
      if (liveDurationMs != null) {
        _setKnownTrackDuration(key, liveDurationMs);
        return _formatDurationLabel(Duration(milliseconds: liveDurationMs));
      }
    }

    return '--:--';
  }

  void _addTracksPlayNext(List<drive.File> tracks) {
    debugPrint('Queue playNext inserted=${tracks.length}');
    _enqueueTracks(tracks, insertAfterCurrent: true);
  }

  void _addTracksToQueueEnd(List<drive.File> tracks) {
    debugPrint('Queue addToQueue appended=${tracks.length}');
    _enqueueTracks(tracks, insertAfterCurrent: false);
  }

  void _enqueueTracks(List<drive.File> tracks,
      {required bool insertAfterCurrent}) {
    final current = _nowPlaying.track;
    if (current == null) {
      _showError('Play something first.');
      return;
    }

    final currentKey = _trackKey(current);
    if (currentKey.isEmpty) {
      _showError('Play something first.');
      return;
    }

    final uniqueTracks = <drive.File>[];
    final seenKeys = <String>{};
    for (final track in tracks) {
      final key = _trackKey(track);
      if (key.isEmpty || key == currentKey || seenKeys.contains(key)) continue;
      seenKeys.add(key);
      uniqueTracks.add(track);
    }

    if (uniqueTracks.isEmpty) return;

    final updatedQueue = _cleanPlaybackQueue(_nowPlaying.queue, current);
    updatedQueue.removeWhere((track) {
      final key = _trackKey(track);
      return key != currentKey && seenKeys.contains(key);
    });

    final currentIndex =
        updatedQueue.indexWhere((track) => _trackKey(track) == currentKey);
    if (currentIndex < 0) {
      _showError('Play something first.');
      return;
    }

    final insertIndex =
        insertAfterCurrent ? currentIndex + 1 : updatedQueue.length;
    final safeInsertIndex = insertIndex < 0
        ? 0
        : insertIndex > updatedQueue.length
            ? updatedQueue.length
            : insertIndex;

    updatedQueue.insertAll(safeInsertIndex, uniqueTracks);
    _nowPlaying.queue = updatedQueue;
    _nowPlaying.queueIndex =
        updatedQueue.indexWhere((track) => _trackKey(track) == currentKey);
    debugPrint(
        'Queue ${insertAfterCurrent ? 'playNext inserted' : 'addToQueue appended'}=${uniqueTracks.length} index=${_nowPlaying.queueIndex} length=${updatedQueue.length}');
    _nowPlaying.refresh();
    if (mounted) setState(() {});
    _showSuccess(insertAfterCurrent ? 'Added next' : 'Added to queue.');
  }

  Future<void> _playQueueIndex(int index) async {
    final current = _nowPlaying.track;
    if (current == null) return;
    final queue = _cleanPlaybackQueue(_nowPlaying.queue, current);
    if (index < 0 || index >= queue.length) return;
    final track = queue[index];
    debugPrint('Queue play index=$index');
    await _playSong(
      track,
      queue: queue,
      idx: index,
      coverUrl: _resolveCurrentTrackCover(
        track,
        queue: queue,
        idx: index,
        fallbackCoverUrl: _nowPlaying.currentCoverUrl,
      ),
      colors: _nowPlaying.dynamicColors,
    );
  }

  void _removeQueueItemAt(int index) {
    final current = _nowPlaying.track;
    if (current == null) return;
    final currentKey = _trackKey(current);
    final queue = _cleanPlaybackQueue(_nowPlaying.queue, current);
    if (index < 0 || index >= queue.length) return;
    if (_trackKey(queue[index]) == currentKey) return;
    queue.removeAt(index);
    final nextCurrentIndex =
        queue.indexWhere((track) => _trackKey(track) == currentKey);
    _nowPlaying.queue = queue;
    _nowPlaying.queueIndex = nextCurrentIndex < 0 ? 0 : nextCurrentIndex;
    _nowPlaying.refresh();
    if (mounted) setState(() {});
  }

  void _clearUpcomingQueue() {
    final current = _nowPlaying.track;
    if (current == null) return;
    final currentKey = _trackKey(current);
    final queue = _cleanPlaybackQueue(_nowPlaying.queue, current);
    final currentIndex =
        queue.indexWhere((track) => _trackKey(track) == currentKey);
    if (currentIndex < 0) return;
    final removed = queue.length - currentIndex - 1;
    if (removed <= 0) return;
    queue.removeRange(currentIndex + 1, queue.length);
    _nowPlaying.queue = queue;
    _nowPlaying.queueIndex = currentIndex;
    _nowPlaying.refresh();
    debugPrint('Queue clear upcoming count=$removed');
    if (mounted) setState(() {});
    _showSuccess('Cleared upcoming queue.');
  }

  void _showError(String msg) => _showErrorFromPart(msg);

  void _showCoverZoom(String heroTag, String coverUrl, List<Color> gradient) =>
      _showCoverZoomFromPart(heroTag, coverUrl, gradient);
}
