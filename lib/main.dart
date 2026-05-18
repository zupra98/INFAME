// MUSIX MAIN.DART - MASSIVE GLASS UI UPDATE VERSION
// Safer library management, proper Settings, swipe tabs, calmer glass UI,
// album actions, foreground metadata scan status, search/sort library controls,
// and no rainbow header text.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musix/models/track_model.dart';
import 'models/player_state.dart';
import 'services/auth_service.dart';
import 'services/drive_audio_source.dart';
import 'services/playback_service.dart';
import 'widgets/shared/glassy_container.dart';

part 'constants/app_constants.dart';
part 'app/infame_app.dart';
part 'app/app_shell.dart';
part 'controllers/main_screen_controller.dart';
part 'controllers/artist_controller.dart';
part 'controllers/library_controller.dart';
part 'controllers/library_index_controller.dart';
part 'controllers/library_brain_controller.dart';
part 'controllers/metadata_progress_controller.dart';
part 'controllers/drive_controller.dart';
part 'controllers/drive_library_controller.dart';
part 'controllers/player_controller.dart';
part 'controllers/player_autoadvance_controller.dart';
part 'controllers/artwork_controller.dart';
part 'services/drive_utils.dart';
part 'services/library_persistence_service.dart';
part 'services/metadata_file_service.dart';
part 'services/metadata_library_service.dart';
part 'services/artwork_service.dart';
part 'services/palette_service.dart';
part 'services/playback_controller_service.dart';
part 'services/metadata_scan/metadata_store.dart';
part 'services/metadata_scan/fast_tag_reader.dart';
part 'services/metadata_scan/scan_concurrency.dart';
part 'services/metadata_scan/metadata_scan_task.dart';
part 'services/local_file_support/local_file_models.dart';
part 'services/local_file_support/local_file_core.dart';
part 'services/local_file_support/local_file_picker_service.dart';
part 'services/local_file_support/local_file_import_service.dart';
part 'services/local_file_support/local_metadata_artwork_service.dart';
part 'screens/home_screen.dart';
part 'screens/library_screen.dart';
part 'screens/drive_screen.dart';
part 'widgets/settings/settings_shared_widgets.dart';
part 'widgets/settings/settings_widgets.dart';
part 'widgets/home/home_cards.dart';
part 'widgets/home/home_sections.dart';
part 'widgets/home/home_widgets.dart';
part 'widgets/library/library_artist_widgets.dart';
part 'widgets/library/library_song_widgets.dart';
part 'widgets/library/library_album_widgets.dart';
part 'widgets/library/liked_widgets.dart';
part 'widgets/album/album_cards.dart';
part 'widgets/album/album_detail_widgets.dart';
part 'widgets/player/player_art_widgets.dart';
part 'widgets/player/lyrics_sheet.dart';
part 'widgets/player/queue_sheet.dart';
part 'widgets/player/mini_player.dart';
part 'widgets/player/full_screen_player.dart';
part 'widgets/player/player_action_widgets.dart';
part 'widgets/shared/navigation_widgets.dart';
part 'widgets/shared/search_widgets.dart';
part 'widgets/shared/main_visual_widgets.dart';
part 'widgets/background/background_widgets.dart';
part 'widgets/background/visual_widgets.dart';
part 'utils/color_utils.dart';
part 'utils/format_utils.dart';

const bool kVerbosePlaybackLogs = false;
const bool kVerboseUiLogs = false;
const bool kVerboseScanLogs = false;
const bool kAlbumKeyDebug = false;
const bool kAlbumDisplayDebug = false;
const bool kAlbumCoverDebug = false;
const bool kHomeCacheDebug = false;

final Stopwatch _startupBootStopwatch = Stopwatch();
bool _startupFirstFrameLogged = false;
int _startupSavedLocalAlbumCount = 0;
int _startupSavedDriveAlbumCount = 0;
bool _startupHasSelectedLocalFolders = false;
Future<void>? _audioServiceInitFuture;

void _verbosePlaybackLog(String message) {
  if (kVerbosePlaybackLogs) debugPrint(message);
}

void _verboseUiLog(String message) {
  if (kVerboseUiLogs) debugPrint(message);
}

