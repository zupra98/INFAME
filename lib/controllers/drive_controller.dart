part of '../main.dart';

extension _DriveControllerExtension on _MainScreenState {
  void _selectRootTab(int index, {bool animate = true}) {
    if (index < 0 || index > 2) return;

    debugPrint('MainTab select requested index=$index');
    setState(() {
      _navIndex = index;
      _viewingAlbum = null;
      _currentDynamicColors = List<Color>.from(_defaultDynamicColors);
    });

    void syncController() {
      if (!_pageController.hasClients) return;
      try {
        _pageController.jumpToPage(index);
      } catch (e) {
        debugPrint('MainTab jumpToPage failed for index=$index: $e');
      }
    }

    syncController();
    if (animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        syncController();
      });
    }

    assert(() {
      final pageValue =
          _pageController.hasClients ? _pageController.page : null;
      debugPrint(
        'MainTab selectedIndex=$_navIndex pageControllerPage=$pageValue',
      );
      return true;
    }());
  }

  void _openDriveSourcePage() {
    debugPrint('DriveSettings opened');
    final hasRootItems = _exploreFolder == null && _exploreItems.isNotEmpty;
    _exploreFolder = null;
    _navStack.clear();
    _driveExplorerLoadError = null;
    if (!hasRootItems) {
      _exploreItems = [];
      _driveExplorerAutoLoadAttempted = false;
    }
    _driveSettingsSetState?.call(() {});

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: _isDarkMode ? _darkBg : _lightBg,
          body: Stack(
            children: [
              StatefulBuilder(
                builder: (context, setState) {
                  _driveSettingsSetState = setState;
                  return SafeArea(bottom: false, child: buildDriveTab());
                },
              ),
              Positioned(
                top: 8,
                left: 8,
                child: SafeArea(
                  bottom: false,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: _isDarkMode ? Colors.white : _textPri,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureDriveExplorerLoaded(force: true);
    });
  }

  void _resetDriveExplorerToRoot() {
    _exploreFolder = null;
    _exploreItems = [];
    _loadingExplore = false;
    _driveExplorerAutoLoadAttempted = false;
    _driveExplorerLoadError = null;
    _navStack.clear();
    _driveSettingsSetState?.call(() {});
  }

  void _ensureDriveExplorerLoaded({bool force = false}) {
    if (_user == null) {
      debugPrint('Drive folder load failed with error: user not signed in');
      return;
    }

    if (_loadingExplore) {
      debugPrint('Drive folder load skipped because already loading');
      return;
    }
    if (_exploreFolder != null) return;
    if (_exploreItems.isNotEmpty) return;
    if (!force && _driveExplorerAutoLoadAttempted) return;

    _driveExplorerAutoLoadAttempted = true;
    _driveExplorerLoadError = null;
    unawaited(_fetchExplore(folderId: 'root'));
  }

  void _openSettingsSheet() => _openSettingsSheetFromPart();

  void _settingsSetState(VoidCallback fn) => setState(fn);

  Future<void> _startForegroundLibraryMetadataScan() async {
    if (_user == null || _albums.isEmpty || _loadingMetadata) return;

    final authHeaders = await _user!.authHeaders;
    final bearer =
        authHeaders['Authorization'] ?? authHeaders['authorization'] ?? '';
    if (!bearer.startsWith('Bearer ')) {
      _showError('Could not get Google token.');
      return;
    }

    final token = bearer.substring(7);

    await FlutterForegroundTask.saveData(key: 'metadata_token', value: token);
    await FlutterForegroundTask.saveData(
        key: 'metadata_albums', value: json.encode(_albums));

    final startingPayload = {
      'type': 'metadata_progress',
      'done': 0,
      'total': 0,
      'fast': 0,
      'deep': 0,
      'failed': 0,
      'phase': 'Starting',
      'running': true,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    _saveMetadataProgressSnapshot(startingPayload);

    setState(() {
      _loadingMetadata = true;
      _metadataDone = 0;
      _metadataTotal = 0;
      _metadataFast = 0;
      _metadataDeep = 0;
      _metadataFailed = 0;
      _metadataPhase = 'Starting';
      _finalMetadataRefreshDone = false;
    });
    _settingsSheetSetState?.call(() {});

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
      await Future.delayed(const Duration(milliseconds: 350));
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: _metadataScanServiceId,
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: 'Infame metadata scan',
      notificationText: 'Starting metadata scan...',
      notificationInitialRoute: '/',
      callback: metadataScanStartCallback,
    );

    if (result is ServiceRequestFailure) {
      if (mounted) {
        setState(() => _loadingMetadata = false);
        _showError('Could not start metadata service: ${result.error}');
      }
      return;
    }
  }

  Future<void> _cancelForegroundMetadataScan() async {
    if (!_loadingMetadata && !(await FlutterForegroundTask.isRunningService))
      return;

    setState(() {
      _loadingMetadata = false;
      _metadataPhase = 'Cancelled';
    });
    _settingsSheetSetState?.call(() {});

    final cancelledPayload = {
      'type': 'metadata_progress',
      'done': _metadataDone,
      'total': _metadataTotal,
      'fast': _metadataFast,
      'deep': _metadataDeep,
      'failed': _metadataFailed,
      'phase': 'Cancelled',
      'running': false,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    _saveMetadataProgressSnapshot(cancelledPayload);

    // Ask the task to stop cleanly first, then force-stop the foreground
    // service. This makes the Settings cancel button work even if the task is
    // busy in a Drive request and does not receive the cancel command quickly.
    FlutterForegroundTask.sendDataToTask('cancel_metadata_scan');
    await Future.delayed(const Duration(milliseconds: 450));

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }

    _metaStore.reload().then((_) {
      if (mounted) {
        _librarySearchTextCache.clear();
        setState(() {});
      }
    });
    _loadAlbums();
  }

  // â”€â”€ Auth â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _trySilentSignIn() async {
    final account = await _googleSignIn.signInSilently();

    if (!mounted) return;

    if (account != null) {
      setState(() => _user = account);
      _logStartupSourceState();
      _ensureDriveExplorerLoaded();
    } else {
      setState(() => _loadingSaved = false);
    }
  }

  Future<void> _signIn() async {
    if (_signingIn) return;

    setState(() => _signingIn = true);

    try {
      await _googleSignIn.signOut();
      final account = await _googleSignIn.signIn();

      if (!mounted) return;

      if (account != null) {
        setState(() => _user = account);
        await _loadAlbums();
        _ensureDriveExplorerLoaded();
      }
    } catch (e) {
      _showError('Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signOut() async {
    await _googleSignIn.signOut();
    await _player.stop();
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }

    _nowPlaying.clearTrack();

    if (!mounted) return;

    setState(() {
      _user = null;
      _albums = [];
      _navIndex = 0;
      _viewingAlbum = null;
      _albumTracks = [];
      _albumTracksCache.clear();
      _librarySearchTextCache.clear();
      _exploreFolder = null;
      _exploreItems = [];
      _driveExplorerAutoLoadAttempted = false;
      _driveExplorerLoadError = null;
      _navStack.clear();
      _currentDynamicColors = List<Color>.from(_defaultDynamicColors);
    });
  }

  // â”€â”€ Local Database â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
}
