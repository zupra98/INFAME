import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

const bool kVerboseAudioServiceLogs = false;

void _audioServiceVerboseLog(String message) {
  if (kVerboseAudioServiceLogs) debugPrint(message);
}

class InfameAudioHandler extends BaseAudioHandler with SeekHandler {
  AudioPlayer? _player;
  StreamSubscription<PlaybackEvent>? _playerEventSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<ProcessingState>? _processingStateSub;
  Future<void> Function()? _onPlay;
  Future<void> Function()? _onPause;
  Future<void> Function()? _onStop;
  Future<void> Function()? _onSkipToNext;
  Future<void> Function()? _onSkipToPrevious;
  Future<void> Function(Duration position)? _onSeek;

  void bindCallbacks({
    Future<void> Function()? onPlay,
    Future<void> Function()? onPause,
    Future<void> Function()? onStop,
    Future<void> Function()? onSkipToNext,
    Future<void> Function()? onSkipToPrevious,
    Future<void> Function(Duration position)? onSeek,
  }) {
    _onPlay = onPlay;
    _onPause = onPause;
    _onStop = onStop;
    _onSkipToNext = onSkipToNext;
    _onSkipToPrevious = onSkipToPrevious;
    _onSeek = onSeek;
  }

  void attachPlayer(AudioPlayer player) {
    _player = player;
    _playerEventSub?.cancel();
    _playingSub?.cancel();
    _processingStateSub?.cancel();
    _playerEventSub = player.playbackEventStream.listen((event) {
      _broadcastPlaybackState();
    });
    _playingSub = player.playingStream.listen((_) {
      _broadcastPlaybackState();
    });
    _processingStateSub = player.processingStateStream.listen((_) {
      _broadcastPlaybackState();
    });
    _audioServiceVerboseLog('AudioService handler attached to player');
    _broadcastPlaybackState();
  }

  void detachPlayer() {
    _playerEventSub?.cancel();
    _playerEventSub = null;
    _playingSub?.cancel();
    _playingSub = null;
    _processingStateSub?.cancel();
    _processingStateSub = null;
    _player = null;
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    this.mediaItem.add(mediaItem);
    _audioServiceVerboseLog(
        'AudioService media item -> title=${mediaItem.title}');
    _broadcastPlaybackState();
  }

  void updatePlaybackState({
    required bool isPlaying,
    required ProcessingState processingState,
    required Duration position,
    required Duration bufferedPosition,
    required double speed,
  }) {
    final audioProcessingState = isPlaying
        ? AudioProcessingState.ready
        : _mapProcessingState(processingState);
    playbackState.add(
      PlaybackState(
        controls: <MediaControl>[
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: audioProcessingState,
        playing: isPlaying,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
        speed: speed,
        systemActions: const {
          MediaAction.seek,
        },
      ),
    );
    _audioServiceVerboseLog(
      'AudioService state -> playing=$isPlaying processing=${audioProcessingState.name}',
    );
  }

  void syncPlaybackStateFromPlayer() {
    _broadcastPlaybackState();
  }

  void _broadcastPlaybackState() {
    final player = _player;
    if (player == null) return;

    final playing = player.playing;
    final processingState = playing
        ? AudioProcessingState.ready
        : _mapProcessingState(player.processingState);
    playbackState.add(
      PlaybackState(
        controls: <MediaControl>[
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        systemActions: const {
          MediaAction.seek,
        },
      ),
    );
    _audioServiceVerboseLog(
      'AudioService state -> playing=$playing processing=${processingState.name}',
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  @override
  Future<void> play() async {
    await _onPlay?.call();
  }

  @override
  Future<void> pause() async {
    await _onPause?.call();
  }

  @override
  Future<void> stop() async {
    debugPrint('AudioService stop requested');
    try {
      await _onStop?.call();
    } catch (e) {
      debugPrint('AudioService stop callback failed: $e');
    }
    try {
      await _player?.stop();
    } catch (e) {
      debugPrint('AudioService player stop failed: $e');
    }
    playbackState.add(
      PlaybackState(
        controls: const [],
        androidCompactActionIndices: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
        systemActions: const {},
      ),
    );
    debugPrint('AudioService stopped');
    detachPlayer();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _onSeek?.call(position);
  }

  @override
  Future<void> skipToNext() async {
    await _onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await _onSkipToPrevious?.call();
  }
}