void _verboseScanLog(String message) {
  if (kVerboseScanLogs) debugPrint(message);
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Compatibility helpers for the local metadata model Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
// These keep main.dart in sync even if lib/models/track_metadata.dart only has
// fromJson/toJson and plain fields.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _startupBootStopwatch
    ..reset()
    ..start();
  debugPrint('Startup minimal start');
  assert(() {
    debugPrint('main start');
    return true;
  }());
  FlutterForegroundTask.initCommunicationPort();
  await _loadStartupThemePreference();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  assert(() {
    debugPrint('runApp start');
    return true;
  }());
  debugPrint(
      'Perf Startup mainToRunApp=${_startupBootStopwatch.elapsedMilliseconds}');
  runApp(const MusixApp());
}

InfameAudioHandler? _infameAudioHandlerInstance;
bool _initialDarkMode = true;
const _themeModePrefsKey = 'infame_theme_mode';

Future<void> _loadStartupThemePreference() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    _initialDarkMode = prefs.getString(_themeModePrefsKey) != 'light';
    final rawAlbums = prefs.getString(_albumsPrefsKey);
    if (rawAlbums != null && rawAlbums.isNotEmpty) {
      final decoded = json.decode(rawAlbums);
      if (decoded is List) {
        var localCount = 0;
        var driveCount = 0;
        for (final item in decoded) {
          if (item is! Map) continue;
          final album = Map<String, String>.from(
            item.map((key, value) => MapEntry('$key', '${value ?? ''}')),
          );
          final id = (album['id'] ?? '').trim();
          final source = (album['source'] ?? '').trim();
          if (source == 'local' || id.startsWith('local_album:')) {
            localCount++;
          } else {
            driveCount++;
          }
        }
        _startupSavedLocalAlbumCount = localCount;
        _startupSavedDriveAlbumCount = driveCount;
      }
    }
    final savedFolders = prefs
            .getStringList(_localFoldersPrefsKey)
            ?.where((path) => path.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    _startupHasSelectedLocalFolders = savedFolders.isNotEmpty;
  } catch (_) {}
}

Future<void> _ensureAudioServiceInitialized() {
  return _audioServiceInitFuture ??= _initAudioService();
}

