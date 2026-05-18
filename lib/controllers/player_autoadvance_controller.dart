part of '../main.dart';

extension _PlayerAutoadvanceControllerExtension on _MainScreenState {
  Future<void> _handleTrackCompleted({String reason = 'unknown'}) async {
    if (_changingTrack || _handlingPlaybackComplete) return;

    try {
      final currentTrack = _nowPlaying.track ?? _nowPlaying.currentTrack;
      if (currentTrack == null) return;

      final queue = _cleanPlaybackQueue(_nowPlaying.queue, currentTrack);
      if (queue.isEmpty) return;

      final currentKey = _trackKey(currentTrack);
      int currentIndex = _nowPlaying.queueIndex;
      if (currentIndex < 0 ||
          currentIndex >= queue.length ||
          _trackKey(queue[currentIndex]) != currentKey) {
        currentIndex =
            queue.indexWhere((track) => _trackKey(track) == currentKey);
      }
      if (currentIndex < 0) currentIndex = 0;

      final completionSignature =
          '$currentKey|$currentIndex|${_playRequestSerial.toString()}';
      if (_lastHandledCompletionSignature == completionSignature) return;

      _handlingPlaybackComplete = true;
      _autoAdvanceInProgress = true;
      _lastHandledCompletionSignature = completionSignature;
      debugPrint('AutoAdvance trigger reason=$reason');
      debugPrint(
          'Playback completed detected current=$currentIndex len=${queue.length}');

      if (_nowPlaying.repeatOne) {
        await _player.seek(Duration.zero);
        await _player.play();
        return;
      }

      final nextIndex = currentIndex + 1;
      if (nextIndex < queue.length) {
        debugPrint('AutoAdvance next index=$nextIndex/${queue.length}');
        debugPrint(
            'Playback completed -> next index=$nextIndex/${queue.length}');
        final nextFile = queue[nextIndex];
        final nextId = DriveUtils.effectiveId(nextFile) ?? _trackKey(nextFile);
        debugPrint('AutoAdvance loading next id=$nextId');
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
          autoPlay: true,
          triggerReason: reason,
        );
        debugPrint(
            'AutoAdvance completed next started playing=${_player.playing}');
        return;
      }

      debugPrint('Playback completed -> end of queue');
      await _player.pause();
      await _player.seek(Duration.zero);
    } catch (e) {
      _lastHandledCompletionSignature = '';
      _showError('Could not continue playback: $e');
    } finally {
      _handlingPlaybackComplete = false;
      _autoAdvanceInProgress = false;
    }
  }

  bool _tryAutoAdvanceCurrentTrack(String reason) {
    if (_autoAdvanceInProgress) {
      debugPrint('AutoAdvance skipped reason=alreadyInProgress source=$reason');
      return false;
    }

    final current = _nowPlaying.track ?? _nowPlaying.currentTrack;
    if (current == null) return false;
    final key = _trackKey(current);
    if (key.isEmpty) return false;

    final queue = _cleanPlaybackQueue(_nowPlaying.queue, current);
    int idx = _nowPlaying.queueIndex;
    if (idx < 0 || idx >= queue.length || _trackKey(queue[idx]) != key) {
      idx = queue.indexWhere((track) => _trackKey(track) == key);
    }
    if (idx < 0) idx = 0;

    final signature = '$key|$idx|${_playRequestSerial.toString()}';
    if (_lastHandledCompletionSignature == signature) return false;

    debugPrint('AutoAdvance started source=$reason');
    unawaited(_handleTrackCompleted(reason: reason));
    return true;
  }

  void _maybeAutoAdvanceAfterPlaybackStop() {
    if (_changingTrack || _handlingPlaybackComplete) return;
    if (_player.playing) return;

    final duration = _player.duration;
    final position = _player.position;
    if (duration == null || duration.inMilliseconds <= 0) return;
    if (position.inMilliseconds < math.max(0, duration.inMilliseconds - 900)) {
      return;
    }

    _tryAutoAdvanceCurrentTrack('stopped_near_end');
  }

  void _maybeAutoAdvanceFromPlaybackEvent(PlaybackEvent event) {
    if (_changingTrack || _handlingPlaybackComplete) return;
    final duration = event.duration ?? _player.duration;
    if (duration == null || duration.inMilliseconds <= 0) return;
    final thresholdMs = math.max(0, duration.inMilliseconds - 250);
    if (event.updatePosition.inMilliseconds < thresholdMs) return;
    _tryAutoAdvanceCurrentTrack('event_reached_end');
  }

  void _startPlaybackEndWatchdog() {
    _playbackEndWatchdog?.cancel();
    _playbackEndWatchdog = Timer.periodic(
      const Duration(milliseconds: 1000),
      (_) => _checkPlaybackEndWatchdog(),
    );
    debugPrint('PlaybackEndWatchdog started interval=1000ms');
  }

  void _stopPlaybackEndWatchdog({String? reason}) {
    _playbackEndWatchdog?.cancel();
    _playbackEndWatchdog = null;
    if (reason != null) {
      debugPrint('PlaybackEndWatchdog stopped reason=$reason');
    }
  }

  void _checkPlaybackEndWatchdog() {
    if (_changingTrack || _handlingPlaybackComplete) return;

    final duration = _player.duration;
    if (duration == null || duration.inMilliseconds <= 0) {
      _lastWatchdogPosition = Duration.zero;
      _watchdogNearEndTicks = 0;
      return;
    }

    final position = _player.position;
    final remainingMs = duration.inMilliseconds - position.inMilliseconds;
    final nearEnd = remainingMs <= 900 && position.inMilliseconds > 1000;

    if (!nearEnd) {
      _lastWatchdogPosition = position;
      _watchdogNearEndTicks = 0;
      return;
    }

    final movedMs =
        (position.inMilliseconds - _lastWatchdogPosition.inMilliseconds).abs();
    _lastWatchdogPosition = position;

    // Some Drive/FLAC streams can sit at the last few hundred ms with
    // processingState=ready and playing=true. In that case just_audio may not
    // emit completed until the user taps pause/play. Detect the stuck tail and
    // advance ourselves.
    final stuckAtTail = movedMs < 120;
    if (_player.playing && !stuckAtTail) {
      _watchdogNearEndTicks = 0;
      return;
    }

    _watchdogNearEndTicks++;
    if (_watchdogNearEndTicks < 2) return;

    _watchdogNearEndTicks = 0;
    _tryAutoAdvanceCurrentTrack(
      _player.playing ? 'watchdog_stuck_near_end' : 'watchdog_stopped_near_end',
    );
  }

  Future<void> _ensureAutoAdvancedTrackAudiblyStarts(
    int requestSerial,
    String activeKey,
  ) async {
    if (_autoAdvanceStartNudgeRunning) return;
    _autoAdvanceStartNudgeRunning = true;
    try {
      final before = _player.position;
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      if (requestSerial != _playRequestSerial) return;
      if (_trackKey(
              _nowPlaying.track ?? _nowPlaying.currentTrack ?? drive.File()) !=
          activeKey) {
        return;
      }
      if (!_player.playing ||
          _player.processingState != ProcessingState.ready) {
        return;
      }

      final after = _player.position;
      final movedMs = after.inMilliseconds - before.inMilliseconds;
      if (movedMs > 180) return;

      debugPrint(
          'AutoAdvance nudge: player reported playing but position did not move');
      await _player.pause();
      await Future<void>.delayed(const Duration(milliseconds: 35));
      if (!mounted || requestSerial != _playRequestSerial) return;
      await _player.play();
      _infameAudioHandler?.syncPlaybackStateFromPlayer();
      _syncAudioServicePlaybackState();
    } catch (e) {
      debugPrint('AutoAdvance nudge failed: $e');
    } finally {
      _autoAdvanceStartNudgeRunning = false;
    }
  }

  String _trackKey(drive.File file) {
    final id = DriveUtils.effectiveId(file);
    if (id != null && id.trim().isNotEmpty) return id.trim();
    return (file.name ?? '').trim().toLowerCase();
  }

  String _currentPlayingAlbumId() {
    final current = _nowPlaying.currentTrack ?? _nowPlaying.track;
    final currentId = (_nowPlaying.currentFileId?.trim().isNotEmpty == true)
        ? _nowPlaying.currentFileId!.trim()
        : current == null
            ? ''
            : (DriveUtils.effectiveId(current) ?? '').trim();
    if (currentId.isEmpty) return '';
    return (_libraryTrackIndex[currentId]?['albumId'] ?? '').trim();
  }

  drive.File? _resolveMiniPlayerTrack() {
    final current = _nowPlaying.currentTrack ?? _nowPlaying.track;
    if (current != null) return current;

    final currentId = _nowPlaying.currentFileId?.trim() ?? '';
    if (currentId.isNotEmpty) {
      final record = _libraryTrackIndex[currentId];
      final synthetic = drive.File()..id = currentId;
      final artist = (record?['artist'] ?? record?['trackArtist'] ?? '').trim();
      final title = (record?['title'] ?? record?['fileName'] ?? '').trim();
      if (artist.isNotEmpty && title.isNotEmpty) {
        synthetic.name = '$artist - $title';
      } else if (title.isNotEmpty) {
        synthetic.name = title;
      } else {
        synthetic.name = currentId;
      }
      return synthetic;
    }

    if (_nowPlaying.queue.isNotEmpty &&
        _nowPlaying.queueIndex >= 0 &&
        _nowPlaying.queueIndex < _nowPlaying.queue.length) {
      return _nowPlaying.queue[_nowPlaying.queueIndex];
    }

    if (_nowPlaying.queue.isNotEmpty) {
      return _nowPlaying.queue.first;
    }

    return null;
  }

  List<drive.File> _cleanPlaybackQueue(
      List<drive.File>? queue, drive.File file) {
    final fileKey = _trackKey(file);
    final source = (queue != null && queue.isNotEmpty)
        ? queue
        : _albumTracks.isNotEmpty
            ? _albumTracks
            : <drive.File>[file];

    final cleaned = <drive.File>[];
    final seen = <String>{};

    for (final item in source) {
      if (!DriveUtils.isAudio(item)) continue;
      final key = _trackKey(item);
      if (key.isEmpty) continue;
      if (seen.contains(key)) continue;
      seen.add(key);
      cleaned.add(item);
    }

    if (cleaned.isEmpty) return <drive.File>[file];

    final containsCurrent = cleaned.any((f) => _trackKey(f) == fileKey);
    if (!containsCurrent) {
      return <drive.File>[
        file,
        ...cleaned.where((f) => _trackKey(f) != fileKey)
      ];
    }

    return cleaned;
  }
}
