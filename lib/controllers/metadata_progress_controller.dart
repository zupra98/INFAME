part of '../main.dart';

extension _MetadataProgressControllerExtension on _MainScreenState {
  void _startMetadataProgressPolling() {
    _metadataProgressPoller?.cancel();
    _metadataProgressPoller = Timer.periodic(const Duration(seconds: 1), (_) {
      _pollMetadataProgressSnapshot();
    });

    _pollMetadataProgressSnapshot();
  }

  void _stopMetadataProgressPoller({String? reason}) {
    _metadataProgressPoller?.cancel();
    _metadataProgressPoller = null;
    if (reason != null) {
      debugPrint('MetadataProgressPoller stopped reason=$reason');
    }
  }

  Future<void> _pollMetadataProgressSnapshot() async {
    try {
      String? raw = await FlutterForegroundTask.getData<String>(
          key: _metadataProgressPrefsKey);

      if (raw == null || raw.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(_metadataProgressPrefsKey);
      }

      if (raw == null || raw.isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is Map) {
        final normalized = Map<String, dynamic>.from(decoded);

        // If Android killed the foreground task but the last saved progress
        // still says running, do not leave the UI stuck forever.
        if (normalized['running'] == true && Platform.isAndroid) {
          final serviceRunning = await FlutterForegroundTask.isRunningService;
          final updatedAt = (normalized['updatedAt'] as num?)?.toInt() ?? 0;
          final ageMs = DateTime.now().millisecondsSinceEpoch - updatedAt;

          if (!serviceRunning && updatedAt > 0 && ageMs > 8000) {
            normalized['running'] = false;
            normalized['phase'] = 'Stopped';
            normalized['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
            _saveMetadataProgressSnapshot(normalized);
          }
        }

        // Stop polling if scan is not running
        if (normalized['running'] != true) {
          _stopMetadataProgressPoller(reason: 'notRunning');
          return;
        }

        _applyMetadataProgressData(normalized);
      }
    } catch (_) {}
  }

  void _applyMetadataProgressData(Map data) {
    if (!mounted) return;

    final stamp = (data['updatedAt'] as num?)?.toInt() ?? 0;
    if (stamp != 0 && stamp == _lastMetadataProgressStamp) return;
    if (stamp != 0) _lastMetadataProgressStamp = stamp;

    final wasRunning = _loadingMetadata;
    final running = data['running'] == true;

    final nextDone = (data['done'] as num?)?.toInt() ?? _metadataDone;
    final nextTotal = (data['total'] as num?)?.toInt() ?? _metadataTotal;
    final nextFast = (data['fast'] as num?)?.toInt() ?? _metadataFast;
    final nextDeep = (data['deep'] as num?)?.toInt() ?? _metadataDeep;
    final nextFailed = (data['failed'] as num?)?.toInt() ?? _metadataFailed;
    final nextPhase = (data['phase'] ?? _metadataPhase).toString();

    final changed = _loadingMetadata != running ||
        _metadataDone != nextDone ||
        _metadataTotal != nextTotal ||
        _metadataFast != nextFast ||
        _metadataDeep != nextDeep ||
        _metadataFailed != nextFailed ||
        _metadataPhase != nextPhase;

    if (!changed) return;

    setState(() {
      _loadingMetadata = running;
      _metadataDone = nextDone;
      _metadataTotal = nextTotal;
      _metadataFast = nextFast;
      _metadataDeep = nextDeep;
      _metadataFailed = nextFailed;
      _metadataPhase = nextPhase;
    });
    _settingsSheetSetState?.call(() {});

    // When the foreground scanner finishes, do not write the old in-memory
    // duration/index maps back to SharedPreferences. First merge the results
    // saved by the background service, then refresh album covers and UI state.
    if (wasRunning && !running) {
      _flushPendingAlbumCovers();
      _finalMetadataRefreshDone = true;
      _syncForegroundMetadataResults();
    }
  }

  Future<void> _requestForegroundMetadataPermissions() async {
    if (!Platform.isAndroid) return;

    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    assert(() {
      debugPrint('Notification permission status: $permission');
      return true;
    }());
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
      final afterRequest =
          await FlutterForegroundTask.checkNotificationPermission();
      assert(() {
        debugPrint('Notification permission after request: $afterRequest');
        return true;
      }());
    }
  }

  void _initForegroundMetadataService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'musix_metadata_scan',
        channelName: 'Infame metadata scan',
        channelDescription:
            'Shows progress while Infame scans Google Drive music metadata.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(3000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  void _onMetadataTaskData(Object data) {
    if (data is! Map) return;

    if (data['type'] == 'duration_found') {
      final fileId = data['fileId']?.toString();
      final durationMs = _validDurationMsFromValue(data['durationMs']);
      if (fileId != null && durationMs != null) {
        _setKnownTrackDuration(fileId, durationMs);
        if (mounted) setState(() {});
      }
      return;
    }

    if (data['type'] == 'album_cover_found') {
      final albumId =
          data['albumKey']?.toString() ?? data['albumId']?.toString() ?? '';
      final coverPath = data['coverPath']?.toString() ?? '';
      _queueAlbumCoverFromMetadataScan(albumId, coverPath);
      return;
    }

    // Handle metadata progress messages
    if (data['type'] != 'metadata_progress') return;
    _applyMetadataProgressData(data);
  }

  String _metadataStatusLabel({bool includeTapToCancel = false}) {
    if (!_loadingMetadata) {
      if (_metadataPhase == 'Complete' && _metadataTotal > 0) {
        return 'Last scan complete â€¢ $_metadataTotal tracks';
      }
      return 'Metadata scanner is idle';
    }

    if (_metadataTotal <= 0) {
      final phase =
          _metadataPhase.trim().isEmpty ? 'Preparing' : _metadataPhase;
      return '$phase metadata scan...';
    }

    final base =
        'Scanning metadata $_metadataDone/$_metadataTotal â€¢ Fast: $_metadataFast â€¢ Deep: $_metadataDeep â€¢ Failed: $_metadataFailed';
    return includeTapToCancel ? '$base â€” tap to cancel' : base;
  }

  String _glassModeLabel(String mode) {
    if (mode == glassModePerformance) return 'Performance';
    if (mode == glassModePretty) return 'Pretty';
    return 'Balanced';
  }

  String _glassModeDescription(String mode) {
    if (mode == glassModePerformance) {
      return 'Fastest mode. Fake glass only, lighter shadows, best for huge libraries.';
    }
    if (mode == glassModePretty) {
      return 'Most glassy mode. Real blur on fixed UI only, heavier glow, still avoids blur in lists.';
    }
    return 'Recommended. Real blur only on fixed UI like nav and player, fake glass in scrolling lists.';
  }

  void _cycleGlassMode([StateSetter? setSheetState]) {
    final next = _glassMode == glassModePerformance
        ? _glassModeBalanced
        : _glassMode == _glassModeBalanced
            ? glassModePretty
            : glassModePerformance;

    setState(() {
      _glassMode = next;
      glassModeNotifier.value = next;
    });
    setSheetState?.call(() {});
    _saveUiPreferences();
  }

  void _cycleAccentMode([StateSetter? setSheetState]) {
    final next = _accentMode == _accentModeChampagne
        ? _accentModeWhite
        : _accentMode == _accentModeWhite
            ? _accentModeBlue
            : _accentMode == _accentModeBlue
                ? _accentModePink
                : _accentModeChampagne;

    setState(() => _accentMode = next);
    setSheetState?.call(() {});
    _saveUiPreferences();
  }
}