Future<void> _initAudioService() async {
  assert(() {
    debugPrint('audio_service init start');
    return true;
  }());

  try {
    final concreteHandler = InfameAudioHandler();
    _infameAudioHandlerInstance = concreteHandler;
    await AudioService.init(
      builder: () => concreteHandler,
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.example.musix.audio',
        androidNotificationChannelName: 'Infame playback',
        // Do not set androidNotificationOngoing when keeping the
        // foreground service alive on pause. audio_service asserts against
        // ongoing=true + stopForegroundOnPause=false, which was causing init
        // to fail and leaving the handler null.
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidResumeOnClick: true,
      ),
    ).timeout(const Duration(seconds: 6));
    assert(() {
      debugPrint('audio_service init done');
      return true;
    }());
  } catch (e, st) {
    _infameAudioHandlerInstance = null;
    debugPrint(
        'audio_service init failed, continuing without notification controls: $e');
    debugPrint('$st');
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Neon-Blob Palette Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Neon-Blob ColorScheme Generator Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  GoogleSignInAccount? _user;
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<ProcessingState>? _processingStateSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<Duration?>? _durationSub;
  Timer? _playbackEndWatchdog;
  Duration _lastWatchdogPosition = Duration.zero;
  int _watchdogNearEndTicks = 0;
  bool _autoAdvanceStartNudgeRunning = false;
  bool _autoAdvanceInProgress = false;
  bool _audioServicePlayerAttached = false;
  int _lastNotificationUpdateMs = 0;
  final Map<String, String> _artistImageCache = {};
  final Map<String, int> _artistImageFailureCooldown = {};
  final Set<String> _artistImageFetchInFlight = {};
  bool _artistImagePrefetchRunning = false;
  bool _changingTrack = false;
  bool _handlingPlaybackComplete = false;
  int _playRequestSerial = 0;
  String _lastHandledCompletionSignature = '';
  String _durationCacheTrackKey = '';
  bool _signingIn = false;
  int _navIndex = 0;
  late final PageController _pageController;
  bool _isDarkMode = _initialDarkMode;
  bool _isShuttingDownPlayback = false;

  String _libraryQuery = '';
  final TextEditingController _librarySearchController =
      TextEditingController();
  String _searchQuery = '';
  String _searchViewMode = 'all';
  final TextEditingController _searchSearchController = TextEditingController();
  final Map<String, String> _librarySearchTextCache = {};
  String _librarySortMode = 'az';
  bool _libraryGridMode = true;
  String _libraryViewMode = 'albums';
  int _homeBrowseCacheVersion = 0;
  int _libraryBrowseCacheVersion = 0;
  String _cachedHomeListKey = '';
  List<Map<String, String>> _cachedRecentBrainAlbums = [];
  List<Map<String, String>> _cachedLastPlayedAlbums = [];
  List<Map<String, String>> _cachedHomeLibraryAlbums = [];
  List<Map<String, String>> _cachedHomeExploreAlbums = [];
  List<Map<String, String>> _cachedHomeHeavyRotationAlbums = [];
  String _cachedLibraryAlbumsKey = '';
  List<Map<String, String>> _cachedVisibleLibraryAlbums = [];
  String _cachedLibrarySongsKey = '';
  List<Map<String, String>> _cachedVisibleLibrarySongs = [];
  List<drive.File> _cachedVisibleLibrarySongFiles = [];
  String _cachedLibraryArtistsKey = '';
  Map<String, List<Map<String, String>>> _cachedLibraryArtists = {};
  List<String> _cachedVisibleLibraryArtists = [];
  Set<String> _likedTrackKeys = {};
  int _likedTracksVersion = 0;

  List<Map<String, String>> _albums = [];
  bool _loadingSaved = true;
  bool _isScanning = false;
  static const _albumsKey = _albumsPrefsKey;
  bool _deferredStartupLoadStarted = false;
  bool _pendingHomeBrowseCacheInvalidation = false;
  bool _localImportInProgress = false;
  final ValueNotifier<String?> _localImportStatus =
      ValueNotifier<String?>(null);
  final Map<String, String> _localImportTempPathCache = {};
  final Set<String> _localImportTempFiles = <String>{};
  int _localImportCopyMsTotal = 0;
  int _localImportCopyCount = 0;

  Map<String, String>? _viewingAlbum;
  List<drive.File> _albumTracks = [];
  bool _loadingAlbum = false;
  List<Map<String, String>> _shuffledExploreAlbums = [];

  // Whole-library foreground metadata scan state. This keeps updating even while
  // you move around the app or open albums.
  bool _loadingMetadata = false;
  int _metadataDone = 0;
  int _metadataTotal = 0;
  int _metadataFast = 0;
  int _metadataDeep = 0;
  int _metadataFailed = 0;
  DateTime _lastMetadataProgressUiUpdate =
      DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _metadataProgressUiThrottle =
      Duration(milliseconds: 120);
  String _metadataPhase = 'Idle';

  void _updateMetadataProgressUi({bool force = false}) {
    if (!mounted) return;

    final now = DateTime.now();
    if (!force &&
        now.difference(_lastMetadataProgressUiUpdate) <
            _metadataProgressUiThrottle) {
      return;
    }

    _lastMetadataProgressUiUpdate = now;
    setState(() {});
  }

  void _invalidateHomeBrowseCache({bool force = false}) {
    if (_localImportInProgress && !force) {
      _pendingHomeBrowseCacheInvalidation = true;
      return;
    }
    _homeBrowseCacheVersion++;
    _cachedHomeListKey = '';
    _cachedRecentBrainAlbums = [];
    _cachedLastPlayedAlbums = [];
    _cachedHomeLibraryAlbums = [];
    _cachedHomeExploreAlbums = [];
    _cachedHomeHeavyRotationAlbums = [];
    _pendingHomeBrowseCacheInvalidation = false;
  }

  void _invalidateLibraryBrowseCache() {
    _libraryBrowseCacheVersion++;
    _cachedLibraryAlbumsKey = '';
    _cachedVisibleLibraryAlbums = [];
    _cachedLibrarySongsKey = '';
    _cachedVisibleLibrarySongs = [];
    _cachedVisibleLibrarySongFiles = [];
    _cachedLibraryArtistsKey = '';
    _cachedLibraryArtists = {};
    _cachedVisibleLibraryArtists = [];
  }

  StateSetter? _settingsSheetSetState;
  Timer? _metadataProgressPoller;
  int _lastMetadataProgressStamp = 0;
  bool _finalMetadataRefreshDone = true;
  bool _syncingForegroundMetadataResults = false;
  bool _showBackgroundGlow = true;
  String _glassMode = _glassModeBalanced;
  String _accentMode = _accentModeChampagne;
  Map<String, String>? _lastPlayed;
  final Map<String, List<Color>> _albumColorCache = {};
  final Set<String> _albumColorExtractionInProgress = {};
  final Map<String, List<drive.File>> _albumTracksCache = {};
  final Map<String, Duration> _knownTrackDurations = {};
  final Map<String, int> _knownTrackDurationsMs = {};
  final Map<String, Map<String, String>> _libraryBrain = {};
  final Map<String, Map<String, String>> _libraryTrackIndex = {};
  final List<Map<String, String>> _playHistory = [];
  List<String> _selectedLocalFolders = <String>[];
  bool _homeShowContinue = true;
  bool _homeShowGenres = true;
  bool _homeShowDecades = true;
  bool _homeShowArtists = true;
  bool _homeShowDiscovery = true;

  // Album-only metadata scan state. This is separate so opening an album does
  // not make the whole-library foreground scan look like it stopped.
  bool _albumMetadataLoading = false;
  int _albumMetadataDone = 0;
  int _albumMetadataTotal = 0;
  final Set<String> _hydratingAlbumDurations = <String>{};
  final Set<String> _hydratedAlbumDurations = <String>{};
  final Map<String, String> _pendingAlbumCoverUpdates = {};
  Timer? _pendingAlbumCoverFlushTimer;

  List<Color> _currentDynamicColors = List<Color>.from(_defaultDynamicColors);

  drive.File? _exploreFolder;
  List<drive.File> _exploreItems = [];
  bool _loadingExplore = false;
  bool _driveExplorerAutoLoadAttempted = false;
  String? _driveExplorerLoadError;
  final List<drive.File> _navStack = [];
  StateSetter? _driveSettingsSetState;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveReadonlyScope],
  );
  AudioPlayer? _audioServiceAttachedPlayer;

  int get _localLibraryCount => _albums.isNotEmpty
      ? _albums.where((album) => _isLocalAlbumRecord(album)).length
      : _startupSavedLocalAlbumCount;

  int get _driveLibraryCount => _albums.isNotEmpty
      ? _albums.length -
          _albums.where((album) => _isLocalAlbumRecord(album)).length
      : _startupSavedDriveAlbumCount;

  bool get _hasLocalMusicLibrary =>
      _localLibraryCount > 0 ||
      _selectedLocalFolders.isNotEmpty ||
      _startupHasSelectedLocalFolders;

  String get _startupSelectedSource {
    if (_user != null && _driveLibraryCount > 0) return 'drive';
    if (_hasLocalMusicLibrary) return 'local';
    return 'none';
  }

  void _logStartupSourceState() {
    debugPrint('Startup hasGoogleAccount=${_user != null}');
    debugPrint('Startup localLibraryCount=$_localLibraryCount');
    debugPrint('Startup driveLibraryCount=$_driveLibraryCount');
    debugPrint('Startup selectedSource=$_startupSelectedSource');
  }

  InfameAudioHandler? get _infameAudioHandler {
    return _infameAudioHandlerInstance;
  }

  void _ensureAudioServicePlayerAttached() {
    final handler = _infameAudioHandlerInstance;
    if (handler == null) {
      debugPrint('AudioService handler is null, cannot attach player');
      return;
    }
    if (_audioServicePlayerAttached &&
        identical(_audioServiceAttachedPlayer, _player)) {
      handler.syncPlaybackStateFromPlayer();
      return;
    }

    handler.attachPlayer(_player);
    _audioServicePlayerAttached = true;
    _audioServiceAttachedPlayer = _player;
    debugPrint('AudioService handler attached to player');
    handler.syncPlaybackStateFromPlayer();
  }

  void _bindAudioServiceCallbacks() {
    final handler = _infameAudioHandlerInstance;
    if (handler == null) return;
    handler.bindCallbacks(
      onPlay: () async {
        await _player.play();
        _infameAudioHandlerInstance?.syncPlaybackStateFromPlayer();
        _syncAudioServicePlaybackState();
      },
      onPause: () async {
        await _player.pause();
        _stopPlaybackEndWatchdog(reason: 'playbackPaused');
        _syncAudioServicePlaybackState();
      },
      onStop: () async {
        await _player.stop();
        _stopPlaybackEndWatchdog(reason: 'playbackStopped');
        _syncAudioServicePlaybackState();
      },
      onSeek: (position) async {
        debugPrint('Seek requested position=$position');
        await _player.seek(position);
        _syncAudioServicePlaybackState();
      },
      onSkipToNext: () async {
        await _playNext();
      },
      onSkipToPrevious: () async {
        await _playPrev();
      },
    );
  }

  void _scheduleDeferredStartupLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_startupFirstFrameLogged) {
        _startupFirstFrameLogged = true;
        debugPrint('Startup firstFrameReady');
        debugPrint(
            'Perf Startup firstFrame=${_startupBootStopwatch.elapsedMilliseconds}');
      }
      if (!mounted || _deferredStartupLoadStarted) return;
      _deferredStartupLoadStarted = true;
      unawaited(_runDeferredStartupLoad());
    });
  }

  Future<void> _runDeferredStartupLoad() async {
    debugPrint('Startup deferredLoad start');
    final stopwatch = Stopwatch()..start();
    try {
      await _ensureAudioServiceInitialized();
      if (!mounted) return;
      _bindAudioServiceCallbacks();
      _ensureAudioServicePlayerAttached();

      await _loadUiPreferences();
      await Future<void>.delayed(Duration.zero);
      await _loadLikedTracks();
      await Future<void>.delayed(Duration.zero);
      await _loadArtistImageCache();
      await Future<void>.delayed(Duration.zero);
      await _loadLastPlayed();
      await Future<void>.delayed(Duration.zero);
      await _loadLibraryTrackIndex();
      await Future<void>.delayed(Duration.zero);
      await _loadCachedMetadata();
      await Future<void>.delayed(Duration.zero);
      await _loadLibraryBrainAndHistory();
      await Future<void>.delayed(Duration.zero);
      await _loadKnownTrackDurations();
      await Future<void>.delayed(Duration.zero);
      await _loadSelectedLocalFolders();
      await Future<void>.delayed(Duration.zero);
      await _loadAlbums();
      await Future<void>.delayed(Duration.zero);
      unawaited(_cleanupStaleLocalImportTempFiles());
      unawaited(_cleanupStaleMetadataScanTempFiles());
      await Future<void>.delayed(Duration.zero);
      await _trySilentSignIn();

      FlutterForegroundTask.addTaskDataCallback(_onMetadataTaskData);
      _startMetadataProgressPolling();

      await Future<void>.delayed(const Duration(milliseconds: 180));
      await _requestForegroundMetadataPermissions();
      _initForegroundMetadataService();
    } finally {
      debugPrint(
          'Startup deferredLoad done elapsedMs=${stopwatch.elapsedMilliseconds}');
    }
  }

  void _setLocalImportProgress(
    String? message, {
    bool inProgress = false,
  }) {
    _localImportInProgress = inProgress;
    if (_localImportStatus.value == message) return;
    _localImportStatus.value = message;
  }

  void _resetLocalImportSessionState() {
    _localImportCopyMsTotal = 0;
    _localImportCopyCount = 0;
    _localImportTempPathCache.clear();
    _localImportTempFiles.clear();
  }

  Future<void> _cleanupLocalImportTempFiles() async {
    final tempFiles = _localImportTempFiles.toList();
    _localImportTempFiles.clear();
    _localImportTempPathCache.clear();
    for (final path in tempFiles) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          debugPrint('LocalImport tempCopy deleted path=$path');
        }
      } catch (_) {}
    }
    var remainingCount = 0;
    var remainingBytes = 0;
    for (final path in tempFiles) {
      try {
        final file = File(path);
        if (await file.exists()) {
          remainingCount++;
          remainingBytes += await file.length();
        }
      } catch (_) {}
    }
    debugPrint(
        'LocalImport tempCleanup remainingCount=$remainingCount remainingBytes=$remainingBytes');
  }

  Future<void> _cleanupStaleMetadataScanTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) return;

      final now = DateTime.now();
      int deletedCount = 0;
      int deletedBytes = 0;

      await for (final entity in tempDir.list(followLinks: false)) {
        if (entity is! File) continue;

        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : entity.path;

        // Clean up metadata scan temp files (musix_meta_* and musix_deep_*)
        if (!name.startsWith('musix_meta_') &&
            !name.startsWith('musix_deep_')) {
          continue;
        }

        try {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);

          // Delete files older than 1 hour
          if (age.inHours >= 1) {
            final bytes = await entity.length();
            await entity.delete();
            deletedCount++;
            deletedBytes += bytes;
            debugPrint('[StorageCleanup] deleted temp file=$name bytes=$bytes');
          }
        } catch (_) {}
      }

      if (deletedCount > 0) {
        final deletedMB = deletedBytes / (1024 * 1024);
        debugPrint(
          '[StorageCleanup] metadata scan temp cleanup deleted=$deletedCount sizeMB=${deletedMB.toStringAsFixed(2)}',
        );
      }
    } catch (e) {
      debugPrint('[StorageCleanup] error cleaning metadata temp files: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: _navIndex);
    _scheduleDeferredStartupLoad();

    _processingStateSub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _handleTrackCompleted(reason: 'processing_completed');
      } else if (state == ProcessingState.ready ||
          state == ProcessingState.idle) {
        _maybeAutoAdvanceAfterPlaybackStop();
      }
      _syncAudioServicePlaybackState();
    });
    _playerStateSub = _player.playerStateStream.listen((_) {
      _maybeAutoAdvanceAfterPlaybackStop();
      _syncAudioServicePlaybackState();
    });
    _playbackEventSub = _player.playbackEventStream.listen((event) {
      _maybeAutoAdvanceFromPlaybackEvent(event);
      _maybeAutoAdvanceAfterPlaybackStop();
      _syncAudioServicePlaybackState();
    });
    _durationSub = _player.durationStream.listen(_cacheCurrentPlaybackDuration);
    _startPlaybackEndWatchdog();
    DriveAudioSource.onEndReached = (fileId) async {
      if (!mounted) return;
      final currentTrack = _nowPlaying.track ?? _nowPlaying.currentTrack;
      final currentId = currentTrack == null
          ? ''
          : (DriveUtils.effectiveId(currentTrack) ?? '').trim();
      if (currentId.isEmpty || currentId != fileId.trim()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (!mounted) return;
      await _handleTrackCompleted(reason: 'drive_eof');
    };
    _searchSearchController.text = _searchQuery;
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onMetadataTaskData);
    DriveAudioSource.onEndReached = null;
    _metadataProgressPoller?.cancel();
    _pendingAlbumCoverFlushTimer?.cancel();
    _playbackEndWatchdog?.cancel();
    _processingStateSub?.cancel();
    _playerStateSub?.cancel();
    _playbackEventSub?.cancel();
    _durationSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_shutdownPlaybackService());
    _localImportStatus.dispose();
    _pageController.dispose();
    _librarySearchController.dispose();
    _searchSearchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(_shutdownPlaybackService());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App going to background - stop UI-only timers but keep playback watchdog for auto-advance
      _stopMetadataProgressPoller(reason: 'appBackgrounded');
      debugPrint(
          'BackgroundPerformance lifecycle=$state stoppedUiTimers=true playbackWatchdogKept=true audioContinues=true');
    } else if (state == AppLifecycleState.resumed) {
      // App returning to foreground - restart UI timers if needed
      debugPrint(
          'BackgroundPerformance lifecycle=$state restartedUiTimers=true');
      // Metadata poller will be restarted if scan is active
    }
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Build Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
  @override
  Widget build(BuildContext context) => _buildMainShellFromPart();

  Widget _buildSignInScreen() => _buildSignInScreenFromPart();

  // Ã¢â€â‚¬Ã¢â€â‚¬ Album View Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
  Widget _buildAlbumView() => _buildAlbumViewFromPart();

  List<Widget> _homeAlbumShelfSlivers({
    required String title,
    required String subtitle,
    required List<Map<String, String>> items,
    double bottomPadding = 22,
  }) =>
      _homeAlbumShelfSliversFromPart(
        title: title,
        subtitle: subtitle,
        items: items,
        bottomPadding: bottomPadding,
      );

  // Ã¢â€â‚¬Ã¢â€â‚¬ Library Tab Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  // Ã¢â€â‚¬Ã¢â€â‚¬ Search Tab Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Widget _buildNowPlayingTab() => _buildNowPlayingTabFromPart();

  Widget _buildSearchTab() => _buildSearchTabFromPart();

  void _searchSetState(VoidCallback fn) => setState(fn);

  void _librarySetState(VoidCallback fn) => setState(fn);

  void _mainShellSetState(VoidCallback fn) => setState(fn);

  Widget _buildAppBackground(List<Color> colors, {bool signIn = false}) =>
      _buildAppBackgroundFromPart(colors, signIn: signIn);

  Widget _buildGradientText(String text,
          {required double size, double spacing = 0}) =>
      _buildGradientTextFromPart(text, size: size, spacing: spacing);
}
