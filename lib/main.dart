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
import 'package:musix/models/track_metadata.dart';
import 'state/now_playing.dart';
import 'services/google_auth_client.dart';
import 'services/drive_audio_source.dart';
import 'services/infame_audio_handler.dart';
import 'widgets/glassy_container.dart';

part 'services/drive_utils.dart';
part 'services/metadata_service.dart';
part 'services/local_file_source.dart';
part 'screens/home_tab.dart';
part 'screens/library_tab.dart';
part 'screens/drive_tab.dart';
part 'widgets/library_widgets.dart';
part 'widgets/liked_widgets.dart';
part 'widgets/library_artist_widgets.dart';
part 'widgets/library_song_widgets.dart';
part 'widgets/library_album_widgets.dart';
part 'widgets/player_widgets.dart';
part 'widgets/settings_widgets.dart';
part 'widgets/search_widgets.dart';
part 'widgets/visual_widgets.dart';
part 'widgets/background_widgets.dart';
part 'widgets/album_detail_widgets.dart';
part 'widgets/player_shell_widgets.dart';
part 'widgets/home_widgets.dart';
part 'widgets/main_visual_widgets.dart';
part 'utils/main_color_helpers.dart';
part 'utils/main_format_helpers.dart';

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

// ─── Compatibility helpers for the local metadata model ─────────────────────
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

// ─── Neon-Blob Palette ───────────────────────────────────────────────────────

// ─── Neon-Blob ColorScheme Generator ───────────────────────────────────────

// ─── Neon-Blob Background Widget ───────────────────────────────────────────────

const _albumsPrefsKey = 'dopamine_albums_v9';
const _albumsBackupPrefsKey = 'dopamine_albums_v9_backup';
const _metadataScanServiceId = 8901;
const _metadataProgressPrefsKey = 'musix_metadata_progress_v1';
const _knownTrackDurationsPrefsKey = 'known_track_durations_ms';
const _uiPrefsKey = 'musix_ui_prefs_v1';
const _albumColorPrefsKey = 'musix_album_color_cache_v1';
const _libraryBrainPrefsKey = 'musix_library_brain_v1';
const _playHistoryPrefsKey = 'musix_play_history_v1';
const _lastPlayedPrefsKey = 'musix_last_played_v1';
const _likedTracksPrefsKey = 'musix_liked_tracks_v1';
const _artistImageCachePrefsKey = 'musix_artist_image_cache_v1';
const _artistImageFailurePrefsKey = 'musix_artist_image_failures_v1';

const glassModePerformance = 'performance';
const _glassModeBalanced = 'balanced';
const glassModePretty = 'pretty';

const _accentModeWhite = 'white';
const _accentModeChampagne = 'champagne';
const _accentModeBlue = 'blue';
const _accentModePink = 'pink';

final ValueNotifier<String> glassModeNotifier =
    ValueNotifier<String>(_glassModeBalanced);

// ─── 4-Color Deterministic Gradient Generator ────────────────────────────────
// Album art can be massive when it comes from embedded tags. Decoding every
// image at full resolution makes grids feel slow even when the files are
// already cached locally. Keep UI decoding capped to a sensible cover size.
const int _coverThumbDecodeSize = 320;
const int _coverLargeDecodeSize = 900;
const String _failedCoverSourcesPrefsKey = 'failed_cover_sources';

final Set<String> _failedCoverSources = <String>{};
final Set<String> _albumCacheKeyLogSeen = <String>{};
final Set<String> _albumDisplayLogSeen = <String>{};

String _coverSourceKey(String source) => source.trim();

String _albumCacheKey(dynamic albumOrTrack, {String source = 'unknown'}) {
  String raw = '';
  String key = '';

  if (albumOrTrack is drive.File) {
    raw =
        (DriveUtils.effectiveId(albumOrTrack) ?? albumOrTrack.id ?? '').trim();
    key = raw;
  } else if (albumOrTrack is TrackMetadata) {
    raw = _firstNonEmptyString([
      albumOrTrack.album,
      albumOrTrack.artist,
      albumOrTrack.title,
      albumOrTrack.coverPath,
    ]);
    key = _normalizeAlbumKeySegment(raw);
  } else if (albumOrTrack is Map) {
    final map = Map<Object?, Object?>.from(albumOrTrack as Map);
    raw = _firstNonEmptyString([
      map['albumKey'],
      map['albumId'],
      map['folderId'],
      map['parentId'],
      map['id'],
      map['displayName'],
      map['name'],
      map['album'],
      map['title'],
    ]);
    key = _normalizeAlbumKeySegment(raw);
    if (key.isEmpty) {
      final title = _firstNonEmptyString([
        map['displayName'],
        map['album'],
        map['title'],
        map['name'],
      ]);
      final artist = _firstNonEmptyString([
        map['artist'],
        map['albumArtist'],
      ]);
      final fallback =
          [artist, title].where((value) => value.isNotEmpty).join('::').trim();
      key = _normalizeAlbumKeySegment(fallback);
    }
  } else if (albumOrTrack is String) {
    raw = albumOrTrack.trim();
    key = _normalizeAlbumKeySegment(raw);
  } else if (albumOrTrack != null) {
    raw = albumOrTrack.toString().trim();
    key = _normalizeAlbumKeySegment(raw);
  }

  if (key.isEmpty) key = raw.trim();
  if (key.isEmpty) key = 'unknown';

  final logKey = '$source|$key';
  if (kAlbumKeyDebug && _albumCacheKeyLogSeen.add(logKey)) {
    debugPrint('AlbumKey resolve raw=$raw key=$key source=$source');
  }
  return key;
}

bool _isDriveThumbnailCover(String source) {
  final lower = source.toLowerCase();
  return lower.contains('lh3.googleusercontent.com/drive-storage') ||
      lower.contains('googleusercontent.com/drive-storage');
}

bool _isBlockedCoverSource(String? source) {
  final value = source?.trim() ?? '';
  if (value.isEmpty) return true;
  if (_failedCoverSources.contains(_coverSourceKey(value))) return true;
  return _isDriveThumbnailCover(value);
}

String _sanitizeCoverSource(String? source) {
  final value = source?.trim() ?? '';
  if (value.isEmpty || _isBlockedCoverSource(value)) return '';
  return value;
}

void _markFailedCoverSource(String source) {
  final key = _coverSourceKey(source);
  if (key.isEmpty || _failedCoverSources.contains(key)) return;
  _failedCoverSources.add(key);
  unawaited(_saveFailedCoverSources());
}

Future<void> _loadFailedCoverSources() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_failedCoverSourcesPrefsKey);
    if (values == null || values.isEmpty) return;
    _failedCoverSources
      ..clear()
      ..addAll(values.map(_coverSourceKey).where((value) => value.isNotEmpty));
  } catch (_) {}
}

Future<void> _saveFailedCoverSources() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _failedCoverSourcesPrefsKey,
      _failedCoverSources.toList()..sort(),
    );
  } catch (_) {}
}

Widget _coverFallbackWidget(String seed) {
  final colors = getAlbumGradient(seed.isNotEmpty ? seed : 'Musix');
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
    ),
    child: Center(
      child: Icon(
        Icons.album_rounded,
        color: Colors.white.withOpacity(0.42),
      ),
    ),
  );
}

ImageProvider? _coverProvider(String? source,
    {int cacheSize = _coverThumbDecodeSize}) {
  if (_isBlockedCoverSource(source)) return null;

  final value = source!.trim();
  final baseProvider = _isLocalCover(value)
      ? FileImage(File(_localCoverPath(value))) as ImageProvider
      : NetworkImage(value);

  return ResizeImage(
    baseProvider,
    width: cacheSize,
    height: cacheSize,
  );
}

Widget _coverImage(
  String source, {
  BoxFit fit = BoxFit.cover,
  int cacheSize = _coverThumbDecodeSize,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  if (_isBlockedCoverSource(source)) {
    return _coverFallbackWidget(source);
  }

  if (_isLocalCover(source)) {
    return Image.file(
      File(_localCoverPath(source)),
      fit: fit,
      cacheWidth: cacheSize,
      cacheHeight: cacheSize,
      errorBuilder: errorBuilder ??
          (context, error, stackTrace) {
            _markFailedCoverSource(source);
            return _coverFallbackWidget(source);
          },
    );
  }

  return Image.network(
    source,
    fit: fit,
    cacheWidth: cacheSize,
    cacheHeight: cacheSize,
    errorBuilder: errorBuilder ??
        (context, error, stackTrace) {
          _markFailedCoverSource(source);
          return _coverFallbackWidget(source);
        },
  );
}

// ─── App Root ────────────────────────────────────────────────────────────────

// ─── Now-Playing State ──────────────────────────────────────────────────────

final _nowPlaying = NowPlaying();

// ─── Main Screen ────────────────────────────────────────────────────────────
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
      debugPrint('BackgroundPerformance lifecycle=$state stoppedUiTimers=true playbackWatchdogKept=true audioContinues=true');
    } else if (state == AppLifecycleState.resumed) {
      // App returning to foreground - restart UI timers if needed
      debugPrint('BackgroundPerformance lifecycle=$state restartedUiTimers=true');
      // Metadata poller will be restarted if scan is active
    }
  }

  Future<void> _shutdownPlaybackService() async {
    if (_isShuttingDownPlayback) return;
    _isShuttingDownPlayback = true;
    debugPrint('App detached: stopping playback service');

    try {
      if (_infameAudioHandlerInstance != null) {
        await _infameAudioHandlerInstance!.stop();
      } else {
        await _player.stop();
      }
    } catch (e) {
      debugPrint('Player stop failed during shutdown: $e');
    }

    debugPrint('AudioService stopped');

    _audioServicePlayerAttached = false;
    _audioServiceAttachedPlayer = null;
  }

  Future<void> _loadCachedMetadata() async {
    await _metaStore.load();
    final changed = _mergeCachedMetadataDurations();
    if (changed) {
      await _saveKnownTrackDurations();
      if (_libraryTrackIndex.isNotEmpty) {
        await _saveLibraryTrackIndex();
      }
    }
    if (mounted) setState(() {});
  }

  bool _mergeCachedMetadataDurations() {
    var changed = false;
    for (final entry in _metaStore.cachedDurationsMs.entries) {
      if (_knownTrackDurationsMs[entry.key] != entry.value) {
        _setKnownTrackDuration(entry.key, entry.value);
        changed = true;
      }
    }
    return changed;
  }

  Color get _appAccent => _accentColorForMode(_accentMode);

  Future<void> _loadLastPlayed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastPlayedPrefsKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = json.decode(raw);
      if (decoded is! Map) return;

      final data = <String, String>{};
      decoded.forEach((key, value) {
        if (key is String && value != null) {
          data[key] = value.toString();
        }
      });

      if (!mounted) return;
      setState(() => _lastPlayed = data);
    } catch (_) {}
  }

  Future<void> _saveLastPlayed(
    drive.File file, {
    String? coverUrl,
  }) async {
    final fileId = DriveUtils.effectiveId(file);
    if (fileId == null) return;

    final meta = DriveUtils.getTrackMeta(file);
    final safeCoverUrl = _sanitizeCoverSource(coverUrl);
    final existing = _lastPlayed;
    final sameAsExisting = existing?['fileId'] == fileId;
    final data = <String, String>{
      'fileId': fileId,
      'fileName': file.name ?? meta['title'] ?? 'Unknown',
      'title': meta['title'] ?? file.name ?? 'Unknown',
      'artist': meta['artist'] ?? 'Unknown Artist',
      'coverUrl': safeCoverUrl.isNotEmpty
          ? safeCoverUrl
          : (sameAsExisting ? (existing?['coverUrl'] ?? '') : ''),
      'albumId': _viewingAlbum?['id'] ??
          (sameAsExisting ? (existing?['albumId'] ?? '') : ''),
      'albumName': _viewingAlbum?['name'] ??
          (sameAsExisting ? (existing?['albumName'] ?? '') : ''),
      'size': file.size ?? '',
      'modifiedTime': file.modifiedTime?.toIso8601String() ?? '',
    };

    _lastPlayed = data;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPlayedPrefsKey, json.encode(data));
    } catch (_) {}

    if (mounted) setState(() {});
  }

  Future<void> _playLastPlayed() async {
    final data = _lastPlayed;
    if (_user == null || data == null) return;

    final fileId = data['fileId'];
    if (fileId == null || fileId.isEmpty) return;

    try {
      final coverUrl = data['coverUrl'] ?? '';
      final albumName = data['albumName'] ?? '';
      final albumId = data['albumId'] ?? '';

      drive.File track = drive.File()
        ..id = fileId
        ..name = data['fileName'] ?? data['title'] ?? 'Unknown';

      List<drive.File> queue = [track];
      int index = 0;
      Map<String, String>? albumRecord;

      if (albumId.isNotEmpty) {
        albumRecord = _albums.firstWhere(
          (album) => album['id'] == albumId,
          orElse: () => {'id': albumId, 'name': albumName, 'cover': coverUrl},
        );

        final authHeaders = await _user!.authHeaders;
        final api = drive.DriveApi(GoogleAuthClient(authHeaders));
        final tracks = await _fetchTracksForAlbumRecord(api, albumRecord);
        final foundIndex =
            tracks.indexWhere((item) => DriveUtils.effectiveId(item) == fileId);

        if (tracks.isNotEmpty && foundIndex >= 0) {
          queue = tracks;
          index = foundIndex;
          track = tracks[foundIndex];
        }
      }

      await _playSong(
        track,
        queue: queue,
        idx: index,
        coverUrl: coverUrl.isNotEmpty ? coverUrl : albumRecord?['cover'],
        colors: getAlbumGradient(
            albumName.isNotEmpty ? albumName : (data['title'] ?? 'Infame')),
      );
    } catch (e) {
      _showError('Could not continue last song: $e');
    }
  }

  Future<void> _loadUiPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      glassModeNotifier.value = _glassMode;
      await _loadFailedCoverSources();
      final savedThemeMode = prefs.getString(_themeModePrefsKey);
      if (savedThemeMode != null) {
        final nextDarkMode = savedThemeMode != 'light';
        if (mounted && _isDarkMode != nextDarkMode) {
          setState(() => _isDarkMode = nextDarkMode);
        } else {
          _isDarkMode = nextDarkMode;
        }
      }

      final colorsRaw = prefs.getString(_albumColorPrefsKey);
      if (colorsRaw != null && colorsRaw.isNotEmpty) {
        try {
          final decodedColors = json.decode(colorsRaw);
          if (decodedColors is Map) {
            _albumColorCache.clear();
            decodedColors.forEach((key, value) {
              if (key is String && value is List) {
                final parsed = value
                    .map((item) => _colorFromHex(item.toString()))
                    .whereType<Color>()
                    .toList();
                if (parsed.length >= 4) {
                  _albumColorCache[key] = parsed.take(4).toList();
                }
              }
            });
          }
        } catch (_) {}
      }

      final raw = prefs.getString(_uiPrefsKey);
      if (raw == null || raw.isEmpty) return;

      final data = json.decode(raw);
      if (data is! Map) return;

      if (!mounted) return;
      setState(() {
        _showBackgroundGlow = data['showBackgroundGlow'] != false;
        _homeShowContinue = data['homeShowContinue'] != false;
        _homeShowGenres = data['homeShowGenres'] != false;
        _homeShowDecades = data['homeShowDecades'] != false;
        _homeShowArtists = data['homeShowArtists'] != false;
        _homeShowDiscovery = data['homeShowDiscovery'] != false;
        final savedGlassMode =
            (data['glassMode'] ?? _glassModeBalanced).toString();
        _glassMode = _isValidGlassMode(savedGlassMode)
            ? savedGlassMode
            : _glassModeBalanced;
        glassModeNotifier.value = _glassMode;

        final savedAccentMode =
            (data['accentMode'] ?? _accentModeChampagne).toString();
        _accentMode = _isValidAccentMode(savedAccentMode)
            ? savedAccentMode
            : _accentModeChampagne;

        final savedLibraryViewMode =
            (data['libraryViewMode'] ?? 'albums').toString();
        _libraryViewMode = (savedLibraryViewMode == 'albums' ||
                savedLibraryViewMode == 'songs' ||
                savedLibraryViewMode == 'artists' ||
                savedLibraryViewMode == 'liked')
            ? savedLibraryViewMode
            : 'albums';
      });
    } catch (_) {}
  }

  Future<void> _saveUiPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _themeModePrefsKey,
      _isDarkMode ? 'dark' : 'light',
    );
    await prefs.setString(
      _uiPrefsKey,
      json.encode({
        'showBackgroundGlow': _showBackgroundGlow,
        'glassMode': _glassMode,
        'homeShowContinue': _homeShowContinue,
        'homeShowGenres': _homeShowGenres,
        'homeShowDecades': _homeShowDecades,
        'homeShowArtists': _homeShowArtists,
        'homeShowDiscovery': _homeShowDiscovery,
        'accentMode': _accentMode,
        'libraryViewMode': _libraryViewMode,
      }),
    );
  }

  Future<void> _loadLikedTracks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final liked =
          prefs.getStringList(_likedTracksPrefsKey) ?? const <String>[];
      final nextLiked = <String>{};
      for (final key in liked) {
        final trimmed = key.trim();
        if (trimmed.isNotEmpty) nextLiked.add(trimmed);
      }
      _likedTrackKeys = nextLiked;
      _likedTracksVersion++;
      _invalidateLibraryBrowseCache();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveLikedTracks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final liked = _likedTrackKeys.toList()..sort();
      await prefs.setStringList(_likedTracksPrefsKey, liked);
    } catch (_) {}
  }

  String _normalizeArtistText(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _artistImageCacheKey(String artistName) {
    return _normalizeArtistText(artistName).toLowerCase();
  }

  bool _isBadArtistName(String value) {
    final text = _normalizeArtistText(value);
    if (text.isEmpty) return true;

    final lower = text.toLowerCase();
    if (lower == 'unknown' ||
        lower == 'unknown artist' ||
        lower == 'various artists' ||
        lower == 'various artist' ||
        lower == 'miscellaneous') {
      return true;
    }

    if (text.length > 80) return true;
    return false;
  }

  String _stripFeaturedArtistSuffix(String value) {
    final text = _normalizeArtistText(value);
    if (text.isEmpty) return '';

    final match = RegExp(
      r'^(.*?)\s+(?:feat\.?|ft\.?|featuring|with)\s+.+$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      final cleaned = _normalizeArtistText(match.group(1) ?? '');
      if (cleaned.isNotEmpty) return cleaned;
    }

    return text;
  }

  String _canonicalArtistName({
    String? albumArtist,
    String? trackArtist,
    String? albumName,
  }) {
    final albumCandidate = _normalizeArtistText(albumArtist ?? '');
    if (albumCandidate.isNotEmpty && !_isBadArtistName(albumCandidate)) {
      final cleaned = _stripFeaturedArtistSuffix(albumCandidate);
      if (cleaned.isNotEmpty && !_isBadArtistName(cleaned)) return cleaned;
      return albumCandidate;
    }

    final folderGuess = _artistAlbumFromFolder(albumName ?? '')['artist'] ?? '';
    if (folderGuess.isNotEmpty && !_isBadArtistName(folderGuess)) {
      final cleaned = _stripFeaturedArtistSuffix(folderGuess);
      if (cleaned.isNotEmpty && !_isBadArtistName(cleaned)) return cleaned;
      return folderGuess;
    }

    final trackCandidate = _normalizeArtistText(trackArtist ?? '');
    if (trackCandidate.isEmpty || _isBadArtistName(trackCandidate)) return '';
    final cleaned = _stripFeaturedArtistSuffix(trackCandidate);
    return cleaned.isNotEmpty ? cleaned : trackCandidate;
  }

  String _artistSearchTextForRecord(Map<String, String> record) {
    final albumId = record['albumId'] ?? '';
    final brain = albumId.isNotEmpty ? _libraryBrain[albumId] : null;
    final canonical = _canonicalArtistName(
      albumArtist: record['albumArtist'] ?? brain?['artist'] ?? '',
      trackArtist: record['artist'] ?? '',
      albumName: record['albumName'] ?? brain?['displayName'] ?? '',
    );

    return [
      canonical,
      record['artist'] ?? '',
      record['albumArtist'] ?? '',
      record['albumName'] ?? '',
      record['album'] ?? '',
      record['name'] ?? '',
      record['title'] ?? '',
      brain?['artist'] ?? '',
      brain?['displayName'] ?? '',
    ].join(' ').toLowerCase();
  }

  List<String> _canonicalArtistNamesFromLibrary() {
    final names = <String>{};
    for (final record in _libraryTrackIndex.values) {
      final albumId = record['albumId'] ?? '';
      final brain = albumId.isNotEmpty ? _libraryBrain[albumId] : null;
      final canonical = _canonicalArtistName(
        albumArtist: record['albumArtist'] ?? brain?['artist'] ?? '',
        trackArtist: record['artist'] ?? '',
        albumName: record['albumName'] ?? brain?['displayName'] ?? '',
      );
      if (canonical.isNotEmpty) names.add(canonical);
    }

    final list = names.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<void> _loadArtistImageCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawCache = prefs.getString(_artistImageCachePrefsKey);
      final rawFailures = prefs.getString(_artistImageFailurePrefsKey);

      final nextCache = <String, String>{};
      if (rawCache != null && rawCache.isNotEmpty) {
        final decoded = json.decode(rawCache);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is String && value is String) {
              final trimmedKey = key.trim();
              final trimmedValue = value.trim();
              if (trimmedKey.isNotEmpty && trimmedValue.isNotEmpty) {
                nextCache[trimmedKey] = trimmedValue;
              }
            }
          });
        }
      }

      final nextFailures = <String, int>{};
      if (rawFailures != null && rawFailures.isNotEmpty) {
        final decoded = json.decode(rawFailures);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is! String) return;
            final until = int.tryParse(value.toString());
            if (until != null && until > 0) {
              nextFailures[key.trim()] = until;
            }
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _artistImageCache
          ..clear()
          ..addAll(nextCache);
        _artistImageFailureCooldown
          ..clear()
          ..addAll(nextFailures);
      });
      _queueArtistImagePrefetch();
    } catch (_) {}
  }

  Future<void> _saveArtistImageCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _artistImageCachePrefsKey,
        json.encode(_artistImageCache),
      );
      await prefs.setString(
        _artistImageFailurePrefsKey,
        json.encode(_artistImageFailureCooldown),
      );
    } catch (_) {}
  }

  bool _artistImageLookupOnCooldown(String artistName) {
    final key = _artistImageCacheKey(artistName);
    final until = _artistImageFailureCooldown[key] ?? 0;
    return until > DateTime.now().millisecondsSinceEpoch;
  }

  void _markArtistImageLookupFailed(String artistName) {
    final key = _artistImageCacheKey(artistName);
    if (key.isEmpty) return;
    _artistImageFailureCooldown[key] =
        DateTime.now().add(const Duration(hours: 12)).millisecondsSinceEpoch;
  }

  void _markArtistImageLookupSucceeded(String artistName, String imageUrl) {
    final key = _artistImageCacheKey(artistName);
    if (key.isEmpty) return;
    _artistImageCache[key] = imageUrl;
    _artistImageFailureCooldown.remove(key);
  }

  Future<String?> _fetchArtistImageUrl(String artistName) async {
    final trimmed = _normalizeArtistText(artistName);
    if (trimmed.isEmpty || _isBadArtistName(trimmed)) return null;

    final query = Uri.encodeComponent(trimmed);
    final uris = <Uri>[
      Uri.parse(
        'https://www.theaudiodb.com/api/v2/json/search/artist/$query',
      ),
      Uri.parse(
        'https://www.theaudiodb.com/api/v1/json/2/search.php?s=$query',
      ),
    ];

    String? chooseUrl(Map item) {
      final candidates = [
        item['strArtistThumb'],
        item['strArtistLogo'],
        item['strArtistCutOut'],
        item['strArtistWideThumb'],
        item['strArtistBanner'],
        item['strArtistFanart1'],
      ];
      for (final candidate in candidates) {
        final value = candidate?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return null;
    }

    for (final uri in uris) {
      try {
        final response =
            await http.get(uri).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;

        final decoded = json.decode(response.body);
        if (decoded is! Map) continue;

        final data = decoded['data'] ?? decoded['artists'];
        if (data is! List || data.isEmpty) continue;

        for (final item in data) {
          if (item is! Map) continue;
          final imageUrl = chooseUrl(item);
          if (imageUrl != null && imageUrl.isNotEmpty) return imageUrl;
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  Future<void> _ensureArtistImageCached(String artistName) async {
    final normalized = _normalizeArtistText(artistName);
    if (normalized.isEmpty || _isBadArtistName(normalized)) return;

    final cacheKey = _artistImageCacheKey(normalized);
    if (cacheKey.isEmpty) return;
    if (_artistImageCache.containsKey(cacheKey)) return;
    if (_artistImageFetchInFlight.contains(cacheKey)) return;
    if (_artistImageLookupOnCooldown(normalized)) return;

    _artistImageFetchInFlight.add(cacheKey);
    try {
      final imageUrl = await _fetchArtistImageUrl(normalized);
      if (!mounted) return;

      setState(() {
        if (imageUrl != null && imageUrl.isNotEmpty) {
          _markArtistImageLookupSucceeded(normalized, imageUrl);
        } else {
          _markArtistImageLookupFailed(normalized);
        }
      });
      await _saveArtistImageCache();
    } catch (_) {
      if (mounted) {
        setState(() => _markArtistImageLookupFailed(normalized));
        await _saveArtistImageCache();
      }
    } finally {
      _artistImageFetchInFlight.remove(cacheKey);
    }
  }

  void _queueArtistImagePrefetch() {
    if (_artistImagePrefetchRunning) return;
    if (_libraryTrackIndex.isEmpty) return;
    _artistImagePrefetchRunning = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _artistImagePrefetchRunning = false;
        return;
      }
      unawaited(_prefetchArtistImages());
    });
  }

  Future<void> _prefetchArtistImages() async {
    try {
      final artists = _canonicalArtistNamesFromLibrary();
      final missing = artists
          .where((artist) {
            final key = _artistImageCacheKey(artist);
            return key.isNotEmpty &&
                !_artistImageCache.containsKey(key) &&
                !_artistImageLookupOnCooldown(artist);
          })
          .take(24)
          .toList();

      for (final artist in missing) {
        if (!mounted) break;
        await _ensureArtistImageCached(artist);
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    } finally {
      _artistImagePrefetchRunning = false;
    }
  }

  bool _isTrackLiked(drive.File file) {
    final key = _trackKey(file);
    return key.isNotEmpty && _likedTrackKeys.contains(key);
  }

  void _toggleLikedTrack(drive.File file) {
    final key = _trackKey(file);
    if (key.isEmpty) return;

    final liked = !_likedTrackKeys.contains(key);
    setState(() {
      if (liked) {
        _likedTrackKeys.add(key);
      } else {
        _likedTrackKeys.remove(key);
      }
      _likedTracksVersion++;
    });
    _invalidateLibraryBrowseCache();
    _saveLikedTracks();
    _nowPlaying.refresh();
    _showSuccess(liked ? 'Added to liked songs' : 'Removed from liked songs');
  }

  Future<void> _saveAlbumColorCache() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, List<String>>{};
    _albumColorCache.forEach((key, colors) {
      if (colors.length >= 4) {
        payload[key] = colors.take(4).map(_colorToHex).toList();
      }
    });
    await prefs.setString(_albumColorPrefsKey, json.encode(payload));
  }

  static const String _libraryTrackIndexKey = 'library_track_index';
  static const String _knownTrackDurationsKey = _knownTrackDurationsPrefsKey;
  final Map<String, int> _knownTrackDurationsMs = {};

  Future<void> _loadLibraryTrackIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_libraryTrackIndexKey);
      final rawExists = raw != null && raw.isNotEmpty;
      final rawLength = raw?.length ?? 0;

      debugPrint('LocalTrackRestore storageKey=$_libraryTrackIndexKey');
      debugPrint(
          'LocalTrackRestore storageLocation=prefs:$_libraryTrackIndexKey');
      debugPrint('LocalTrackRestore rawExists=$rawExists');
      debugPrint('LocalTrackRestore rawLength=$rawLength');

      if (raw == null || raw.isEmpty) {
        debugPrint('LocalTrackRestore decodedCount=0');
        debugPrint('LocalTrackRestore rejectedCount=0');
        return;
      }

      dynamic decoded;
      try {
        decoded = json.decode(raw);
      } catch (e) {
        debugPrint('LocalTrackRestore decodeError=$e');
        debugPrint(
            'LocalTrackRestore rawPreview=${raw.substring(0, math.min(500, raw.length))}');
        return;
      }
      if (decoded is Map) {
        var decodedCount = 0;
        var rejectedCount = 0;
        _libraryTrackIndex.clear();
        Map<String, String>? firstDecoded;
        decoded.forEach((key, value) {
          if (key is String && value is Map) {
            final record = Map<String, String>.from(value);
            if (record.isEmpty) {
              rejectedCount++;
              return;
            }
            final normalizedId = record['id']?.trim().isNotEmpty == true
                ? record['id']!.trim()
                : key.trim();
            if (normalizedId.isEmpty) {
              rejectedCount++;
              return;
            }
            record['id'] = normalizedId;
            _libraryTrackIndex[normalizedId] = record;
            firstDecoded ??= record;
            decodedCount++;
          } else {
            rejectedCount++;
          }
        });

        debugPrint('LocalTrackRestore decodedCount=$decodedCount');
        debugPrint('LocalTrackRestore rejectedCount=$rejectedCount');
        if (firstDecoded != null) {
          final decodedSample = firstDecoded!;
          debugPrint(
              'LocalTrackRestore firstDecoded albumKey=${decodedSample['albumId'] ?? decodedSample['albumKey'] ?? ''} title=${decodedSample['title'] ?? ''} uri=${decodedSample['localUri'] ?? ''} path=${decodedSample['localPath'] ?? decodedSample['path'] ?? ''} source=${decodedSample['source'] ?? ''}');
        }

        // Repair old records so Songs/Artists inherit current album covers and
        // durations without needing the album to be opened first.
        _repairLibraryTrackIndexFromAlbums();
        _queueArtistImagePrefetch();

        for (final entry in _libraryTrackIndex.entries) {
          final durationMs =
              _validDurationMsFromValue(entry.value['durationMs']);
          if (durationMs != null) {
            _setKnownTrackDuration(entry.key, durationMs);
          }
        }

        _invalidateLibraryBrowseCache();
        _queueArtistImagePrefetch();
      } else {
        debugPrint('LocalTrackRestore decodeError=decoded_not_map');
        debugPrint(
            'LocalTrackRestore rawPreview=${raw.substring(0, math.min(500, raw.length))}');
      }
    } catch (e) {
      debugPrint('LocalTrackRestore error=$e');
    }
  }

  Future<void> _saveLibraryTrackIndex(
      {bool logLocalPersistence = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = json.encode(_libraryTrackIndex);
      await prefs.setString(_libraryTrackIndexKey, raw);

      if (logLocalPersistence) {
        final localRecords = _libraryTrackIndex.values
            .where((record) => (record['source'] ?? '') == 'local')
            .toList();
        final storageKey = _libraryTrackIndexKey;
        debugPrint('LocalTrackPersist storageKey=$storageKey');
        debugPrint(
            'LocalTrackPersist storageLocation=prefs:$_libraryTrackIndexKey');
        debugPrint('LocalTrackPersist writeCount=${localRecords.length}');
        if (localRecords.isNotEmpty) {
          final first = localRecords.first;
          debugPrint(
              'LocalTrackPersist firstSaved albumKey=${first['albumId'] ?? first['albumKey'] ?? ''} title=${first['title'] ?? ''} uri=${first['localUri'] ?? ''} path=${first['localPath'] ?? first['path'] ?? ''} source=${first['source'] ?? ''}');
        }
        try {
          final persistedRaw = prefs.getString(_libraryTrackIndexKey) ?? '';
          var readBackCount = 0;
          if (persistedRaw.isNotEmpty) {
            final decoded = json.decode(persistedRaw);
            if (decoded is Map) {
              for (final entry in decoded.entries) {
                if (entry.key is String && entry.value is Map) {
                  final record = Map<String, dynamic>.from(entry.value as Map);
                  if ((record['source'] ?? '') == 'local') {
                    readBackCount++;
                  }
                }
              }
            }
          }
          debugPrint('LocalTrackPersist readBackCount=$readBackCount');
        } catch (e) {
          debugPrint('LocalTrackPersist readBackError=$e');
        }
      }
    } catch (_) {}
  }

  Future<void> _loadKnownTrackDurations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<dynamic, dynamic>? decoded;

      final raw = prefs.getString(_knownTrackDurationsKey);
      if (raw != null && raw.isNotEmpty) {
        final parsed = json.decode(raw);
        if (parsed is Map) decoded = parsed;
      }

      // Backward-compat migrations for older builds.
      if (decoded == null) {
        const legacyKeys = <String>[
          'known_track_durations',
          'known_track_durations_v1',
          'known_track_durations_ms_v1',
        ];
        for (final legacyKey in legacyKeys) {
          final legacyRaw = prefs.getString(legacyKey);
          if (legacyRaw == null || legacyRaw.isEmpty) continue;
          final parsed = json.decode(legacyRaw);
          if (parsed is Map) {
            decoded = parsed;
            break;
          }
        }
      }

      if (decoded == null) return;

      _knownTrackDurationsMs.clear();
      decoded.forEach((key, value) {
        if (key is! String) return;
        final durationMs = _validDurationMsFromValue(value) ??
            _validDurationMsFromValue(
              value is Map
                  ? (value['durationMs'] ??
                      value['inMilliseconds'] ??
                      value['milliseconds'] ??
                      value['duration'])
                  : null,
            );
        if (durationMs == null) return;
        _setKnownTrackDuration(key, durationMs);
      });

      final metadataChanged = _mergeCachedMetadataDurations();
      final repaired = _repairLibraryTrackIndexFromAlbums();
      if (repaired || metadataChanged) await _saveLibraryTrackIndex();
      if (metadataChanged) await _saveKnownTrackDurations();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveKnownTrackDurations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _knownTrackDurationsKey, json.encode(_knownTrackDurationsMs));
    } catch (_) {}
  }

  int? _validDurationMsFromValue(Object? value) {
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.toInt();
    } else if (value is String) {
      parsed = int.tryParse(value.trim());
    }

    if (parsed == null || parsed <= 0 || parsed >= 86400000) return null;
    return parsed;
  }

  void _setKnownTrackDuration(String trackId, int durationMs) {
    final valid = _validDurationMsFromValue(durationMs);
    if (trackId.trim().isEmpty || valid == null) return;

    _knownTrackDurationsMs[trackId] = valid;
    _knownTrackDurations[trackId] = Duration(milliseconds: valid);

    final record = _libraryTrackIndex[trackId];
    if (record != null) {
      record['durationMs'] = valid.toString();
    }
  }

  void _storeDurationForTrackId(
    String trackId,
    int durationMs, {
    bool persist = true,
    bool refreshVisibleAlbum = false,
  }) {
    final valid = _validDurationMsFromValue(durationMs);
    if (trackId.trim().isEmpty || valid == null) return;

    _setKnownTrackDuration(trackId, valid);

    if (persist) {
      unawaited(_saveKnownTrackDurations());
      unawaited(_saveLibraryTrackIndex());
    }

    if (refreshVisibleAlbum && mounted && _viewingAlbum != null) {
      setState(() {});
    }
  }

  void _cacheCurrentPlaybackDuration(Duration? duration) {
    final durationMs = _validDurationMsFromValue(duration?.inMilliseconds);
    if (durationMs == null) return;

    final current = _nowPlaying.track ?? _nowPlaying.currentTrack;
    if (current == null) return;

    final key = _trackKey(current);
    if (key.isEmpty) return;

    // During a track change just_audio can briefly re-emit the previous
    // source's duration after _nowPlaying has already been switched to the
    // next file. Only cache durations for the source that has finished
    // setAudioSource for the current track, otherwise album rows can show the
    // wrong length until the user taps the song again.
    if (_durationCacheTrackKey != key) return;

    final existingDurationMs = _knownTrackDurationsMs[key] ??
        _validDurationMsFromValue(_libraryTrackIndex[key]?['durationMs']);
    if (existingDurationMs != null &&
        existingDurationMs > 0 &&
        durationMs < (existingDurationMs * 0.85).round()) {
      return;
    }

    if (_knownTrackDurationsMs[key] == durationMs &&
        _libraryTrackIndex[key]?['durationMs'] == durationMs.toString()) {
      return;
    }

    _storeDurationForTrackId(
      key,
      durationMs,
      persist: true,
      refreshVisibleAlbum: true,
    );
    _invalidateLibraryBrowseCache();

    _verbosePlaybackLog(
        'Duration cached from player key=$key durationMs=$durationMs');
  }

  int? _durationMsFromTrackMetadata(drive.File file) {
    final meta = _metaStore.peekFresh(file) ?? _metaStore.peek(file);
    return _validDurationMsFromValue(meta?.durationMs);
  }

  int? _durationMsForTrack(drive.File file) {
    final trackId = _trackKey(file);
    if (trackId.isEmpty) return null;

    final fromMetadata = _durationMsFromTrackMetadata(file);
    final fromKnown =
        _validDurationMsFromValue(_knownTrackDurationsMs[trackId]);
    final fromIndex =
        _validDurationMsFromValue(_libraryTrackIndex[trackId]?['durationMs']);

    return fromMetadata ?? fromKnown ?? fromIndex;
  }

  List<drive.File> _tracksForAlbumKey(String albumKey) {
    final normalizedKey = _albumCacheKey(albumKey, source: 'album_tracks');
    final cachedTracks = _albumTracksCache[normalizedKey];
    if (cachedTracks != null && cachedTracks.isNotEmpty) {
      return _sortTracksForAlbum(cachedTracks);
    }

    if (_viewingAlbum != null &&
        _albumCacheKey(_viewingAlbum!, source: 'current_album') ==
            normalizedKey &&
        _albumTracks.isNotEmpty) {
      return _sortTracksForAlbum(_albumTracks);
    }

    return const <drive.File>[];
  }

  Map<String, String>? _brainForAlbum(Map<String, String> album) {
    final normalizedKey = _albumCacheKey(album, source: 'brain_lookup');
    final rawKey = (album['id'] ?? '').trim();
    return _libraryBrain[normalizedKey] ?? _libraryBrain[rawKey];
  }

  bool _isWeakAlbumDisplayTitle(String? value, {String? artist}) {
    final text = _cleanBrainValue(value);
    if (text.isEmpty) return true;
    final lower = text.toLowerCase().trim();
    if (RegExp(r'^disc\s*\d+([\s_-]*album)?$').hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'^cd\s*\d+([\s_-]*album)?$').hasMatch(lower)) {
      return true;
    }
    if (lower == 'album' || lower == 'unknown album') return true;

    final artistText = _cleanBrainValue(artist).toLowerCase();
    if (artistText.isNotEmpty) {
      final normalizedTitle =
          lower.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      final normalizedArtist =
          artistText.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      if (normalizedTitle == normalizedArtist ||
          normalizedTitle == '$normalizedArtist album') {
        return true;
      }
    }

    return false;
  }

  List<Map<String, String>> _trackRecordsForAlbumKey(String albumKey) {
    final normalizedKey =
        _albumCacheKey(albumKey, source: 'album_track_records');
    if (normalizedKey.isEmpty) return const <Map<String, String>>[];
    return _libraryTrackIndex.values
        .where((record) {
          final id = (record['albumId'] ?? record['albumKey'] ?? '').trim();
          if (id.isEmpty) return false;
          return id == normalizedKey ||
              _albumCacheKey(id, source: 'album_track_record_id') ==
                  normalizedKey;
        })
        .map((record) => Map<String, String>.from(record))
        .toList(growable: false);
  }

  String _mostCommonCleanValue(
    Iterable<String?> values, {
    bool Function(String value)? accept,
  }) {
    final counts = <String, int>{};
    final canonical = <String, String>{};
    for (final raw in values) {
      final value = _cleanBrainValue(raw);
      if (value.isEmpty) continue;
      if (accept != null && !accept(value)) continue;
      final key = value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      counts[key] = (counts[key] ?? 0) + 1;
      canonical.putIfAbsent(key, () => value);
    }
    if (counts.isEmpty) return '';
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return canonical[entries.first.key] ?? '';
  }

  String _albumTitleFromRecords(
    List<Map<String, String>> records, {
    String? fallbackArtist,
  }) {
    return _mostCommonCleanValue(
      records.map((record) => record['album']),
      accept: (value) =>
          !_isWeakAlbumDisplayTitle(value, artist: fallbackArtist),
    );
  }

  String _albumArtistFromRecords(List<Map<String, String>> records) {
    final albumArtist = _mostCommonCleanValue(
      records.map((record) => record['albumArtist']),
      accept: (value) => !_isBadArtistName(value),
    );
    if (albumArtist.isNotEmpty) return albumArtist;
    return _mostCommonCleanValue(
      records.map((record) => record['artist']),
      accept: (value) => !_isBadArtistName(value),
    );
  }

  String _albumCoverFromRecords(List<Map<String, String>> records) {
    return _mostCommonCleanValue(
      records.map((record) => record['albumCover']),
      accept: (value) => _sanitizeCoverSource(value).isNotEmpty,
    );
  }

  String _resolvedAlbumTitle(Map<String, String> album) {
    final key = _albumCacheKey(album, source: 'album_title');
    final brain = _brainForAlbum(album);
    final tracks = _tracksForAlbumKey(key);
    final records = _trackRecordsForAlbumKey(key);
    final artistHint = _firstNonEmptyString([
      _albumArtistFromRecords(records),
      _cleanBrainValue(brain?['artist']),
      _cleanBrainValue(album['artist']),
      if (tracks.isNotEmpty) _albumArtistFromTracks(tracks),
      _artistAlbumFromFolder(album['name'] ?? '')['artist'] ?? '',
    ]);

    final metadataTitle = _firstNonEmptyString([
      _albumTitleFromRecords(records, fallbackArtist: artistHint),
      if (tracks.isNotEmpty) _albumTitleFromTracks(tracks),
    ]);

    final savedTitle = _firstNonEmptyString([
      if (!_isWeakAlbumDisplayTitle(brain?['displayName'], artist: artistHint))
        _cleanBrainValue(brain?['displayName']),
      if (!_isWeakAlbumDisplayTitle(album['displayName'], artist: artistHint))
        _cleanBrainValue(album['displayName']),
      if (!_isWeakAlbumDisplayTitle(brain?['name'], artist: artistHint))
        _cleanBrainValue(brain?['name']),
      if (!_isWeakAlbumDisplayTitle(album['album'], artist: artistHint))
        _cleanBrainValue(album['album']),
      if (!_isWeakAlbumDisplayTitle(album['title'], artist: artistHint))
        _cleanBrainValue(album['title']),
      if (!_isWeakAlbumDisplayTitle(album['name'], artist: artistHint))
        _cleanBrainValue(album['name']),
    ]);

    final folderFallback = _cleanBackgroundValue(
      album['name'] ?? album['displayName'] ?? album['album'] ?? album['title'],
    );
    final value =
        _firstNonEmptyString([metadataTitle, savedTitle, folderFallback]);
    final titleSource = metadataTitle.isNotEmpty
        ? 'metadata'
        : savedTitle.isNotEmpty
            ? 'saved'
            : folderFallback.isNotEmpty
                ? 'folder_fallback'
                : 'none';
    final logKey = 'title|$key|$value|$titleSource';
    if (kAlbumDisplayDebug && _albumDisplayLogSeen.add(logKey)) {
      debugPrint(
          'AlbumDisplay resolved key=$key title="$value" artist="$artistHint" titleSource=$titleSource');
    }
    return value.isNotEmpty ? value : 'Album';
  }

  String _resolvedAlbumArtist(Map<String, String> album) {
    final key = _albumCacheKey(album, source: 'album_artist');
    final brain = _brainForAlbum(album);
    final tracks = _tracksForAlbumKey(key);
    final records = _trackRecordsForAlbumKey(key);

    final metadataArtist = _firstNonEmptyString([
      _albumArtistFromRecords(records),
      if (tracks.isNotEmpty) _albumArtistFromTracks(tracks),
    ]);

    final savedArtist = _firstNonEmptyString([
      if (!_isBadArtistName(_cleanBrainValue(brain?['artist'])))
        _cleanBrainValue(brain?['artist']),
      if (!_isBadArtistName(_cleanBrainValue(album['artist'])))
        _cleanBrainValue(album['artist']),
      if (!_isBadArtistName(
          _artistAlbumFromFolder(album['name'] ?? '')['artist'] ?? ''))
        _artistAlbumFromFolder(album['name'] ?? '')['artist'] ?? '',
    ]);

    final value = _firstNonEmptyString([metadataArtist, savedArtist]);
    final artistSource = metadataArtist.isNotEmpty
        ? 'metadata'
        : savedArtist.isNotEmpty
            ? 'saved'
            : 'none';
    final logKey = 'artist|$key|$value|$artistSource';
    if (kAlbumDisplayDebug && _albumDisplayLogSeen.add(logKey)) {
      debugPrint(
          'AlbumDisplay resolved key=$key artist="$value" artistSource=$artistSource');
    }
    return value.isNotEmpty ? value : 'Unknown Artist';
  }

  String _resolvedAlbumCover(Map<String, String> album) {
    final key = _albumCacheKey(album, source: 'album_cover');
    final brain = _brainForAlbum(album);
    final records = _trackRecordsForAlbumKey(key);

    final direct = _sanitizeCoverSource(
      album['cover'] ??
          album['coverUrl'] ??
          album['artwork'] ??
          brain?['cover'] ??
          brain?['coverUrl'] ??
          brain?['artwork'] ??
          '',
    );
    if (direct.isNotEmpty) {
      final logKey = 'cover|$key|$direct';
      if (kAlbumCoverDebug && _albumDisplayLogSeen.add(logKey)) {
        final directHasBytes =
            _isLocalCover(direct) ? File(direct).existsSync() : false;
        debugPrint(
            'AlbumCover lookup key=$key albumCoverBytes=$directHasBytes brainCoverBytes=$directHasBytes cacheCoverBytes=false');
        debugPrint(
            'AlbumCover key=$key source=album_or_brain hasBytes=$directHasBytes');
      }
      return direct;
    }

    final recordCover = _sanitizeCoverSource(_albumCoverFromRecords(records));
    if (recordCover.isNotEmpty) {
      final logKey = 'cover|$key|$recordCover';
      if (kAlbumCoverDebug && _albumDisplayLogSeen.add(logKey)) {
        debugPrint(
            'AlbumCover lookup key=$key albumCoverBytes=false brainCoverBytes=false cacheCoverBytes=true');
        debugPrint('AlbumCover key=$key source=track_index hasBytes=true');
      }
      return recordCover;
    }

    final tracks = _tracksForAlbumKey(key);
    for (final track in tracks) {
      final cached = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      final coverPath = _sanitizeCoverSource(cached?.coverPath);
      if (coverPath.isNotEmpty) {
        final logKey = 'cover|$key|$coverPath';
        if (kAlbumCoverDebug && _albumDisplayLogSeen.add(logKey)) {
          debugPrint(
              'AlbumCover lookup key=$key albumCoverBytes=false brainCoverBytes=false cacheCoverBytes=true');
          debugPrint('AlbumCover key=$key source=metadata hasBytes=true');
        }
        return coverPath;
      }
    }

    final logKey = 'cover|$key|none';
    if (kAlbumCoverDebug && _albumDisplayLogSeen.add(logKey)) {
      debugPrint(
          'AlbumCover lookup key=$key albumCoverBytes=false brainCoverBytes=false cacheCoverBytes=false');
      debugPrint('AlbumCover key=$key source=none hasBytes=false');
    }
    return '';
  }

  String _albumTitleFromTracks(List<drive.File> tracks) {
    final titles = <String>[];
    for (final track in tracks) {
      final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      final album = meta?.album?.trim() ?? '';
      if (album.isNotEmpty && !_isWeakAlbumDisplayTitle(album)) {
        titles.add(album);
      }
    }
    return _mostCommonCleanValue(titles);
  }

  String _albumArtistFromTracks(List<drive.File> tracks) {
    final artists = <String>[];
    for (final track in tracks) {
      final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      final artist = meta?.artist.trim() ?? '';
      if (artist.isNotEmpty && !_isBadArtistName(artist)) {
        artists.add(artist);
      }
    }
    return _mostCommonCleanValue(artists);
  }

  Map<String, String> _resolvedAlbumMap(Map<String, String> album) {
    final key = _albumCacheKey(album, source: 'album_map');
    final resolved = Map<String, String>.from(album);
    resolved['albumKey'] = key;
    if (resolved['id']?.trim().isNotEmpty == true) {
      resolved['id'] = key;
    } else {
      resolved['id'] = key;
    }
    resolved['displayName'] = _resolvedAlbumTitle(album);
    resolved['artist'] = _resolvedAlbumArtist(album);
    final cover = _resolvedAlbumCover(album);
    if (cover.isNotEmpty) {
      resolved['cover'] = cover;
      resolved['coverUrl'] = cover;
    }
    return resolved;
  }

  Future<bool> _mergeKnownTrackDurationsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_knownTrackDurationsKey);
      if (raw == null || raw.isEmpty) return false;

      final decoded = json.decode(raw);
      if (decoded is! Map) return false;

      var changed = false;
      decoded.forEach((key, value) {
        if (key is! String) return;
        final durationMs = _validDurationMsFromValue(value);
        if (durationMs == null) return;

        if (_knownTrackDurationsMs[key] != durationMs ||
            _libraryTrackIndex[key]?['durationMs'] != durationMs.toString()) {
          changed = true;
        }
        _setKnownTrackDuration(key, durationMs);
      });

      return changed;
    } catch (_) {
      return false;
    }
  }

  String _albumCoverForIndex(Map<String, String> album) {
    final key = _albumCacheKey(album, source: 'album_cover_index');
    final direct = _sanitizeCoverSource(
      album['cover'] ??
          album['customCoverUrl'] ??
          album['coverUrl'] ??
          album['thumbnailLink'] ??
          album['artwork'] ??
          _libraryBrain[key]?['cover'] ??
          '',
    );
    if (direct.isNotEmpty) return direct;
    final tracks = _tracksForAlbumKey(key);
    for (final track in tracks) {
      final cached = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      final cover = _sanitizeCoverSource(cached?.coverPath);
      if (cover.isNotEmpty) return cover;
    }
    return '';
  }

  String _albumStableKey(Map<String, String> album) {
    final id = _albumCacheKey(album, source: 'album_stable');
    if (id.isNotEmpty) return id;
    final artist = (album['artist'] ?? '').trim().toLowerCase();
    final name =
        (album['displayName'] ?? album['name'] ?? '').trim().toLowerCase();
    return '$artist::$name'.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  String _safeArtworkFileName(String value) {
    final cleaned = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return cleaned
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '')
        .trim();
  }

  String _imageExtensionFromHeaders(http.Response response, String url) {
    final type = response.headers['content-type']?.toLowerCase() ?? '';
    if (type.contains('png')) return '.png';
    if (type.contains('webp')) return '.webp';
    if (type.contains('jpeg') || type.contains('jpg')) return '.jpg';
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('.png')) return '.png';
    if (lowerUrl.contains('.webp')) return '.webp';
    return '.jpg';
  }

  bool _repairLibraryTrackIndexFromAlbums() {
    if (_libraryTrackIndex.isEmpty || _albums.isEmpty) return false;

    final albumsById = <String, Map<String, String>>{};
    for (final album in _albums) {
      final id = album['id'] ?? '';
      if (id.isNotEmpty) albumsById[id] = album;
    }

    var changed = false;
    for (final entry in _libraryTrackIndex.entries) {
      final record = entry.value;
      final albumId = record['albumId'] ?? '';
      final album = albumsById[albumId];
      if (album != null) {
        final albumCover = _albumCoverForIndex(album);
        if (albumCover.isNotEmpty && record['albumCover'] != albumCover) {
          record['albumCover'] = albumCover;
          changed = true;
        }
      }

      final durationMs = _knownTrackDurationsMs[entry.key];
      if (durationMs != null &&
          durationMs > 0 &&
          durationMs < 86400000 &&
          record['durationMs'] != durationMs.toString()) {
        record['durationMs'] = durationMs.toString();
        changed = true;
      }
    }

    return changed;
  }

  bool _applyAlbumCoverFromMetadataScan(
    String albumId,
    String coverPath, {
    bool persistChanges = true,
    bool refreshUi = true,
  }) {
    if (albumId.trim().isEmpty || coverPath.trim().isEmpty) return false;

    var changed = false;
    for (final album in _albums) {
      if ((album['id'] ?? '') == albumId && album['cover'] != coverPath) {
        album['cover'] = coverPath;
        changed = true;
        break;
      }
    }

    if (_viewingAlbum != null && (_viewingAlbum!['id'] ?? '') == albumId) {
      if (_viewingAlbum!['cover'] != coverPath) {
        _viewingAlbum!['cover'] = coverPath;
        changed = true;
      }
    }

    final brain = _libraryBrain[albumId];
    if (brain != null && brain['cover'] != coverPath) {
      brain['cover'] = coverPath;
      changed = true;
      if (persistChanges) _saveLibraryBrain();
    }

    for (final record in _libraryTrackIndex.values) {
      if ((record['albumId'] ?? '') == albumId &&
          record['albumCover'] != coverPath) {
        record['albumCover'] = coverPath;
        changed = true;
      }
    }

    if (changed && persistChanges) {
      _librarySearchTextCache.clear();
      _persistAlbums();
      _saveLibraryTrackIndex();
      _invalidateHomeBrowseCache();
      _invalidateLibraryBrowseCache();
      if (refreshUi && mounted) setState(() {});
    }

    return changed;
  }

  void _queueAlbumCoverFromMetadataScan(String albumId, String coverPath) {
    final normalizedId =
        _albumCacheKey(albumId, source: 'metadata_cover_found');
    if (normalizedId.trim().isEmpty || coverPath.trim().isEmpty) return;
    _pendingAlbumCoverUpdates[normalizedId] = coverPath;
    _pendingAlbumCoverFlushTimer ??=
        Timer(const Duration(milliseconds: 500), _flushPendingAlbumCovers);
  }

  void _flushPendingAlbumCovers() {
    _pendingAlbumCoverFlushTimer?.cancel();
    _pendingAlbumCoverFlushTimer = null;
    if (_pendingAlbumCoverUpdates.isEmpty) return;

    final pending = Map<String, String>.from(_pendingAlbumCoverUpdates);
    _pendingAlbumCoverUpdates.clear();

    var changed = false;
    for (final entry in pending.entries) {
      if (_applyAlbumCoverFromMetadataScan(
        entry.key,
        entry.value,
        persistChanges: false,
        refreshUi: false,
      )) {
        changed = true;
      }
    }

    if (changed) {
      _librarySearchTextCache.clear();
      _saveLibraryBrain();
      _persistAlbums();
      _saveLibraryTrackIndex();
      _invalidateHomeBrowseCache();
      _invalidateLibraryBrowseCache();
      _nowPlaying.refresh();
      debugPrint('UI refresh after cover scan');
      if (mounted) setState(() {});
    }
  }

  Future<void> _syncForegroundMetadataResults() async {
    if (_syncingForegroundMetadataResults) return;
    _syncingForegroundMetadataResults = true;

    try {
      await _mergeKnownTrackDurationsFromPrefs();
      await _metaStore.reload();
      await _loadAlbums();

      final repaired = _repairLibraryTrackIndexFromAlbums();
      if (repaired) await _saveLibraryTrackIndex();

      await _saveKnownTrackDurations();

      if (!mounted) return;
      _librarySearchTextCache.clear();
      _nowPlaying.refresh();
      setState(() {});
    } finally {
      _syncingForegroundMetadataResults = false;
    }
  }

  String _formatDurationMs(int ms) => _formatDurationMsFromPart(ms);

  Future<Duration?> _getDurationWithTemporaryPlayer(
      drive.File file, String token) async {
    final fileId = DriveUtils.effectiveId(file);
    if (fileId == null) return null;

    // Check if we already have duration in cache
    final cachedMs = _knownTrackDurationsMs[fileId];
    if (cachedMs != null && cachedMs > 0) {
      return Duration(milliseconds: cachedMs);
    }

    // Use temporary AudioPlayer to get duration
    final tempPlayer = AudioPlayer();
    try {
      final source = DriveAudioSource(
        fileId,
        token,
        knownSourceLength: int.tryParse(file.size ?? ''),
      );

      Duration? duration = await tempPlayer
          .setAudioSource(source)
          .timeout(const Duration(seconds: 10), onTimeout: () => null);

      duration ??= await tempPlayer.durationStream
          .firstWhere((value) => value != null)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      final durationMs = _validDurationMsFromValue(duration?.inMilliseconds);
      if (durationMs != null) {
        return Duration(milliseconds: durationMs);
      }
    } catch (e) {
      // Continue on error
      return null;
    } finally {
      await tempPlayer.dispose();
    }

    return null;
  }

  Future<void> _clearLibraryTrackIndex() async {
    _libraryTrackIndex.clear();
    await _saveLibraryTrackIndex();
    _invalidateLibraryBrowseCache();
  }

  Future<void> _buildLibraryTrackIndex() async {
    if (_user == null || _albums.isEmpty) {
      _showError('Sign in and add albums first.');
      return;
    }

    setState(() {
      _loadingSaved = true;
    });

    try {
      final headers = await _user!.authHeaders;
      final api = drive.DriveApi(GoogleAuthClient(headers));
      final newIndex = <String, Map<String, String>>{};

      for (final album in _albums) {
        if (!mounted) return;

        try {
          final tracks = await _fetchTracksForAlbumRecord(api, album);
          final sortedTracks = _sortTracksForAlbum(tracks);

          _albumTracksCache[album['id'] ?? ''] = sortedTracks;

          for (final track in sortedTracks) {
            final trackId = DriveUtils.effectiveId(track);
            if (trackId == null || trackId.isEmpty) continue;

            final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
            final trackMeta = DriveUtils.getTrackMeta(track);

            final albumCover = _albumCoverForIndex(album);

            final durationMs = _knownTrackDurationsMs[trackId] ??
                _validDurationMsFromValue(
                    _libraryTrackIndex[trackId]?['durationMs']) ??
                _validDurationMsFromValue(meta?.durationMs) ??
                _validDurationMsFromValue(trackMeta['durationMs']);
            if (durationMs != null) _setKnownTrackDuration(trackId, durationMs);

            final record = <String, String>{
              'id': trackId,
              'name': track.name ?? '',
              'albumId': album['id'] ?? '',
              'albumName': (meta?.album?.trim().isNotEmpty == true)
                  ? meta!.album!.trim()
                  : (album['displayName'] ?? album['name'] ?? ''),
              'albumArtist': _canonicalArtistName(
                albumArtist: album['artist'],
                trackArtist:
                    meta?.artist ?? trackMeta['artist']?.toString() ?? '',
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
              record['title'] =
                  trackMeta['title']?.toString() ?? track.name ?? '';
              record['artist'] = trackMeta['artist']?.toString() ?? '';
              record['album'] = album['displayName'] ?? album['name'] ?? '';
              record['year'] = trackMeta['year']?.toString() ?? '';
              record['genre'] = trackMeta['genre']?.toString() ?? '';
              record['trackNumber'] =
                  trackMeta['trackNumber']?.toString() ?? '';
              record['discNumber'] = trackMeta['discNumber']?.toString() ?? '';
            }

            newIndex[trackId] = record;
          }
        } catch (e) {
          // Continue even if one album fails
          continue;
        }
      }

      // Replace the index at the end
      _libraryTrackIndex.clear();
      _libraryTrackIndex.addAll(newIndex);
      await _saveLibraryTrackIndex();
      _invalidateLibraryBrowseCache();
      _queueArtistImagePrefetch();

      if (!mounted) return;

      setState(() {
        _loadingSaved = false;
      });

      _showSuccess('Song index built successfully.');
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingSaved = false;
        });
        _showError('Failed to build song index: $e');
      }
    }
  }

  drive.File _fileFromTrackIndexRecord(Map<String, String> record) {
    final modifiedTime = int.tryParse(record['modifiedTime'] ?? '');
    final file = drive.File()
      ..id = record['id']
      ..name = record['name']
      ..mimeType = record['mimeType']
      ..thumbnailLink = record['thumbnailLink']
      ..size = record['size'] ?? '0'
      ..modifiedTime = modifiedTime != null
          ? DateTime.fromMillisecondsSinceEpoch(modifiedTime)
          : null;

    final source = (record['source'] ?? '').trim();
    final localPath = (record['localPath'] ?? '').trim();
    final localUri = (record['localUri'] ?? '').trim();
    if (source.isNotEmpty || localPath.isNotEmpty || localUri.isNotEmpty) {
      file.appProperties = <String, String>{
        if (source.isNotEmpty) 'source': source,
        if (localPath.isNotEmpty) 'path': localPath,
        if (localUri.isNotEmpty) 'localUri': localUri,
      };
      file.properties = Map<String, String>.from(file.appProperties!);
    }

    return file;
  }

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

  String _cleanBrainValue(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty ||
        v.toLowerCase() == 'unknown' ||
        v.toLowerCase() == 'unknown artist') {
      return '';
    }
    return v;
  }

  String _yearFromText(String value) {
    final match = RegExp(r'(19|20)\d{2}').firstMatch(value);
    return match?.group(0) ?? '';
  }

  String _decadeFromYear(String year) {
    final y = int.tryParse(year);
    if (y == null) return '';
    return '${(y ~/ 10) * 10}s';
  }

  Map<String, String> _artistAlbumFromFolder(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'\s*\[(19|20)\d{2}\]\s*'), ' ')
        .replaceAll(RegExp(r'\s*\((19|20)\d{2}\)\s*'), ' ')
        .trim();

    final parts = cleaned.split(RegExp(r'\s+[–—-]\s+'));
    if (parts.length < 2) return const <String, String>{};

    // Assume format is "Album - Artist" (not "Artist - Album")
    final album = _cleanBrainValue(parts.first);
    final artist = _cleanBrainValue(parts.sublist(1).join(' - '));
    if (artist.isEmpty || album.isEmpty) return const <String, String>{};

    return {
      'artist': artist,
      'album': album,
    };
  }

  bool _looksLikeOldNameGuessedGenre(String? genre, String context) {
    final g = _cleanBrainValue(genre);
    if (g.isEmpty) return false;

    final t = context.toLowerCase();
    if (g == 'Rock' &&
        (t.contains('pete rock') ||
            t.contains('a\$ap rock') ||
            t.contains('asap rock') ||
            t.contains('rocky') ||
            t.contains('metal fingers') ||
            t.contains('metalface') ||
            t.contains('mf doom'))) {
      return true;
    }

    if (g == 'Soul / R&B' && t.contains('de la soul')) return true;

    return false;
  }

  String _genreFromText(String text) {
    // Intentionally disabled. Infame should never guess genre from artist,
    // album, or folder names. Names like Pete Rock, A$AP Rocky, De La Soul,
    // and Metal Fingers made the old guessing system poison the library.
    // Only trusted embedded tag genres should be used.
    return '';
  }

  String _normalizeGenre(String value) {
    final g = _cleanBrainValue(value);
    if (g.isEmpty) return '';

    final first = g.split('/').first.split(';').first.split(',').first.trim();
    final t = first.toLowerCase();
    final normalized = t.replaceAll(RegExp(r'[^a-z0-9&]+'), ' ').trim();
    final words =
        normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();

    bool has(String word) => words.contains(word);

    if (normalized.contains('hip hop') ||
        t.contains('hip-hop') ||
        has('rap') ||
        has('trap')) {
      return 'Hip-Hop';
    }
    if (t.contains('r&b') || has('rnb') || has('soul') || has('funk'))
      return 'Soul / R&B';
    if (has('jazz')) return 'Jazz';
    if (has('rock') || has('metal') || has('punk')) return 'Rock';
    if (has('electronic') || has('house') || has('techno') || has('dance')) {
      return 'Electronic';
    }
    if (has('soundtrack') || has('score')) return 'Soundtracks';
    if (has('pop')) return 'Pop';

    return first;
  }

  String _mostCommon(List<String> values) {
    final counts = <String, int>{};
    for (final raw in values) {
      final value = _cleanBrainValue(raw);
      if (value.isEmpty) continue;
      counts[value] = (counts[value] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';

    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });

    return entries.first.key;
  }

  int _brainInt(Map<String, String> info, String key) {
    return int.tryParse(info[key] ?? '') ?? 0;
  }

  Future<void> _loadLibraryBrainAndHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final brainRaw = prefs.getString(_libraryBrainPrefsKey);
      final historyRaw = prefs.getString(_playHistoryPrefsKey);

      final nextBrain = <String, Map<String, String>>{};
      if (brainRaw != null && brainRaw.isNotEmpty) {
        final decoded = json.decode(brainRaw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is String && value is Map) {
              nextBrain[key] = Map<String, String>.from(value);
            }
          });
        }
      }

      final nextHistory = <Map<String, String>>[];
      if (historyRaw != null && historyRaw.isNotEmpty) {
        final decoded = json.decode(historyRaw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) nextHistory.add(Map<String, String>.from(item));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _libraryBrain
          ..clear()
          ..addAll(nextBrain);
        _playHistory
          ..clear()
          ..addAll(nextHistory.take(40));
      });

      _invalidateHomeBrowseCache();
      unawaited(_rebuildBrainWithCorrectParsing());
      _buildBasicLibraryBrain(save: false);
      _queueArtistImagePrefetch();
      _prewarmHomeMetadataCache();
    } catch (_) {}
  }

  Future<void> _rebuildBrainWithCorrectParsing() async {
    // Fix any albums that have swapped artist/album from old folder parsing
    debugPrint(
        '[BrainFix] Checking for swapped metadata in ${_libraryBrain.length} albums');
    int fixed = 0;
    var processed = 0;

    for (final entry in _libraryBrain.entries.toList()) {
      processed++;
      if (processed % 24 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final id = entry.key;
      final brain = entry.value;
      final name = brain['name'] ?? '';

      // Re-parse folder name with correct logic
      final folderGuess = _artistAlbumFromFolder(name);
      if (folderGuess.isEmpty) continue;

      final currentDisplayName = brain['displayName'] ?? '';
      final currentArtist = brain['artist'] ?? '';
      final guessedAlbum = folderGuess['album'] ?? '';
      final guessedArtist = folderGuess['artist'] ?? '';

      // Check if metadata looks swapped (album name matches artist field, artist name matches displayName field)
      if (currentDisplayName.isNotEmpty &&
          currentArtist.isNotEmpty &&
          guessedAlbum.isNotEmpty &&
          guessedArtist.isNotEmpty) {
        // If current displayName looks like an artist and current artist looks like an album
        if (currentDisplayName
                .toLowerCase()
                .contains(guessedArtist.toLowerCase()) &&
            currentArtist.toLowerCase().contains(guessedAlbum.toLowerCase())) {
          // Swap them
          brain['displayName'] = guessedAlbum;
          brain['artist'] = guessedArtist;
          _libraryBrain[id] = brain;
          fixed++;
          debugPrint(
              '[BrainFix] Fixed $id: "$currentDisplayName" by "$currentArtist" → "$guessedAlbum" by "$guessedArtist"');
        }
      }
    }

    if (fixed > 0) {
      debugPrint('[BrainFix] Fixed $fixed albums with swapped metadata');
      _saveLibraryBrain();
    }
  }

  void _prewarmHomeMetadataCache() {
    if (_albums.isEmpty) return;
    // Pre-resolve metadata for home tab albums in background
    // This prevents freeze on first home tab render
    Future.microtask(() {
      try {
        final recent = _recentBrainAlbums(limit: 14);
        final played = _lastPlayedAlbums(limit: 10);
        final primaryAlbums = played.isNotEmpty ? played : recent;

        // Resolve a few albums at a time to avoid blocking
        for (final album in primaryAlbums.take(5)) {
          _resolvedAlbumMap(album);
        }
        for (final album in _albums.take(10)) {
          _resolvedAlbumMap(album);
        }
      } catch (_) {}
    });
  }

  Future<void> _saveLibraryBrain() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_libraryBrainPrefsKey, json.encode(_libraryBrain));
  }

  Future<void> _savePlayHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _playHistoryPrefsKey, json.encode(_playHistory.take(40).toList()));
  }

  void _buildBasicLibraryBrain({bool save = true}) {
    if (_albums.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch.toString();
    bool changed = false;

    for (final album in _albums) {
      final id = _albumCacheKey(album, source: 'build_brain');
      if (id.isEmpty) continue;

      final existing = _libraryBrain[id] ?? <String, String>{};
      final name = album['name'] ?? existing['name'] ?? 'Album';
      final folderGuess = _artistAlbumFromFolder(name);
      final cover = album['cover'] ?? existing['cover'] ?? '';
      final dateAdded = album['dateAdded'] ?? existing['dateAdded'] ?? now;
      final savedArtist = _canonicalArtistName(
        albumArtist: album['artist'],
        trackArtist: existing['artist'] ?? '',
        albumName: name,
      );
      final savedDisplayName = _cleanBrainValue(album['displayName']).isNotEmpty
          ? album['displayName']!
          : _cleanBrainValue(existing['displayName']).isNotEmpty
              ? existing['displayName']!
              : folderGuess['album'] ?? name;
      final year = _cleanBrainValue(album['year']).isNotEmpty
          ? album['year']!
          : _cleanBrainValue(existing['year']).isNotEmpty
              ? existing['year']!
              : _yearFromText(name);
      final rawGenre = _cleanBrainValue(album['genre']).isNotEmpty
          ? _normalizeGenre(album['genre']!)
          : _cleanBrainValue(existing['genre']).isNotEmpty
              ? _normalizeGenre(existing['genre']!)
              : '';
      final genre =
          _looksLikeOldNameGuessedGenre(rawGenre, '$name $savedArtist')
              ? ''
              : rawGenre;

      album['dateAdded'] = dateAdded;
      album['id'] = id;
      album['albumKey'] = id;

      final next = <String, String>{
        'albumId': id,
        'name': name,
        'displayName': savedDisplayName,
        'artist': savedArtist,
        'year': year,
        'decade': _decadeFromYear(year),
        'genre': genre,
        'cover': cover,
        'trackCount': album['trackCount'] ?? existing['trackCount'] ?? '',
        'playCount': existing['playCount'] ?? '0',
        'lastPlayed': existing['lastPlayed'] ?? '',
        'dateAdded': dateAdded,
      };

      if (json.encode(existing) != json.encode(next)) {
        _libraryBrain[id] = next;
        changed = true;
      }
    }

    if (changed && save) {
      if (mounted) setState(() {});
      _saveLibraryBrain();
      _persistAlbums();
    }
  }

  void _indexAlbumFromTracks(Map<String, String> album, List<drive.File> tracks,
      {bool save = true}) {
    final id = _albumCacheKey(album, source: 'index_album');
    if (id.isEmpty) return;

    final existing = _libraryBrain[id] ?? <String, String>{};
    final artists = <String>[];
    final albumNames = <String>[];
    final years = <String>[];
    final genres = <String>[];

    for (final track in tracks) {
      final cached = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      if (cached == null) continue;
      artists.add(cached.artist);
      if (cached.album != null) albumNames.add(cached.album!);
      if (cached.year != null) years.add(cached.year!);
      if (cached.genre != null) genres.add(cached.genre!);
    }

    final folderName = album['name'] ?? existing['name'] ?? 'Album';
    final folderGuess = _artistAlbumFromFolder(folderName);
    final commonArtist = _mostCommonCleanValue(
      artists,
      accept: (value) => !_isBadArtistName(value),
    );
    final commonAlbum = _mostCommonCleanValue(
      albumNames,
      accept: (value) => !_isWeakAlbumDisplayTitle(value, artist: commonArtist),
    );
    final displayName = commonAlbum.isNotEmpty
        ? commonAlbum
        : (!_isWeakAlbumDisplayTitle(existing['displayName'],
                artist: commonArtist)
            ? existing['displayName']!
            : (folderGuess['album'] ?? folderName));
    final artist = _canonicalArtistName(
      albumArtist: commonArtist,
      trackArtist: existing['artist'] ?? '',
      albumName: displayName,
    );
    final rawYear = _mostCommon(years).isNotEmpty
        ? _mostCommon(years)
        : _yearFromText('$displayName $folderName');
    final rawGenre = _normalizeGenre(_mostCommon(genres));

    final next = <String, String>{
      'albumId': id,
      'name': folderName,
      'displayName': displayName,
      'artist': artist,
      'year': rawYear,
      'decade': _decadeFromYear(rawYear),
      'genre': rawGenre,
      'cover': album['cover'] ?? existing['cover'] ?? '',
      'trackCount': tracks.length.toString(),
      'playCount': existing['playCount'] ?? '0',
      'lastPlayed': existing['lastPlayed'] ?? '',
      'dateAdded': album['dateAdded'] ??
          existing['dateAdded'] ??
          DateTime.now().millisecondsSinceEpoch.toString(),
    };

    album['displayName'] = displayName;
    album['artist'] = artist;
    album['year'] = rawYear;
    album['genre'] = rawGenre;
    album['trackCount'] = tracks.length.toString();
    album['id'] = id;
    album['albumKey'] = id;

    _libraryBrain[id] = next;
    if (save) {
      _saveLibraryBrain();
      _persistAlbums();
      if (mounted) setState(() {});
    }
  }

  Future<void> _recordPlay(drive.File file, {String? coverUrl}) async {
    final fileId = DriveUtils.effectiveId(file);
    if (fileId == null) return;

    final meta = DriveUtils.getTrackMeta(file);
    final safeCoverUrl = _sanitizeCoverSource(coverUrl);
    final currentAlbum = _viewingAlbum;
    final albumId = currentAlbum == null
        ? ''
        : _albumCacheKey(currentAlbum, source: 'record_play');
    final albumName =
        currentAlbum == null ? '' : _resolvedAlbumTitle(currentAlbum);
    final now = DateTime.now().millisecondsSinceEpoch.toString();

    _playHistory.removeWhere((item) => item['fileId'] == fileId);
    _playHistory.insert(0, {
      'fileId': fileId,
      'title': meta['title'] ?? file.name ?? 'Unknown',
      'artist': meta['artist'] ?? 'Unknown Artist',
      'albumId': albumId,
      'albumName': albumName.isNotEmpty ? albumName : (meta['album'] ?? ''),
      'albumKey': albumId,
      'cover': safeCoverUrl.isNotEmpty
          ? safeCoverUrl
          : _sanitizeCoverSource(currentAlbum?['cover']),
      'playedAt': now,
    });

    if (_playHistory.length > 40) {
      _playHistory.removeRange(40, _playHistory.length);
    }

    if (albumId.isNotEmpty) {
      final existing = _libraryBrain[albumId] ?? <String, String>{};
      existing['albumId'] = albumId;
      existing['name'] = existing['name'] ?? albumName;
      existing['displayName'] = existing['displayName'] ?? albumName;
      existing['cover'] = safeCoverUrl.isNotEmpty
          ? safeCoverUrl
          : _sanitizeCoverSource(existing['cover'] ?? currentAlbum?['cover']);
      existing['playCount'] =
          ((_brainInt(existing, 'playCount')) + 1).toString();
      existing['lastPlayed'] = now;
      existing['dateAdded'] =
          existing['dateAdded'] ?? _viewingAlbum?['dateAdded'] ?? now;
      _libraryBrain[albumId] = Map<String, String>.from(existing);
      _saveLibraryBrain();
    }

    _savePlayHistory();
    _invalidateHomeBrowseCache();
    if (mounted) setState(() {});
  }

  List<Map<String, String>> _brainAlbums() {
    _buildBasicLibraryBrain(save: false);

    final items = _albums
        .map((album) {
          final key = _albumCacheKey(album, source: 'brain_album');
          final brain = Map<String, String>.from(
              _libraryBrain[key] ?? <String, String>{});
          final resolved = _resolvedAlbumMap({
            ...album,
            'id': key,
            'albumKey': key,
            ...brain,
          });
          resolved['albumId'] = key;
          resolved['dateAdded'] =
              album['dateAdded'] ?? brain['dateAdded'] ?? '0';
          return resolved;
        })
        .where((item) => (item['albumId'] ?? '').isNotEmpty)
        .toList();

    return items;
  }

  Map<String, String>? _albumById(String id) {
    for (final album in _albums) {
      if (_albumCacheKey(album, source: 'album_by_id') == id ||
          (album['id'] ?? '') == id) {
        return album;
      }
    }
    return null;
  }

  void _openAlbumByBrain(Map<String, String> info) {
    final id = _albumCacheKey(info, source: 'open_by_brain');
    final album = _albumById(id);
    if (album != null) _openAlbum(album);
  }

  List<Map<String, String>> _recentBrainAlbums({int limit = 8}) {
    final items = _brainAlbums()
      ..sort((a, b) =>
          _brainInt(b, 'dateAdded').compareTo(_brainInt(a, 'dateAdded')));
    return items.take(limit).toList();
  }

  List<Map<String, String>> _lastPlayedAlbums({int limit = 8}) {
    final items = _brainAlbums()
        .where((a) => _brainInt(a, 'lastPlayed') > 0)
        .toList()
      ..sort((a, b) =>
          _brainInt(b, 'lastPlayed').compareTo(_brainInt(a, 'lastPlayed')));
    return items.take(limit).toList();
  }

  List<Map<String, String>> _albumsForGenre(String genre, {int limit = 8}) {
    final items = _brainAlbums()
        .where((a) => (a['genre'] ?? '') == genre)
        .toList()
      ..sort((a, b) =>
          _brainInt(b, 'dateAdded').compareTo(_brainInt(a, 'dateAdded')));
    return items.take(limit).toList();
  }

  List<Map<String, String>> _albumsForDecade(String decade, {int limit = 8}) {
    final items = _brainAlbums()
        .where((a) => (a['decade'] ?? '') == decade)
        .toList()
      ..sort(
          (a, b) => (a['displayName'] ?? '').compareTo(b['displayName'] ?? ''));
    return items.take(limit).toList();
  }

  List<String> _topGenres({int limit = 3}) {
    final counts = <String, int>{};
    for (final album in _brainAlbums()) {
      final genre = album['genre'] ?? '';
      if (genre.isEmpty) continue;
      counts[genre] = (counts[genre] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList();
  }

  List<String> _topDecades({int limit = 3}) {
    final counts = <String, int>{};
    for (final album in _brainAlbums()) {
      final decade = album['decade'] ?? '';
      if (decade.isEmpty) continue;
      counts[decade] = (counts[decade] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return entries.take(limit).map((e) => e.key).toList();
  }

  List<Map<String, String>> _topArtists({int limit = 12}) {
    final counts = <String, int>{};
    for (final album in _brainAlbums()) {
      final artist = _cleanBrainValue(album['artist']);
      if (artist.isEmpty) continue;
      counts[artist] = (counts[artist] ?? 0) + 1;
    }

    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });

    return entries
        .take(limit)
        .map((e) => {'artist': e.key, 'count': e.value.toString()})
        .toList();
  }

  Future<void> _rebuildSmartHomeIndex() async {
    _libraryBrain.clear();
    _buildBasicLibraryBrain(save: false);

    for (final album in _albums) {
      final tracks = _albumTracksCache[album['id'] ?? ''];
      if (tracks != null && tracks.isNotEmpty) {
        _indexAlbumFromTracks(album, tracks, save: false);
      }
    }

    await _saveLibraryBrain();
    await _persistAlbums();
    if (mounted) setState(() {});
    _showSuccess('Smart Home index rebuilt from cached metadata.');
  }

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
        return 'Last scan complete • $_metadataTotal tracks';
      }
      return 'Metadata scanner is idle';
    }

    if (_metadataTotal <= 0) {
      final phase =
          _metadataPhase.trim().isEmpty ? 'Preparing' : _metadataPhase;
      return '$phase metadata scan...';
    }

    final base =
        'Scanning metadata $_metadataDone/$_metadataTotal • Fast: $_metadataFast • Deep: $_metadataDeep • Failed: $_metadataFailed';
    return includeTapToCancel ? '$base — tap to cancel' : base;
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

  // ── Auth ──────────────────────────────────────────────────────────────────
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

  // ── Local Database ─────────────────────────────────────────────────────────
  Future<void> _loadAlbums() async {
    setState(() => _loadingSaved = true);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_albumsKey);
    final now = DateTime.now().millisecondsSinceEpoch.toString();

    if (!mounted) return;

    var changed = false;
    final loadedAlbums = raw != null
        ? List<Map<String, String>>.from(
            (json.decode(raw) as List).map((e) => Map<String, String>.from(e)),
          )
        : <Map<String, String>>[];

    for (final album in loadedAlbums) {
      final normalizedId = _albumCacheKey(album, source: 'load_album');
      if (normalizedId.isNotEmpty) {
        album['id'] = normalizedId;
        album['albumKey'] = normalizedId;
      }
      if ((album['dateAdded'] ?? '').isEmpty) {
        album['dateAdded'] = now;
        changed = true;
      }
    }

    setState(() {
      _albums = loadedAlbums;
      _librarySearchTextCache.clear();
      _shuffledExploreAlbums = (List<Map<String, String>>.from(loadedAlbums)
            ..shuffle())
          .take(14)
          .toList();
      _loadingSaved = false;
    });

    _invalidateHomeBrowseCache();
    _invalidateLibraryBrowseCache();
    _buildBasicLibraryBrain(save: true);
    final repairedIndex = _repairLibraryTrackIndexFromAlbums();
    if (repairedIndex) await _saveLibraryTrackIndex();
    if (_albums.any(_isLocalAlbumRecord)) {
      _rebuildLocalAlbumTrackCacheFromIndex(log: true);
    }
    if (changed) await _persistAlbums();
    _logStartupSourceState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _precacheAlbumCovers(limit: 36);
    });
  }

  void _precacheAlbumCovers({int limit = 36}) {
    final candidates = _albums
        .map((album) => album['cover'] ?? '')
        .where((cover) => cover.isNotEmpty)
        .where((cover) => _isLocalCover(cover))
        .take(limit);

    for (final cover in candidates) {
      final provider = _coverProvider(cover);
      if (provider != null) {
        precacheImage(provider, context).catchError((_) {});
      }
    }
  }

  Future<void> _persistAlbums() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_albumsKey, json.encode(_albums));
  }

  String _audioExtension(drive.File file) {
    final name = file.name ?? 'track.mp3';
    final dot = name.lastIndexOf('.');
    if (dot == -1) return '.mp3';
    return name.substring(dot).toLowerCase();
  }

  String _safeCacheName(String id) {
    return id
        .replaceAll('/', '_')
        .replaceAll(':', '_')
        .replaceAll('?', '_')
        .replaceAll('&', '_')
        .replaceAll('=', '_');
  }

  Future<File> _downloadTrackToTemp(
      String fileId, String token, String extension) async {
    final dir = await getTemporaryDirectory();
    final unique = DateTime.now().microsecondsSinceEpoch;
    final path =
        '${dir.path}/musix_meta_${_safeCacheName(fileId)}_$unique$extension';
    final tempFile = File(path);

    final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
    final client = http.Client();

    try {
      final request = http.Request('GET', uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'User-Agent': 'InfameApp/1.0',
        })
        ..followRedirects = false;

      final response = await client.send(request);
      http.StreamedResponse finalResponse = response;

      if (response.isRedirect && response.headers.containsKey('location')) {
        final redirectUri = Uri.parse(response.headers['location']!);
        final secondRequest = http.Request('GET', redirectUri);
        finalResponse = await client.send(secondRequest);
      }

      if (finalResponse.statusCode != 200 && finalResponse.statusCode != 206) {
        throw Exception(
            'Could not download metadata file: ${finalResponse.statusCode}');
      }

      final sink = tempFile.openWrite();
      await finalResponse.stream.pipe(sink);
      return tempFile;
    } finally {
      client.close();
    }
  }

  String _coverExtensionFromBytes(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return '.png';
    }

    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return '.jpg';
    }

    if (bytes.length >= 12 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return '.webp';
    }

    return '.jpg';
  }

  Future<String?> _saveEmbeddedCover(drive.File file, Uint8List bytes) async {
    final fileId = DriveUtils.effectiveId(file);
    if (fileId == null || bytes.isEmpty) return null;

    try {
      _pendingAlbumCoverFlushTimer?.cancel();
      _pendingAlbumCoverFlushTimer = null;
      _pendingAlbumCoverUpdates.clear();

      final dir = await getApplicationDocumentsDirectory();
      final coverDir = Directory('${dir.path}/musix_embedded_covers');
      if (!await coverDir.exists()) {
        await coverDir.create(recursive: true);
      }

      final ext = _coverExtensionFromBytes(bytes);
      final path = '${coverDir.path}/${_safeCacheName(fileId)}$ext';
      final out = File(path);
      await out.writeAsBytes(bytes, flush: true);
      return 'file://$path';
    } catch (_) {
      return null;
    }
  }

  void _applyEmbeddedCoverToAlbum(
    drive.File file,
    String coverPath, {
    Map<String, String>? albumRecord,
  }) {
    final fileId = DriveUtils.effectiveId(file);
    final safeCoverPath = _sanitizeCoverSource(coverPath);
    if (safeCoverPath.isEmpty) return;
    bool changed = false;

    void applyToAlbum(Map<String, String> album) {
      album['cover'] = safeCoverPath;
      changed = true;
    }

    if (albumRecord != null) {
      final albumId = _albumCacheKey(albumRecord, source: 'apply_cover');
      for (final album in _albums) {
        if (_albumCacheKey(album, source: 'apply_cover_saved') == albumId ||
            album['id'] == albumId) {
          applyToAlbum(album);
          break;
        }
      }

      if (_viewingAlbum != null &&
          (_albumCacheKey(_viewingAlbum!, source: 'apply_cover_view') ==
                  albumId ||
              _viewingAlbum!['id'] == albumId)) {
        _viewingAlbum!['cover'] = safeCoverPath;
        changed = true;
      }
    } else if (_viewingAlbum != null && fileId != null) {
      final inCurrentAlbum =
          _albumTracks.any((track) => DriveUtils.effectiveId(track) == fileId);
      if (inCurrentAlbum) {
        _viewingAlbum!['cover'] = safeCoverPath;
        for (final album in _albums) {
          if (album['id'] == _viewingAlbum!['id']) {
            album['cover'] = safeCoverPath;
            break;
          }
        }
        changed = true;
      }
    }

    if (_nowPlaying.track != null && fileId != null) {
      final activeId = DriveUtils.effectiveId(_nowPlaying.track!);
      if (activeId == fileId) {
        _nowPlaying.currentCoverUrl = safeCoverPath;
        _nowPlaying.refresh();
      }
    }

    if (changed) {
      final albumIdForCover = albumRecord?['id'] ?? _viewingAlbum?['id'] ?? '';
      final normalizedAlbumId = _albumCacheKey(
        albumRecord ?? _viewingAlbum ?? <String, String>{},
        source: 'apply_cover_record',
      );
      if (albumIdForCover.isNotEmpty) {
        for (final record in _libraryTrackIndex.values) {
          if ((record['albumId'] ?? '') == albumIdForCover ||
              (record['albumId'] ?? '') == normalizedAlbumId) {
            record['albumCover'] = safeCoverPath;
          }
        }
        _saveLibraryTrackIndex();
      }
      _persistAlbums();
      debugPrint('UI refresh after cover scan');
      if (mounted) setState(() {});
    }
  }

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

  Future<void> _loadMetadataForEntireLibrary() async {
    if (_user == null || _albums.isEmpty || _loadingMetadata) return;

    setState(() {
      _loadingMetadata = true;
      _metadataDone = 0;
      _metadataTotal = 0;
    });

    try {
      final authHeaders = await _user!.authHeaders;
      final bearer =
          authHeaders['Authorization'] ?? authHeaders['authorization'] ?? '';
      if (!bearer.startsWith('Bearer ')) {
        throw Exception('Could not get Google token.');
      }

      final token = bearer.substring(7);
      final api = drive.DriveApi(GoogleAuthClient(authHeaders));
      final Map<String, drive.File> uniqueTracks = {};
      final Map<String, Map<String, String>> trackAlbums = {};

      for (final album in _albums) {
        if (!mounted) return;
        final tracks = await _fetchTracksForAlbumRecord(api, album);
        _albumTracksCache[album['id'] ?? ''] = _sortTracksForAlbum(tracks);

        for (final track in tracks) {
          final id = DriveUtils.effectiveId(track);
          if (id != null) {
            uniqueTracks[id] = track;
            trackAlbums[id] = album;
          }
        }
      }

      int freshCacheHits = 0;
      int missingCount = 0;
      int changedCount = 0;
      final missing = uniqueTracks.values.where((track) {
        final fresh = _metaStore.peekFresh(track);
        final trackId = DriveUtils.effectiveId(track);
        final hasDuration = trackId != null &&
            (_validDurationMsFromValue(
                      _knownTrackDurationsMs[trackId] ??
                          _libraryTrackIndex[trackId]?['durationMs'],
                    ) !=
                    null ||
                _validDurationMsFromValue(fresh?.durationMs) != null);
        if (fresh != null && hasDuration) {
          freshCacheHits++;
          return false;
        }
        if (_metaStore.peek(track) == null) {
          missingCount++;
        } else {
          changedCount++;
        }
        return true;
      }).toList()
        ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

      _verboseScanLog(
        'MetadataScan fresh cache hits=$freshCacheHits missing=$missingCount changed=$changedCount',
      );
      _verboseScanLog('MetadataScan skipped unchanged=$freshCacheHits');

      if (!mounted) return;

      if (missing.isEmpty) {
        for (final album in _albums) {
          final albumId = album['id'] ?? '';
          final cachedTracks = _albumTracksCache[albumId];
          if (cachedTracks != null) {
            _indexAlbumFromTracks(album, cachedTracks, save: false);
            _indexTracksForAlbum(album, cachedTracks);
          }
        }
        await _saveLibraryBrain();
        await _saveLibraryTrackIndex();
        await _persistAlbums();
        _invalidateHomeBrowseCache();
        _invalidateLibraryBrowseCache();
        setState(() => _loadingMetadata = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Metadata is already loaded and album display was refreshed.',
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
        _metadataTotal = missing.length;
        _metadataDone = 0;
      });
      _updateMetadataProgressUi(force: true);

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
            final id = DriveUtils.effectiveId(track);
            await _loadMetadataFor(
              track,
              token,
              albumRecord: id == null ? null : trackAlbums[id],
              textOnly: true,
              persistImmediately: false,
              refreshUi: false,
              client: client,
            );
            if (mounted) {
              _metadataDone++;
              _updateMetadataProgressUi();
            }
            tracksProcessed++;
            if (tracksProcessed % 100 == 0) {
              await _metaStore.persistNow();
              await _saveLibraryTrackIndex();
            }
          },
        );
      } finally {
        client.close();
      }

      if (!mounted) return;

      setState(() => _loadingMetadata = false);
      _updateMetadataProgressUi(force: true);
      await _persistAlbums();

      // Final save of metadata and library index
      await _metaStore.persistNow();

      for (final album in _albums) {
        final albumId = album['id'] ?? '';
        final cachedTracks = _albumTracksCache[albumId];
        if (cachedTracks != null) {
          _indexAlbumFromTracks(album, cachedTracks, save: false);
          _indexTracksForAlbum(album, cachedTracks);
        }
      }
      await _saveLibraryBrain();
      await _saveLibraryTrackIndex();
      _invalidateHomeBrowseCache();
      _invalidateLibraryBrowseCache();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Metadata loaded and cached for ' +
                missing.length.toString() +
                ' library tracks.',
            style: GoogleFonts.inter(
                color: Colors.black, fontWeight: FontWeight.w800),
          ),
          backgroundColor: _accentDefault,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMetadata = false);
        _updateMetadataProgressUi(force: true);
        _showError('Library metadata load failed: ' + e.toString());
      }
    }
  }

  Future<void> _backupLibraryCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_albumsBackupPrefsKey, json.encode(_albums));
  }

  Future<void> _restoreLibraryBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_albumsBackupPrefsKey);

    if (raw == null || raw.isEmpty) {
      _showError('No library backup found yet.');
      return;
    }

    try {
      final restored = List<Map<String, String>>.from(
        (json.decode(raw) as List).map((e) => Map<String, String>.from(e)),
      );

      setState(() {
        _albums = restored
          ..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
        _librarySearchTextCache.clear();
        _shuffledExploreAlbums = (List<Map<String, String>>.from(restored)
              ..shuffle())
            .take(14)
            .toList();
        _viewingAlbum = null;
        _albumTracks = [];
      });

      _buildBasicLibraryBrain(save: false);
      await _persistAlbums();
      await _saveLibraryBrain();
      _showSuccess('Previous library restored.');
    } catch (e) {
      _showError('Could not restore library backup: $e');
    }
  }

  Future<bool> _confirmDangerAction({
    required String title,
    required String body,
    required String confirmText,
  }) async {
    final controller = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF181820),
          surfaceTintColor: Colors.transparent,
          title: Text(
            title,
            style:
                GoogleFonts.inter(color: _textPri, fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                body,
                style: GoogleFonts.inter(
                    color: _textSub, height: 1.45, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Text(
                'Type $confirmText to continue.',
                style: GoogleFonts.inter(
                    color: _textPri, fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                style: GoogleFonts.inter(
                    color: _textPri, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  hintText: confirmText,
                  hintStyle:
                      GoogleFonts.inter(color: _textSub.withOpacity(0.6)),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.12)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.12)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _accentDefault),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Cancel',
                  style: GoogleFonts.inter(
                      color: _textSub, fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                    dialogContext, controller.text.trim() == confirmText);
              },
              child: Text('Confirm',
                  style: GoogleFonts.inter(
                      color: _accentDefault, fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result == true;
  }

  Future<void> _clearLibraryCacheSafely() async {
    if (_albums.isEmpty) {
      _showSuccess('Library cache is already empty.');
      return;
    }

    final confirmed = await _confirmDangerAction(
      title: 'Clear app library cache?',
      body:
          'This does NOT delete anything from Google Drive. It only removes the albums saved inside Infame. A backup will be saved first so you can restore it from Settings.',
      confirmText: 'CLEAR',
    );

    if (!confirmed) return;

    await _backupLibraryCache();

    setState(() {
      _albums.clear();
      _viewingAlbum = null;
      _albumTracks.clear();
      _albumTracksCache.clear();
      _libraryBrain.clear();
      _libraryTrackIndex.clear();
      _playHistory.clear();
      _currentDynamicColors = List<Color>.from(_defaultDynamicColors);
    });

    await _persistAlbums();
    await _saveLibraryBrain();
    await _saveLibraryTrackIndex();
    await _savePlayHistory();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Library cache cleared. Your Drive files are untouched.',
          style: GoogleFonts.inter(
              color: Colors.black, fontWeight: FontWeight.w900),
        ),
        backgroundColor: _accentDefault,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'RESTORE',
          textColor: Colors.black,
          onPressed: _restoreLibraryBackup,
        ),
      ),
    );
  }

  Future<void> _clearMetadataCacheSafely() async {
    final confirmed = await _confirmDangerAction(
      title: 'Clear metadata cache?',
      body:
          'Song titles, artists, album metadata and cached scan results will be removed. Your Drive music files stay untouched.',
      confirmText: 'CLEAR',
    );

    if (!confirmed) return;

    await _metaStore.clear();
    _librarySearchTextCache.clear();
    for (final album in _albums) {
      album.remove('displayName');
      album.remove('artist');
      album.remove('year');
      album.remove('genre');
      album.remove('trackCount');
    }
    _libraryBrain.clear();
    _buildBasicLibraryBrain(save: false);
    await _persistAlbums();
    await _saveLibraryBrain();
    _nowPlaying.refresh();
    if (mounted) setState(() {});
    _showSuccess('Metadata cache cleared.');
  }

  Future<void> _clearCoverCacheSafely() async {
    final confirmed = await _confirmDangerAction(
      title: 'Clear embedded cover cache?',
      body:
          'This removes locally saved embedded album covers. Your Drive files stay untouched, and covers can be regenerated by scanning metadata again.',
      confirmText: 'CLEAR',
    );

    if (!confirmed) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final coverDir = Directory('${dir.path}/musix_embedded_covers');
      if (await coverDir.exists()) {
        await coverDir.delete(recursive: true);
      }

      for (final album in _albums) {
        if (_isLocalCover(album['cover'])) {
          album['cover'] = '';
        }
        album.remove(_embeddedCoverScanFingerprintKey);
        final albumId = album['id'] ?? '';
        if (albumId.isNotEmpty) {
          _libraryBrain[albumId]?.remove(_embeddedCoverScanFingerprintKey);
          for (final record in _libraryTrackIndex.values) {
            if ((record['albumId'] ?? '') == albumId &&
                _isLocalCover(record['albumCover'])) {
              record['albumCover'] = '';
            }
          }
        }
      }
      _failedCoverSources.clear();
      await _saveFailedCoverSources();

      await _persistAlbums();
      await _saveLibraryBrain();
      await _saveLibraryTrackIndex();
      _invalidateHomeBrowseCache();
      _invalidateLibraryBrowseCache();
      if (mounted) setState(() {});
      _showSuccess('Cover cache cleared.');
    } catch (e) {
      _showError('Could not clear cover cache: $e');
    }
  }

  Future<void> _removeCurrentAlbumFromLibrary() async {
    final album = _viewingAlbum;
    if (album == null) return;

    final confirmed = await _confirmDangerAction(
      title: 'Remove album from Infame?',
      body:
          'This only removes the album from the app library cache. It does not delete the folder or songs from Google Drive.',
      confirmText: 'REMOVE',
    );

    if (!confirmed) return;

    await _backupLibraryCache();
    final id = album['id'];

    setState(() {
      _albums.removeWhere((a) => a['id'] == id);
      if (id != null) _libraryBrain.remove(id);
      _playHistory.removeWhere((item) => item['albumId'] == id);
      _viewingAlbum = null;
      _albumTracks = [];
      _currentDynamicColors = List<Color>.from(_defaultDynamicColors);
    });

    await _persistAlbums();
    await _saveLibraryBrain();
    await _savePlayHistory();
    _showSuccess('Album removed from app library. Drive files are untouched.');
  }

  Future<String?> _findEmbeddedCoverForAlbum(Map<String, String> album) async {
    final tracks = _tracksForAlbumArtwork(album);

    for (final track in tracks) {
      final cached = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      final cover = cached?.coverPath ?? '';
      if (cover.isNotEmpty) return cover;
    }

    if (_user == null || tracks.isEmpty) return null;

    try {
      final authHeaders = await _user!.authHeaders;
      final bearer =
          authHeaders['Authorization'] ?? authHeaders['authorization'] ?? '';
      if (!bearer.startsWith('Bearer ')) return null;
      final token = bearer.substring(7);

      for (final track in tracks.take(8)) {
        final result = await FastTagReader.read(file: track, token: token);
        final bytes = result?.coverBytes;
        if (bytes == null || bytes.isEmpty) continue;

        final saved = await _saveEmbeddedCover(track, bytes);
        if (saved == null || saved.isEmpty) continue;

        _applyEmbeddedCoverToAlbum(track, saved, albumRecord: album);
        return saved;
      }
    } catch (_) {}

    return null;
  }

  List<drive.File> _tracksForAlbumArtwork(Map<String, String> album) {
    final albumId = _albumCacheKey(album, source: 'album_artwork_tracks');
    final cachedTracks = _albumTracksCache[albumId];
    if (cachedTracks != null && cachedTracks.isNotEmpty) {
      return _sortTracksForAlbum(cachedTracks);
    }

    if (_viewingAlbum != null &&
        _albumCacheKey(_viewingAlbum!, source: 'album_artwork_tracks_view') ==
            albumId) {
      if (_albumTracks.isNotEmpty) return _sortTracksForAlbum(_albumTracks);
    }

    return const <drive.File>[];
  }

  String _albumArtworkLookupKey(Map<String, String> album) {
    final id = _albumCacheKey(album, source: 'album_artwork_key');
    if (id.isNotEmpty) return id;
    final title = _albumTitleForArtwork(album);
    final artist = _albumArtistForArtwork(album);
    return _safeArtworkFileName('$artist::$title');
  }

  String _albumArtworkLookupQuery(
    Map<String, String> album, {
    String? title,
    String? artist,
    String? year,
  }) {
    final albumName = (title ?? _albumTitleForArtwork(album)).trim();
    final artistName = (artist ?? _albumArtistForArtwork(album)).trim();
    final albumYear = (year ?? _albumYearForArtwork(album)).trim();
    final parts = <String>[
      if (artistName.isNotEmpty && artistName != 'Unknown Artist') artistName,
      if (albumName.isNotEmpty) albumName,
      if (albumYear.isNotEmpty) albumYear,
      'album cover',
    ];
    return parts.join(' ').trim();
  }

  bool _albumArtworkMatchesCandidate({
    required String albumName,
    required String artistName,
    required _ArtworkCandidate candidate,
  }) {
    final wantedAlbum = _normalizeArtworkMatch(albumName);
    final wantedArtist = _normalizeArtworkMatch(artistName);
    final candAlbum = _normalizeArtworkMatch(candidate.title);
    final candArtist = _normalizeArtworkMatch(candidate.artist);

    if (wantedAlbum.isEmpty || candAlbum.isEmpty) return false;
    final albumMatch = wantedAlbum == candAlbum ||
        candAlbum.contains(wantedAlbum) ||
        wantedAlbum.contains(candAlbum);
    if (!albumMatch) return false;

    if (wantedArtist.isNotEmpty && wantedArtist != 'unknown artist') {
      if (candArtist.isEmpty) return false;
      final artistMatch = wantedArtist == candArtist ||
          candArtist.contains(wantedArtist) ||
          wantedArtist.contains(candArtist);
      if (!artistMatch) return false;
    }

    return candidate.confidence >= 0.72;
  }

  Future<_ArtworkCandidate?> _fetchCoverArtCandidate(
    Map<String, String> album, {
    String? title,
    String? artist,
    String? year,
  }) async {
    final albumName = (title ?? _albumTitleForArtwork(album)).trim();
    final artistName = (artist ?? _albumArtistForArtwork(album)).trim();
    final albumYear = (year ?? _albumYearForArtwork(album)).trim();
    if (albumName.isEmpty) return null;

    final candidates = <_ArtworkCandidate>[];
    try {
      candidates.addAll(
        await _searchTheAudioDbArtworkCandidates(
            albumName, artistName, albumYear),
      );
    } catch (_) {}
    try {
      candidates.addAll(
        await _searchITunesArtworkCandidates(albumName, artistName, albumYear),
      );
    } catch (_) {}
    try {
      candidates.addAll(
        await _searchMusicBrainzArtworkCandidates(
          albumName,
          artistName,
          albumYear,
        ),
      );
    } catch (_) {}

    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    for (final candidate in candidates) {
      if (_albumArtworkMatchesCandidate(
        albumName: albumName,
        artistName: artistName,
        candidate: candidate,
      )) {
        return candidate;
      }
    }

    return null;
  }

  Future<void> _findCoversForAllAlbums() async {
    if (_user == null || _albums.isEmpty) {
      _showError('Please sign in first.');
      return;
    }

    _showSuccess('Starting cover search for ${_albums.length} albums...');
    int found = 0;
    int failed = 0;
    final usedRemoteUrls = <String, String>{};
    final coverUsage = <String, Set<String>>{};
    for (final existingAlbum in _albums) {
      final existingCover = _albumCoverForIndex(existingAlbum).trim();
      if (existingCover.isEmpty) continue;
      final signature =
          '${_normalizeArtworkMatch(_albumTitleForArtwork(existingAlbum))}::${_normalizeArtworkMatch(_albumArtistForArtwork(existingAlbum))}';
      coverUsage.putIfAbsent(existingCover, () => <String>{}).add(signature);
    }
    final suspiciousCovers = coverUsage.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => entry.key)
        .toSet();

    for (final album in _albums) {
      final albumName = _albumTitleForArtwork(album);
      final artist = _albumArtistForArtwork(album);
      final year = _albumYearForArtwork(album);
      final albumKey = _albumArtworkLookupKey(album);
      final query = _albumArtworkLookupQuery(
        album,
        title: albumName,
        artist: artist,
        year: year,
      );

      _verboseScanLog('Cover lookup albumKey=$albumKey');
      _verboseScanLog('Cover lookup query=$query');

      final existingCover = _albumCoverForIndex(album).trim();
      if (existingCover.isNotEmpty &&
          !suspiciousCovers.contains(existingCover)) {
        _verboseScanLog('Cover skipped album=$albumKey reason=existing_cover');
        continue;
      } else if (existingCover.isNotEmpty) {
        _verboseScanLog(
            'Cover lookup albumKey=$albumKey reason=suspicious_existing_cover');
      }

      final embedded = await _findEmbeddedCoverForAlbum(album);
      if (embedded != null && embedded.isNotEmpty) {
        album['cover'] = embedded;
        found++;
        _verboseScanLog(
            'Cover accepted album=$albumKey url=$embedded source=embedded');
        await _extractAlbumColors(embedded, albumName);
        continue;
      }

      final candidate = await _fetchCoverArtCandidate(
        album,
        title: albumName,
        artist: artist,
        year: year,
      );
      if (candidate != null && candidate.imageUrl.isNotEmpty) {
        final remoteUrl = candidate.imageUrl;
        final normalizedAlbum =
            '${_normalizeArtworkMatch(albumName)}::${_normalizeArtworkMatch(artist)}';
        final existingAlbum = usedRemoteUrls[remoteUrl];
        if (existingAlbum != null && existingAlbum != normalizedAlbum) {
          _verboseScanLog(
              'Cover rejected album=$albumKey reason=duplicate_remote_url');
          failed++;
          continue;
        }
        usedRemoteUrls[remoteUrl] = normalizedAlbum;
        album['cover'] = remoteUrl;
        found++;
        _verboseScanLog(
            'Cover accepted album=$albumKey url=$remoteUrl source=${candidate.source}');
        await _extractAlbumColors(remoteUrl, albumName);
      } else {
        _verboseScanLog(
            'Cover skipped album=$albumKey reason=no_confident_match');
        failed++;
      }
    }

    await _persistAlbums();
    _showSuccess('Cover search complete: $found found, $failed failed.');
  }

  String _albumTitleForArtwork(Map<String, String> album) {
    return _resolvedAlbumTitle(album);
  }

  String _albumArtistForArtwork(Map<String, String> album) {
    return _resolvedAlbumArtist(album);
  }

  String _albumYearForArtwork(Map<String, String> album) {
    final id = _albumCacheKey(album, source: 'album_artwork_year');
    final brain = _libraryBrain[id] ?? const <String, String>{};
    return (brain['year'] ?? album['year'] ?? '').trim();
  }

  Future<List<_ArtworkCandidate>> _searchITunesArtworkCandidates(
    String albumName,
    String artistName,
    String year,
  ) async {
    final cleanAlbum = _cleanCoverSearchTerm(albumName);
    final cleanArtist = _coverSearchAlias(_cleanCoverSearchTerm(artistName));
    final term = [cleanArtist, cleanAlbum]
        .where((v) => v.trim().isNotEmpty && v != 'Unknown Artist')
        .join(' ');
    if (term.trim().isEmpty) return const <_ArtworkCandidate>[];

    final url = Uri.parse(
      'https://itunes.apple.com/search?term=${Uri.encodeComponent(term)}&entity=album&limit=18',
    );
    final res = await http.get(url, headers: {'User-Agent': 'InfameApp/1.0'});
    if (res.statusCode != 200) return const <_ArtworkCandidate>[];

    final data = json.decode(res.body);
    final results = data['results'];
    if (results is! List) return const <_ArtworkCandidate>[];

    final candidates = <_ArtworkCandidate>[];
    for (final item in results) {
      if (item is! Map) continue;
      final artwork = item['artworkUrl100'];
      if (artwork is! String || artwork.isEmpty) continue;
      final title = (item['collectionName'] ?? '').toString();
      final artist = (item['artistName'] ?? '').toString();
      final releaseDate = (item['releaseDate'] ?? '').toString();
      final full = artwork
          .replaceAll('100x100bb.jpg', '1200x1200bb.jpg')
          .replaceAll('100x100bb.png', '1200x1200bb.png');
      candidates.add(
        _ArtworkCandidate(
          source: 'iTunes',
          title: title.isEmpty ? albumName : title,
          artist: artist.isEmpty ? artistName : artist,
          year: releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '',
          imageUrl: full,
          thumbnailUrl: artwork,
          confidence: _artworkConfidence(
            wantedAlbum: albumName,
            wantedArtist: artistName,
            wantedYear: year,
            candidateAlbum: title,
            candidateArtist: artist,
            candidateYear: releaseDate,
          ),
        ),
      );
    }
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    return candidates.take(12).toList();
  }

  Future<List<_ArtworkCandidate>> _searchTheAudioDbArtworkCandidates(
    String albumName,
    String artistName,
    String year,
  ) async {
    final cleanAlbum = _cleanCoverSearchTerm(albumName);
    final cleanArtist = _coverSearchAlias(_cleanCoverSearchTerm(artistName));
    if (cleanAlbum.isEmpty ||
        cleanArtist.isEmpty ||
        cleanArtist == 'Unknown Artist') {
      return const <_ArtworkCandidate>[];
    }

    final url = Uri.parse(
      'https://www.theaudiodb.com/api/v1/json/2/searchalbum.php?s=${Uri.encodeComponent(cleanArtist)}&a=${Uri.encodeComponent(cleanAlbum)}',
    );
    final res = await http.get(url, headers: {'User-Agent': 'InfameApp/1.0'});
    if (res.statusCode != 200) return const <_ArtworkCandidate>[];

    final data = json.decode(res.body);
    final albums = data['album'];
    if (albums is! List) return const <_ArtworkCandidate>[];

    final candidates = <_ArtworkCandidate>[];
    for (final item in albums) {
      if (item is! Map) continue;
      final image =
          (item['strAlbumThumb'] ?? item['strAlbumCDart'] ?? '').toString();
      if (image.isEmpty) continue;
      final title = (item['strAlbum'] ?? '').toString();
      final artist = (item['strArtist'] ?? '').toString();
      final released = (item['intYearReleased'] ?? '').toString();
      candidates.add(
        _ArtworkCandidate(
          source: 'TheAudioDB',
          title: title.isEmpty ? albumName : title,
          artist: artist.isEmpty ? artistName : artist,
          year: released,
          imageUrl: image,
          thumbnailUrl: image,
          confidence: _artworkConfidence(
            wantedAlbum: albumName,
            wantedArtist: artistName,
            wantedYear: year,
            candidateAlbum: title,
            candidateArtist: artist,
            candidateYear: released,
          ),
        ),
      );
    }
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    return candidates.take(12).toList();
  }

  Future<List<_ArtworkCandidate>> _searchMusicBrainzArtworkCandidates(
    String albumName,
    String artistName,
    String year,
  ) async {
    final cleanAlbum = _cleanCoverSearchTerm(albumName);
    final cleanArtist = _coverSearchAlias(_cleanCoverSearchTerm(artistName));
    final queries = <String>[
      if (cleanArtist.isNotEmpty && cleanArtist != 'Unknown Artist')
        'releasegroup:"$cleanAlbum" AND artist:"$cleanArtist"',
      if (cleanArtist.isNotEmpty && cleanArtist != 'Unknown Artist')
        '$cleanAlbum $cleanArtist',
      cleanAlbum,
    ];
    final candidates = <_ArtworkCandidate>[];
    final seen = <String>{};

    for (final query in queries) {
      if (query.trim().isEmpty || seen.contains(query)) continue;
      seen.add(query);
      final mbUrl = Uri.parse(
        'https://musicbrainz.org/ws/2/release-group/?query=${Uri.encodeComponent(query)}&fmt=json&limit=10',
      );
      final mbRes = await http.get(
        mbUrl,
        headers: {'User-Agent': 'InfameApp/1.0 (artwork source picker)'},
      );
      if (mbRes.statusCode != 200) continue;

      final data = json.decode(mbRes.body);
      final groups = data['release-groups'];
      if (groups is! List) continue;

      for (final group in groups.take(8)) {
        if (group is! Map) continue;
        final mbid = (group['id'] ?? '').toString();
        if (mbid.isEmpty) continue;
        final title = (group['title'] ?? '').toString();
        final firstDate = (group['first-release-date'] ?? '').toString();
        var artist = artistName;
        final credits = group['artist-credit'];
        if (credits is List && credits.isNotEmpty && credits.first is Map) {
          artist = ((credits.first as Map)['name'] ?? artistName).toString();
        }

        // Keep MusicBrainz gentle; this is only run after the user taps the source.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final caaUrl =
            Uri.parse('https://coverartarchive.org/release-group/$mbid');
        final caaRes =
            await http.get(caaUrl, headers: {'Accept': 'application/json'});
        if (caaRes.statusCode != 200) continue;

        final caaData = json.decode(caaRes.body);
        final images = caaData['images'];
        if (images is! List || images.isEmpty) continue;
        for (final img in images.take(3)) {
          if (img is! Map) continue;
          if (img['front'] != true && candidates.isNotEmpty) continue;
          final thumbnails = img['thumbnails'];
          final full = (img['image'] ?? '').toString();
          final thumb = thumbnails is Map
              ? (thumbnails['500'] ??
                      thumbnails['250'] ??
                      thumbnails['small'] ??
                      full)
                  .toString()
              : full;
          if (full.isEmpty) continue;
          candidates.add(
            _ArtworkCandidate(
              source: 'MusicBrainz',
              title: title.isEmpty ? albumName : title,
              artist: artist.isEmpty ? artistName : artist,
              year: firstDate.length >= 4 ? firstDate.substring(0, 4) : '',
              imageUrl: full,
              thumbnailUrl: thumb.isEmpty ? full : thumb,
              confidence: _artworkConfidence(
                wantedAlbum: albumName,
                wantedArtist: artistName,
                wantedYear: year,
                candidateAlbum: title,
                candidateArtist: artist,
                candidateYear: firstDate,
              ),
            ),
          );
          break;
        }
      }
      if (candidates.isNotEmpty) break;
    }

    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    return candidates.take(12).toList();
  }

  Future<String?> _downloadArtworkToLocalCache(
    Map<String, String> album,
    _ArtworkCandidate candidate,
  ) async {
    final res = await http.get(Uri.parse(candidate.imageUrl),
        headers: {'User-Agent': 'InfameApp/1.0'});
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    final type = res.headers['content-type']?.toLowerCase() ?? '';
    if (type.isNotEmpty && !type.startsWith('image/')) return null;
    if (res.bodyBytes.length > 12 * 1024 * 1024) return null;

    final dir = await getApplicationSupportDirectory();
    final artworkDir = Directory('${dir.path}/infame/artwork');
    if (!await artworkDir.exists()) await artworkDir.create(recursive: true);
    final key = _safeArtworkFileName(_albumStableKey(album));
    final source = _safeArtworkFileName(candidate.source);
    final ext = _imageExtensionFromHeaders(res, candidate.imageUrl);
    final path = '${artworkDir.path}/${key}_$source$ext';
    final file = File(path);
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return path;
  }

  Future<void> _applyArtworkOverrideToAlbum(
    Map<String, String> album,
    String coverPath, {
    String source = 'Custom',
    String remoteUrl = '',
  }) async {
    final albumId = album['id'] ?? '';
    final currentCover = _albumCoverForIndex(album);
    if ((album['driveCover'] ?? '').isEmpty &&
        currentCover.isNotEmpty &&
        currentCover != coverPath) {
      album['driveCover'] = currentCover;
    }

    void apply(Map<String, String> target) {
      if ((target['driveCover'] ?? '').isEmpty &&
          currentCover.isNotEmpty &&
          currentCover != coverPath) {
        target['driveCover'] = currentCover;
      }
      target['cover'] = coverPath;
      target['customCoverUrl'] = coverPath;
      target['artworkSource'] = source;
      if (remoteUrl.isNotEmpty) target['artworkRemoteUrl'] = remoteUrl;
      target['artworkUpdatedAt'] =
          DateTime.now().millisecondsSinceEpoch.toString();
    }

    apply(album);
    for (final savedAlbum in _albums) {
      if ((savedAlbum['id'] ?? '') == albumId) {
        apply(savedAlbum);
        break;
      }
    }
    if (_viewingAlbum != null && (_viewingAlbum!['id'] ?? '') == albumId) {
      apply(_viewingAlbum!);
    }

    final brain = _libraryBrain[albumId];
    if (brain != null) {
      brain['cover'] = coverPath;
      await _saveLibraryBrain();
    }

    for (final record in _libraryTrackIndex.values) {
      if ((record['albumId'] ?? '') == albumId) {
        record['albumCover'] = coverPath;
      }
    }

    if (albumId.isNotEmpty && _currentPlayingAlbumId() == albumId) {
      _nowPlaying.currentCoverUrl = coverPath;
      _nowPlaying.refresh();
    }

    _librarySearchTextCache.clear();
    await _persistAlbums();
    await _saveLibraryTrackIndex();
    await _extractAlbumColors(coverPath, _albumTitleForArtwork(album));
    _invalidateHomeBrowseCache();
    _invalidateLibraryBrowseCache();
    if (mounted) setState(() {});
  }

  Future<void> _revertAlbumArtwork(Map<String, String> album) async {
    final albumId = _albumCacheKey(album, source: 'revert_artwork');
    final fallback = album['driveCover'] ??
        album['coverUrl'] ??
        album['thumbnailLink'] ??
        album['artwork'] ??
        '';

    void revert(Map<String, String> target) {
      target.remove('customCoverUrl');
      target.remove('artworkSource');
      target.remove('artworkRemoteUrl');
      target.remove('artworkUpdatedAt');
      target['cover'] = fallback;
    }

    revert(album);
    for (final savedAlbum in _albums) {
      if (_albumCacheKey(savedAlbum, source: 'revert_artwork_saved') ==
              albumId ||
          (savedAlbum['id'] ?? '') == albumId) {
        revert(savedAlbum);
        break;
      }
    }
    if (_viewingAlbum != null &&
        (_albumCacheKey(_viewingAlbum!, source: 'revert_artwork_view') ==
                albumId ||
            (_viewingAlbum!['id'] ?? '') == albumId)) {
      revert(_viewingAlbum!);
    }

    final brain = _libraryBrain[albumId];
    if (brain != null) {
      brain['cover'] = fallback;
      await _saveLibraryBrain();
    }
    for (final record in _libraryTrackIndex.values) {
      if ((record['albumId'] ?? '') == albumId) {
        record['albumCover'] = fallback;
      }
    }
    _librarySearchTextCache.clear();
    await _persistAlbums();
    await _saveLibraryTrackIndex();
    _invalidateHomeBrowseCache();
    _invalidateLibraryBrowseCache();
    if (mounted) setState(() {});
  }

  Future<List<_ArtworkCandidate>> _searchArtworkSource(
    String source,
    String albumName,
    String artistName,
    String year,
  ) async {
    switch (source) {
      case 'itunes':
        return _searchITunesArtworkCandidates(albumName, artistName, year);
      case 'audiodb':
        return _searchTheAudioDbArtworkCandidates(albumName, artistName, year);
      case 'musicbrainz':
        return _searchMusicBrainzArtworkCandidates(albumName, artistName, year);
      default:
        return const <_ArtworkCandidate>[];
    }
  }

  Future<void> _showArtworkSourcePicker() async {
    final album = _viewingAlbum;
    if (album == null) return;

    final albumName = _albumTitleForArtwork(album);
    final artistName = _albumArtistForArtwork(album);
    final year = _albumYearForArtwork(album);
    final currentCover = _albumCoverForIndex(album);
    final glowColor = _isDarkMode ? _neonPurple : _neonMagenta;
    var candidates = <_ArtworkCandidate>[];
    var loading = false;
    var status = 'Choose a source to search artwork.';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            Future<void> runSource(String source) async {
              sheetSetState(() {
                loading = true;
                candidates = <_ArtworkCandidate>[];
                status = 'Searching artwork...';
              });
              try {
                final results = await _searchArtworkSource(
                    source, albumName, artistName, year);
                sheetSetState(() {
                  candidates = results;
                  status = results.isEmpty
                      ? 'No artwork found for this source.'
                      : 'Tap the correct cover to save it locally.';
                });
              } catch (e) {
                sheetSetState(() => status = 'Could not search artwork: $e');
              } finally {
                sheetSetState(() => loading = false);
              }
            }

            Future<void> pickCandidate(_ArtworkCandidate candidate) async {
              sheetSetState(() {
                loading = true;
                status = 'Saving artwork locally...';
              });
              try {
                final localPath =
                    await _downloadArtworkToLocalCache(album, candidate);
                if (localPath == null || localPath.isEmpty) {
                  sheetSetState(() => status = 'Could not download artwork.');
                  return;
                }
                await _applyArtworkOverrideToAlbum(
                  album,
                  localPath,
                  source: candidate.source,
                  remoteUrl: candidate.imageUrl,
                );
                if (mounted) Navigator.of(sheetContext).pop();
                _showSuccess('Artwork updated.');
              } catch (e) {
                sheetSetState(() => status = 'Could not save artwork: $e');
              } finally {
                sheetSetState(() => loading = false);
              }
            }

            Widget sourceButton(
                String label, IconData icon, VoidCallback onTap) {
              return Expanded(
                child: PressableScale(
                  onTap: loading ? null : onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 10),
                    decoration: BoxDecoration(
                      color: (_isDarkMode
                          ? Colors.white.withOpacity(0.08)
                          : Colors.white),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: glowColor.withOpacity(0.35)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: glowColor, size: 20),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                              color: _textPri,
                              fontWeight: FontWeight.w800,
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Container(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88),
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 14,
                bottom: MediaQuery.of(context).padding.bottom + 18,
              ),
              decoration: BoxDecoration(
                color: _isDarkMode
                    ? const Color(0xFF121018)
                    : const Color(0xFFFFFBFF),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: glowColor.withOpacity(0.28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _textSub.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Choose Artwork Source',
                      style: GoogleFonts.inter(
                          color: _textPri,
                          fontSize: 22,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('$artistName • $albumName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          color: _textSub, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (currentCover.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(kArtworkRadius),
                          child: SizedBox(
                              width: 58,
                              height: 58,
                              child: _coverImage(currentCover, cacheSize: 160)),
                        )
                      else
                        Container(
                            width: 58,
                            height: 58,
                            color: glowColor.withOpacity(0.14),
                            child: Icon(Icons.album_rounded, color: glowColor)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          status,
                          style: GoogleFonts.inter(
                              color: _textSub, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      sourceButton('iTunes', Icons.music_note_rounded,
                          () => runSource('itunes')),
                      const SizedBox(width: 10),
                      sourceButton('TheAudioDB', Icons.storage_rounded,
                          () => runSource('audiodb')),
                      const SizedBox(width: 10),
                      sourceButton('MusicBrainz', Icons.public_rounded,
                          () => runSource('musicbrainz')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      sourceButton('Current', Icons.image_rounded, () async {
                        await _revertAlbumArtwork(album);
                        if (mounted) Navigator.of(sheetContext).pop();
                        _showSuccess('Using current cover.');
                      }),
                      const SizedBox(width: 10),
                      sourceButton('Revert', Icons.undo_rounded, () async {
                        await _revertAlbumArtwork(album);
                        if (mounted) Navigator.of(sheetContext).pop();
                        _showSuccess('Artwork reverted.');
                      }),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (loading)
                    LinearProgressIndicator(
                        color: glowColor,
                        backgroundColor: glowColor.withOpacity(0.12)),
                  if (!loading && candidates.isNotEmpty)
                    Flexible(
                      child: GridView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(top: 10),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final candidate = candidates[index];
                          return GestureDetector(
                            onTap: () => pickCandidate(candidate),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(kArtworkRadius),
                                    child: Container(
                                      color: glowColor.withOpacity(0.10),
                                      child: _coverImage(
                                        candidate.thumbnailUrl.isNotEmpty
                                            ? candidate.thumbnailUrl
                                            : candidate.imageUrl,
                                        cacheSize: 260,
                                        errorBuilder: (_, __, ___) => Center(
                                            child: Icon(
                                                Icons.broken_image_rounded,
                                                color: glowColor)),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  candidate.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      color: _textPri,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11),
                                ),
                                Text(
                                  [
                                    candidate.source,
                                    if (candidate.year.isNotEmpty)
                                      candidate.year
                                  ].join(' • '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      color: _textSub,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _refreshCurrentAlbumCover() async {
    final album = _viewingAlbum;
    if (album == null) return;

    final normalized = _resolvedAlbumMap(album);
    final albumId = normalized['id'] ?? '';
    final brain = _libraryBrain[albumId] ?? const <String, String>{};
    final albumName =
        normalized['displayName'] ?? normalized['name'] ?? 'Unknown Album';
    final artist = normalized['artist'] ?? 'Unknown Artist';

    _showSuccess('Checking embedded cover first...');

    final embedded = await _findEmbeddedCoverForAlbum(album);
    if (embedded != null && embedded.isNotEmpty) {
      setState(() {
        album['cover'] = embedded;
        for (final savedAlbum in _albums) {
          if (_albumCacheKey(savedAlbum, source: 'show_artwork_saved') ==
                  albumId ||
              savedAlbum['id'] == album['id']) {
            savedAlbum['cover'] = embedded;
            break;
          }
        }
      });
      await _persistAlbums();
      await _extractAlbumColors(embedded, albumName);
      _showSuccess('Embedded album cover restored.');
      return;
    }

    _showSuccess('Searching Cover Art Archive...');
    final fetched = await _fetchCoverArt(albumName, artist);
    if (fetched == null || fetched.isEmpty) {
      _showError(
          'No cover found. Embedded art was missing and online lookup failed.');
      return;
    }

    setState(() {
      album['cover'] = fetched;
      for (final savedAlbum in _albums) {
        if (_albumCacheKey(savedAlbum, source: 'show_artwork_saved') ==
                albumId ||
            savedAlbum['id'] == album['id']) {
          savedAlbum['cover'] = fetched;
          break;
        }
      }
    });

    await _persistAlbums();
    await _extractAlbumColors(fetched, albumName);
    _showSuccess('Album cover refreshed.');
  }

  Future<void> _shuffleLibrary() async {
    if (_user == null || _albums.isEmpty) return;

    try {
      final authHeaders = await _user!.authHeaders;
      final api = drive.DriveApi(GoogleAuthClient(authHeaders));
      final random = math.Random();
      final albums = List<Map<String, String>>.from(_albums)..shuffle(random);

      for (final album in albums) {
        final tracks = await _fetchTracksForAlbumRecord(api, album);
        if (tracks.isEmpty) continue;

        final trackIndex = random.nextInt(tracks.length);
        final coverUrl = album['cover'];
        final colors = coverUrl != null && coverUrl.isNotEmpty
            ? getAlbumGradient(album['name'] ?? '')
            : getAlbumGradient(album['name'] ?? '');

        await _playSong(
          tracks[trackIndex],
          queue: tracks,
          idx: trackIndex,
          coverUrl: coverUrl,
          colors: colors,
        );
        return;
      }

      _showError('No playable tracks found in your library.');
    } catch (e) {
      _showError('Could not shuffle library: $e');
    }
  }

  Future<void> _clearLibrary() async {
    await _clearLibraryCacheSafely();
  }

  void _showSuccess(String msg) => _showSuccessFromPart(msg);

  // ── Cover Art Fetcher ─────────────────────────────────────────────────────
  // ── Cover Art Fetcher ─────────────────────────────────────────────────────
  String _coverSearchAlias(String value) {
    final cleaned = value.trim();
    final lower = cleaned.toLowerCase();
    if (lower == 'clips') return 'Clipse';
    if (lower == r'a$ap rocky' || lower == 'asap rocky') return r'A$AP Rocky';
    if (lower == 'mf doom' || lower == 'madvillain') return cleaned;
    return cleaned;
  }

  String _cleanCoverSearchTerm(String value) {
    var cleaned = value
        .replaceAll(RegExp(r'\[.*?\]|\(.*?\)'), '')
        .replaceAll(RegExp(r'\b(19|20)\d{2}\b'), '')
        .replaceAll(
            RegExp(
                r'\b(deluxe|expanded|explicit|clean|remaster(ed)?|anniversary|edition|version)\b',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? value.trim() : cleaned;
  }

  Future<String?> _coverFromCoverArtArchive(
      String albumName, String artistName) async {
    final cleanAlbum = _cleanCoverSearchTerm(albumName);
    final cleanArtist = _coverSearchAlias(_cleanCoverSearchTerm(artistName));

    final queries = <String>[
      if (cleanArtist.isNotEmpty && cleanArtist != 'Unknown Artist')
        'releasegroup:"$cleanAlbum" AND artist:"$cleanArtist"',
      if (cleanArtist.isNotEmpty && cleanArtist != 'Unknown Artist')
        '$cleanAlbum $cleanArtist',
      cleanAlbum,
    ];

    final seen = <String>{};

    for (final query in queries) {
      if (query.trim().isEmpty || seen.contains(query)) continue;
      seen.add(query);

      final mbUrl = Uri.parse(
        'https://musicbrainz.org/ws/2/release-group/?query=${Uri.encodeComponent(query)}&fmt=json&limit=8',
      );

      final mbRes = await http.get(
        mbUrl,
        headers: {'User-Agent': 'InfameApp/1.0 (cover lookup)'},
      );

      if (mbRes.statusCode != 200) continue;

      final data = json.decode(mbRes.body);
      final groups = data['release-groups'];
      if (groups is! List || groups.isEmpty) continue;

      for (final group in groups.take(6)) {
        final mbid = group['id'];
        if (mbid == null) continue;

        final caaUrl =
            Uri.parse('https://coverartarchive.org/release-group/$mbid');
        final caaRes =
            await http.get(caaUrl, headers: {'Accept': 'application/json'});
        if (caaRes.statusCode != 200) continue;

        final caaData = json.decode(caaRes.body);
        final images = caaData['images'];
        if (images is! List || images.isEmpty) continue;

        final front = images.cast<dynamic>().firstWhere(
              (img) => img is Map && img['front'] == true,
              orElse: () => images.first,
            );
        if (front is Map) {
          final thumbnails = front['thumbnails'];
          final image = thumbnails is Map
              ? (thumbnails['large'] ??
                  thumbnails['500'] ??
                  thumbnails['250'] ??
                  front['image'])
              : front['image'];
          if (image is String && image.isNotEmpty) return image;
        }
      }
    }

    return null;
  }

  Future<String?> _coverFromITunes(String albumName, String artistName) async {
    final cleanAlbum = _cleanCoverSearchTerm(albumName);
    final cleanArtist = _coverSearchAlias(_cleanCoverSearchTerm(artistName));
    final term = [cleanArtist, cleanAlbum]
        .where((v) => v.trim().isNotEmpty && v != 'Unknown Artist')
        .join(' ');
    if (term.trim().isEmpty) return null;

    final url = Uri.parse(
      'https://itunes.apple.com/search?term=${Uri.encodeComponent(term)}&entity=album&limit=10',
    );

    final res = await http.get(url, headers: {'User-Agent': 'InfameApp/1.0'});
    if (res.statusCode != 200) return null;

    final data = json.decode(res.body);
    final results = data['results'];
    if (results is! List || results.isEmpty) return null;

    for (final item in results) {
      if (item is! Map) continue;
      final artwork = item['artworkUrl100'];
      if (artwork is String && artwork.isNotEmpty) {
        return artwork
            .replaceAll('100x100bb.jpg', '1200x1200bb.jpg')
            .replaceAll('100x100bb.png', '1200x1200bb.png');
      }
    }
    return null;
  }

  Future<String?> _fetchCoverArt(String albumName, String artistName) async {
    try {
      final candidate = await _fetchCoverArtCandidate(
        <String, String>{'name': albumName, 'artist': artistName},
        title: albumName,
        artist: artistName,
      );
      if (candidate != null && candidate.imageUrl.isNotEmpty) {
        return candidate.imageUrl;
      }
    } catch (_) {}

    return null;
  }

  // ── Library Scanner ────────────────────────────────────────────────────────
  Future<void> _scanFolderToLibrary(drive.File rootFolder) async {
    if (_user == null || DriveUtils.effectiveId(rootFolder) == null) return;

    debugPrint('scan started');
    debugPrint('[DriveScan] scan started for folder: ${rootFolder.name}');
    setState(() => _isScanning = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Scanning Drive and building album covers...',
          style: GoogleFonts.inter(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: _pink,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );

    try {
      final headers = await _user!.authHeaders;
      final api = drive.DriveApi(GoogleAuthClient(headers));

      final Map<String, Map<String, String>> discoveredMap = {};

      await _crawlDirectory(
        api,
        DriveUtils.effectiveId(rootFolder)!,
        rootFolder.name ?? 'Unknown',
        discoveredMap,
      );

      final discovered = discoveredMap.values.toList();

      if (!mounted) return;

      if (discovered.isEmpty) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No audio files found.',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final uniqueAlbums = <String, Map<String, String>>{};
      for (final a in _albums) {
        uniqueAlbums[a['id']!] = a;
      }
      for (final a in discovered) {
        final id = a['id']!;
        final existing = uniqueAlbums[id];
        if (existing != null) {
          a['dateAdded'] = existing['dateAdded'] ??
              a['dateAdded'] ??
              DateTime.now().millisecondsSinceEpoch.toString();
          if ((a['cover'] ?? '').isEmpty &&
              (existing['cover'] ?? '').isNotEmpty) {
            a['cover'] = existing['cover']!;
          }
        }
        uniqueAlbums[id] = a;
      }

      setState(() {
        _albums = uniqueAlbums.values.toList()
          ..forEach((album) {
            final normalizedId = _albumCacheKey(album, source: 'scan_album');
            if (normalizedId.isNotEmpty) {
              album['id'] = normalizedId;
              album['albumKey'] = normalizedId;
            }
          })
          ..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
        _librarySearchTextCache.clear();
        _shuffledExploreAlbums = (List<Map<String, String>>.from(_albums)
              ..shuffle())
            .take(14)
            .toList();
        _albumTracksCache.clear();
        _isScanning = false;
      });

      _buildBasicLibraryBrain(save: false);
      await _persistAlbums();
      await _saveLibraryBrain();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Scan complete! Found ${discovered.length} albums.',
            style: GoogleFonts.inter(
                color: Colors.black, fontWeight: FontWeight.w800),
          ),
          backgroundColor: _accentDefault,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (e.toString().contains('401')) {
        _showError('Session expired. Sign out and sign back in.');
      } else {
        _showError('Scan failed: $e');
      }

      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _crawlDirectory(
    drive.DriveApi api,
    String folderId,
    String folderName,
    Map<String, Map<String, String>> discovered,
  ) async {
    String? pageToken;
    bool containsAudio = false;
    String? localCoverUrl;
    String? firstArtistFound;
    final List<drive.File> subFolders = [];

    do {
      final res = await api.files.list(
        q: "'$folderId' in parents and trashed = false",
        $fields:
            'files(id,name,mimeType,thumbnailLink,shortcutDetails(targetId,targetMimeType)),nextPageToken',
        pageSize: 100,
        pageToken: pageToken,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );

      final files = res.files ?? <drive.File>[];

      for (final f in files) {
        if (DriveUtils.isAudio(f)) {
          containsAudio = true;
          firstArtistFound ??= DriveUtils.getTrackMeta(f)['artist'];
        } else if (DriveUtils.isFolder(f)) {
          subFolders.add(f);
        } else if (DriveUtils.effectiveMimeType(f)?.startsWith('image/') ==
            true) {
          localCoverUrl ??= f.thumbnailLink;
        }
      }

      pageToken = res.nextPageToken;
    } while (pageToken != null);

    if (containsAudio) {
      final baseAlbumName = folderName
          .replaceAll(
            RegExp(
              r'[\s\-\(\[\]]*(disc|cd)\.?\s*\d+[\s\-\)\[\]]*',
              caseSensitive: false,
            ),
            '',
          )
          .trim();

      String finalCover = localCoverUrl ?? '';

      if (discovered.containsKey(baseAlbumName)) {
        discovered[baseAlbumName]!['id'] =
            '${discovered[baseAlbumName]!['id']!},$folderId';

        if (discovered[baseAlbumName]!['cover']!.isEmpty &&
            finalCover.isNotEmpty) {
          discovered[baseAlbumName]!['cover'] = finalCover;
        }
      } else {
        // Do not call online cover APIs while crawling Drive. That made the
        // first library scan feel much slower, and embedded album art is the
        // preferred source anyway. The manual "Refresh cover" action still
        // uses online lookup as a fallback when needed.

        discovered[baseAlbumName] = {
          'id': folderId,
          'name': baseAlbumName.isEmpty ? folderName : baseAlbumName,
          'cover': finalCover,
          'dateAdded': DateTime.now().millisecondsSinceEpoch.toString(),
        };
      }
    }

    for (final sub in subFolders) {
      final subId = DriveUtils.effectiveId(sub);
      if (subId != null) {
        await _crawlDirectory(api, subId, sub.name ?? 'Unknown', discovered);
      }
    }
  }

  Future<void> _extractAlbumColors(
    String coverUrl,
    String albumName, {
    String? cacheKey,
  }) async {
    final fallback = getAlbumGradient(albumName);
    final key =
        cacheKey?.trim().isNotEmpty == true ? cacheKey!.trim() : albumName;

    final cached = _albumColorCache[key];
    if (cached != null && cached.length >= 4) {
      if (mounted) setState(() => _currentDynamicColors = cached);
      return;
    }

    if (coverUrl.isEmpty) {
      _albumColorCache[key] = fallback;
      _saveAlbumColorCache();
      if (mounted) setState(() => _currentDynamicColors = fallback);
      return;
    }

    if (_isBlockedCoverSource(coverUrl)) {
      _albumColorCache[key] = fallback;
      _saveAlbumColorCache();
      if (mounted) setState(() => _currentDynamicColors = fallback);
      return;
    }

    // Prevent duplicate extractions for the same cover
    if (_albumColorExtractionInProgress.contains(key)) {
      debugPrint('Palette extraction already in progress for $key, skipping');
      return;
    }

    _albumColorExtractionInProgress.add(key);

    try {
      final provider = _coverProvider(coverUrl);
      if (provider == null) throw Exception('Missing cover provider');

      // Resize image to 300x300 for faster palette extraction
      final paletteProvider = ResizeImage(
        provider,
        width: 300,
        height: 300,
      );

      final stopwatch = Stopwatch()..start();

      // Sample resized image for color extraction (much faster than full image)
      final palette = await PaletteGenerator.fromImageProvider(
        paletteProvider,
        maximumColorCount: 24,
        region: null, // Full resized image sampling
      );

      stopwatch.stop();
      debugPrint('Palette extraction took ${stopwatch.elapsedMilliseconds}ms for $key');

      // Sort by combination of population (70%) and saturation (30%)
      final hsl = HSLColor.fromColor;
      final sortedColors = List<PaletteColor>.from(palette.paletteColors)
        ..sort((a, b) {
          final aScore =
              (a.population * 0.7) + (hsl(a.color).saturation * 1000 * 0.3);
          final bScore =
              (b.population * 0.7) + (hsl(b.color).saturation * 1000 * 0.3);
          return bScore.compareTo(aScore);
        });

      // Boost saturation by 15% for more vibrant colors
      Color boostSaturation(Color color) {
        final hslColor = hsl(color);
        return hslColor
            .withSaturation(
              (hslColor.saturation + 0.15).clamp(0.0, 1.0),
            )
            .toColor();
      }

      // Calculate average brightness to detect dark/muted palettes
      double calculateBrightness(List<Color> colors) {
        final brightness = colors.map((c) {
          final hsl = HSLColor.fromColor(c);
          return hsl.lightness;
        }).reduce((a, b) => a + b);
        return brightness / colors.length;
      }

      // Select top vibrant colors
      Color pickByScore(int index, Color fallbackColor) {
        if (sortedColors.length > index)
          return boostSaturation(sortedColors[index].color);
        return boostSaturation(fallbackColor);
      }

      final dominant = pickByScore(
        0,
        palette.dominantColor?.color ?? fallback[0],
      );

      // Get top 4-5 colors with saturation boost
      final extractedRaw = [
        dominant,
        pickByScore(1, palette.vibrantColor?.color ?? fallback[1]),
        pickByScore(2, palette.lightVibrantColor?.color ?? fallback[2]),
        pickByScore(3, palette.darkMutedColor?.color ?? fallback[3]),
        pickByScore(4, palette.lightMutedColor?.color ?? fallback[3]),
      ];

      // Check if colors are too dark/muted (average brightness < 0.25)
      final avgBrightness = calculateBrightness(extractedRaw);
      List<Color> extracted;

      if (avgBrightness < 0.25) {
        // Fallback: Use dominant color with gradient variations
        final base = palette.dominantColor?.color ?? fallback[0];
        extracted = [
          base,
          HSLColor.fromColor(base).withLightness(0.35).toColor(),
          HSLColor.fromColor(base).withLightness(0.25).toColor(),
          HSLColor.fromColor(base).withLightness(0.15).toColor(),
        ];
      } else {
        // Ensure at least one warm color if present in palette
        final hasWarmColor = sortedColors.any((c) {
          final hsl = HSLColor.fromColor(c.color);
          return hsl.hue >= 0 && hsl.hue <= 60 || hsl.hue >= 330;
        });

        if (hasWarmColor) {
          // Find and prioritize warm color
          final warmColor = sortedColors.firstWhere(
            (c) {
              final hsl = HSLColor.fromColor(c.color);
              return hsl.hue >= 0 && hsl.hue <= 60 || hsl.hue >= 330;
            },
            orElse: () => sortedColors[0],
          );
          extracted = [
            boostSaturation(warmColor.color),
            extractedRaw[0],
            extractedRaw[1],
            extractedRaw[2],
          ];
        } else {
          extracted = extractedRaw.take(4).toList();
        }
      }

      _albumColorCache[key] = extracted;
      _saveAlbumColorCache();

      if (!mounted) return;
      setState(() => _currentDynamicColors = extracted);
    } catch (_) {
      _albumColorCache[key] = fallback;
      _saveAlbumColorCache();
      if (mounted) setState(() => _currentDynamicColors = fallback);
    } finally {
      _albumColorExtractionInProgress.remove(key);
    }
  }

  // ── Album View Logic ──────────────────────────────────────────────────────
  Future<void> _openAlbum(Map<String, String> album) async {
    final normalizedAlbum = _resolvedAlbumMap(album);
    final albumId = _albumCacheKey(normalizedAlbum, source: 'open_album');
    final albumName =
        normalizedAlbum['displayName'] ?? album['name'] ?? 'Unknown Album';
    final cachedTracks = _albumTracksCache[albumId];
    final sortedCachedTracks = cachedTracks == null || cachedTracks.isEmpty
        ? null
        : _sortTracksForAlbum(cachedTracks);
    final cachedColors = _albumColorCache[albumId];
    final isLocalAlbum = _isLocalAlbumRecord(normalizedAlbum);
    final localIndexTracks = isLocalAlbum
        ? _sortTracksForAlbum(_localTracksForAlbumFromIndex(normalizedAlbum))
        : <drive.File>[];
    final localFallbackTracks = isLocalAlbum
        ? (localIndexTracks.isNotEmpty
            ? localIndexTracks
            : _sortTracksForAlbum(_localTracksForAlbum(normalizedAlbum)))
        : <drive.File>[];

    debugPrint(
        'AlbumOpen requested albumKey=$albumId cacheCount=${cachedTracks?.length ?? 0} indexCount=${isLocalAlbum ? localIndexTracks.length : 0} fallbackCount=${localFallbackTracks.length}');

    setState(() {
      _viewingAlbum = normalizedAlbum;
      _loadingAlbum = sortedCachedTracks == null &&
          (!isLocalAlbum || localFallbackTracks.isEmpty);
      _albumTracks = sortedCachedTracks ??
          (isLocalAlbum ? localFallbackTracks : <drive.File>[]);
      _albumMetadataLoading = false;
      _albumMetadataDone = 0;
      _albumMetadataTotal = 0;
      _currentDynamicColors = cachedColors ?? getAlbumGradient(albumName);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _extractAlbumColors(
        normalizedAlbum['cover'] ?? '',
        albumName,
        cacheKey: albumId,
      );
    });

    if (sortedCachedTracks != null) {
      _applyFirstCachedEmbeddedCover(normalizedAlbum, sortedCachedTracks);
      _indexAlbumFromTracks(normalizedAlbum, sortedCachedTracks);
      _indexTracksForAlbum(normalizedAlbum, sortedCachedTracks);
      unawaited(
          _hydrateAlbumDurationsInBackground(albumId, sortedCachedTracks));
      return;
    }

    try {
      List<drive.File> tracks;
      if (isLocalAlbum) {
        tracks = localFallbackTracks.isNotEmpty
            ? localFallbackTracks
            : _sortTracksForAlbum(_localTracksForAlbum(normalizedAlbum));
      } else {
        if (_user == null) {
          throw Exception('Sign in to load Drive albums.');
        }
        final headers = await _user!.authHeaders;
        final api = drive.DriveApi(GoogleAuthClient(headers));
        tracks =
            _sortTracksForAlbum(await _fetchTracksForAlbumRecord(api, album));
      }

      if (!mounted) return;

      _albumTracksCache[albumId] = tracks;
      if (isLocalAlbum && tracks.isEmpty) {
        debugPrint(
          'DataIntegrityWarning local album opened with zero restored tracks key=$albumId title=${normalizedAlbum['displayName'] ?? normalizedAlbum['name'] ?? ''} artist=${normalizedAlbum['artist'] ?? ''}',
        );
      }
      _applyFirstCachedEmbeddedCover(normalizedAlbum, tracks);
      _indexAlbumFromTracks(normalizedAlbum, tracks, save: false);
      _indexTracksForAlbum(normalizedAlbum, tracks);
      _saveLibraryBrain();
      _persistAlbums();

      setState(() {
        _albumTracks = tracks;
        _loadingAlbum = false;
      });
      unawaited(_hydrateAlbumDurationsInBackground(albumId, tracks));

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _precacheTrackArtwork(normalizedAlbum['cover'] ?? '');
      });
    } catch (e) {
      _showError('Failed to load album: $e');
      if (mounted) setState(() => _loadingAlbum = false);
    }
  }

  void _applyFirstCachedEmbeddedCover(
      Map<String, String> album, List<drive.File> tracks) {
    String? cachedEmbeddedCover;
    for (final track in tracks) {
      final cached = _metaStore.peek(track);
      if (cached?.coverPath != null && cached!.coverPath!.isNotEmpty) {
        cachedEmbeddedCover = cached.coverPath;
        break;
      }
    }

    if (cachedEmbeddedCover == null) return;

    bool changed = album['cover'] != cachedEmbeddedCover;
    album['cover'] = cachedEmbeddedCover;

    for (final savedAlbum in _albums) {
      if (savedAlbum['id'] == album['id']) {
        if (savedAlbum['cover'] != cachedEmbeddedCover) {
          savedAlbum['cover'] = cachedEmbeddedCover;
          changed = true;
        }
        break;
      }
    }

    if (changed) {
      _persistAlbums();
      if (mounted) setState(() {});
    }
  }

  void _precacheTrackArtwork(String coverUrl) {
    if (coverUrl.isEmpty || !_isLocalCover(coverUrl)) return;
    final provider = _coverProvider(coverUrl);
    if (provider != null) {
      precacheImage(provider, context).catchError((_) {});
    }
  }

  Future<void> _hydrateAlbumDurationsInBackground(
    String albumId,
    List<drive.File> tracks,
  ) async {
    final normalizedAlbumId = albumId.trim();
    if (normalizedAlbumId.isEmpty || tracks.isEmpty) return;
    if (_hydratingAlbumDurations.contains(normalizedAlbumId) ||
        _hydratedAlbumDurations.contains(normalizedAlbumId)) {
      return;
    }
    _hydratingAlbumDurations.add(normalizedAlbumId);

    var filled = 0;
    var stillMissing = 0;

    final missingTracks = <drive.File>[];
    for (final track in tracks) {
      if (_durationMsForTrack(track) == null) {
        missingTracks.add(track);
      }
    }
    _verboseScanLog(
        'AlbumDurationHydration start album=$normalizedAlbumId missing=${missingTracks.length}');

    try {
      // First pass: hydrate from already cached metadata/index only.
      var quickChanged = false;
      for (final track in missingTracks) {
        final trackId = DriveUtils.effectiveId(track);
        if (trackId == null || trackId.isEmpty) continue;

        final durationMs = _durationMsForTrack(track);
        if (durationMs == null) continue;

        _storeDurationForTrackId(
          trackId,
          durationMs,
          persist: false,
          refreshVisibleAlbum: false,
        );
        quickChanged = true;
        filled++;
        _verboseScanLog(
            'AlbumDurationHydration cached track=$trackId durationMs=$durationMs');
      }

      if (quickChanged) {
        await _saveKnownTrackDurations();
        await _saveLibraryTrackIndex();
        _invalidateLibraryBrowseCache();
        if (mounted && _viewingAlbum?['id'] == normalizedAlbumId) {
          setState(() {});
        }
      }

      // Second pass: best-effort backfill for truly missing Drive durations.
      // Local files are parsed at import time and should not try to use Drive auth.
      final driveMissingTracks = missingTracks
          .where((track) => !DriveUtils.isLocalFile(track))
          .toList(growable: false);
      if (driveMissingTracks.isEmpty || _user == null) {
        stillMissing =
            missingTracks.where((t) => _durationMsForTrack(t) == null).length;
        return;
      }

      final headers = await _user!.authHeaders;
      final bearer = headers['Authorization'] ?? headers['authorization'] ?? '';
      if (!bearer.startsWith('Bearer ')) return;
      final token = bearer.substring(7);

      var changed = false;
      var batchedUiUpdates = 0;
      final client = http.Client();
      try {
        for (final track in driveMissingTracks) {
          final trackId = DriveUtils.effectiveId(track);
          if (trackId == null || trackId.isEmpty) continue;

          final existing = _durationMsForTrack(track);
          if (existing != null) continue;

          final fastResult = await FastTagReader.read(
            file: track,
            token: token,
            readCover: false,
            client: client,
          );
          final durationMs =
              _validDurationMsFromValue(fastResult?.duration?.inMilliseconds);
          if (durationMs == null) continue;

          _storeDurationForTrackId(
            trackId,
            durationMs,
            persist: false,
            refreshVisibleAlbum: false,
          );
          changed = true;
          filled++;
          batchedUiUpdates++;
          _verboseScanLog(
              'AlbumDurationHydration cached track=$trackId durationMs=$durationMs');

          if (batchedUiUpdates >= 6 &&
              mounted &&
              _viewingAlbum?['id'] == normalizedAlbumId) {
            batchedUiUpdates = 0;
            setState(() {});
          }
        }
      } finally {
        client.close();
      }

      if (changed) {
        await _saveKnownTrackDurations();
        await _saveLibraryTrackIndex();
        _invalidateLibraryBrowseCache();
        if (mounted && _viewingAlbum?['id'] == normalizedAlbumId) {
          setState(() {});
        }
      }
      stillMissing = tracks.where((t) => _durationMsForTrack(t) == null).length;
    } catch (_) {
      // Best effort only.
    } finally {
      _hydratingAlbumDurations.remove(normalizedAlbumId);
      _hydratedAlbumDurations.add(normalizedAlbumId);
      _verboseScanLog(
          'AlbumDurationHydration complete album=$normalizedAlbumId filled=$filled stillMissing=$stillMissing');
    }
  }

  void _closeAlbum() {
    setState(() {
      _viewingAlbum = null;
      _albumTracks = [];
      _currentDynamicColors = List<Color>.from(_defaultDynamicColors);
    });
  }

  Future<List<drive.File>> _fetchTracksForAlbumRecord(
    drive.DriveApi api,
    Map<String, String> album,
  ) async {
    if (_isLocalAlbumRecord(album)) {
      return _sortTracksForAlbum(_localTracksForAlbum(album));
    }

    final List<drive.File> tracks = [];
    final folderIds =
        (album['id'] ?? '').split(',').where((id) => id.trim().isNotEmpty);

    for (final fId in folderIds) {
      String? pageToken;

      do {
        final res = await api.files.list(
          q: "'$fId' in parents and trashed = false",
          $fields:
              'files(id,name,mimeType,shortcutDetails(targetId,targetMimeType),size,modifiedTime),nextPageToken',
          pageSize: 100,
          pageToken: pageToken,
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
        );

        final files = res.files ?? <drive.File>[];
        tracks.addAll(files.where((file) => DriveUtils.isAudio(file)));
        pageToken = res.nextPageToken;
      } while (pageToken != null);
    }

    tracks.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    return tracks;
  }

  List<drive.File> _sortTracksForAlbum(List<drive.File> tracks) {
    final sorted = List<drive.File>.from(tracks);

    int discOf(drive.File file) {
      return _metaStore.peekFresh(file)?.discNumber ??
          _metaStore.peek(file)?.discNumber ??
          1;
    }

    int trackOf(drive.File file) {
      final cached = _metaStore.peekFresh(file) ?? _metaStore.peek(file);
      if (cached?.trackNumber != null) return cached!.trackNumber!;
      final name = file.name ?? '';
      final match = RegExp(r'^\s*(\d{1,3})[\s._-]+').firstMatch(name);
      return int.tryParse(match?.group(1) ?? '') ?? 9999;
    }

    String titleOf(drive.File file) {
      final cached = _metaStore.peekFresh(file) ?? _metaStore.peek(file);
      return (cached?.title ?? file.name ?? '').toLowerCase();
    }

    sorted.sort((a, b) {
      final discCompare = discOf(a).compareTo(discOf(b));
      if (discCompare != 0) return discCompare;

      final trackCompare = trackOf(a).compareTo(trackOf(b));
      if (trackCompare != 0) return trackCompare;

      return titleOf(a).compareTo(titleOf(b));
    });

    return sorted;
  }

  Future<void> _playCurrentAlbum({bool shuffle = false}) async {
    if (_albumTracks.isEmpty) return;

    final tracks = _sortTracksForAlbum(_albumTracks);
    if (shuffle && tracks.length > 1) {
      tracks.shuffle(math.Random());
    }

    setState(() => _albumTracks = tracks);

    final albumId = _viewingAlbum?['id'] ?? '';
    final coverUrl =
        _viewingAlbum?['cover'] ?? _libraryBrain[albumId]?['cover'] ?? '';

    await _playSong(
      tracks.first,
      queue: tracks,
      idx: 0,
      coverUrl: coverUrl,
      colors: _safeColors(_currentDynamicColors),
    );
  }

  // ── Drive Explorer ────────────────────────────────────────────────────────
  Future<void> _fetchExplore({required String folderId}) async {
    if (_user == null) {
      debugPrint('[DriveExplore] user not signed in');
      _driveExplorerLoadError = 'Sign in to load Drive folders.';
      return;
    }

    if (_loadingExplore) {
      debugPrint('Drive folder load skipped because already loading');
      return;
    }

    debugPrint('Drive folder load started');
    setState(() => _loadingExplore = true);
    _driveSettingsSetState?.call(() {});

    try {
      final headers = await _user!.authHeaders;
      final api = drive.DriveApi(GoogleAuthClient(headers));

      final result = await api.files.list(
        q: "'$folderId' in parents and trashed = false",
        $fields:
            'files(id,name,mimeType,shortcutDetails(targetId,targetMimeType),size,modifiedTime)',
        pageSize: 100,
        orderBy: 'folder,name',
        corpora: 'allDrives',
        spaces: 'drive',
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );

      final files = result.files ?? <drive.File>[];

      if (!mounted) return;

      var filteredFiles = files
          .where((f) => DriveUtils.isFolder(f) || DriveUtils.isAudio(f))
          .toList();

      if (folderId == 'root' &&
          filteredFiles.where(DriveUtils.isFolder).isEmpty) {
        debugPrint(
            'Drive root returned no direct children, loading all folders fallback');

        String? pageToken;
        final allFolders = <drive.File>[];
        do {
          final folderResult = await api.files.list(
            q: "mimeType = 'application/vnd.google-apps.folder' and trashed = false",
            $fields:
                'files(id,name,mimeType,shortcutDetails(targetId,targetMimeType),size,modifiedTime),nextPageToken',
            pageSize: 100,
            pageToken: pageToken,
            orderBy: 'name',
            corpora: 'allDrives',
            spaces: 'drive',
            supportsAllDrives: true,
            includeItemsFromAllDrives: true,
          );
          final folderFiles = folderResult.files ?? <drive.File>[];
          allFolders.addAll(
              folderFiles.where((f) => DriveUtils.isFolder(f)).toList());
          pageToken = folderResult.nextPageToken;
        } while (pageToken != null);

        filteredFiles = allFolders;
      }

      debugPrint(
          'Drive folder load completed with count ${filteredFiles.length}');

      setState(() {
        _exploreItems = filteredFiles;
        _loadingExplore = false;
        _driveExplorerLoadError = null;
      });
      _driveSettingsSetState?.call(() {});
    } catch (e) {
      debugPrint('Drive folder load failed with error: $e');
      _driveExplorerLoadError = e.toString();
      _driveExplorerAutoLoadAttempted = false;
      if (e.toString().contains('401')) {
        _showError('Session expired. Sign out and sign back in.');
      } else {
        _showError('Drive load failed: $e');
      }

      if (mounted) setState(() => _loadingExplore = false);
      _driveSettingsSetState?.call(() {});
    }
  }

  Future<void> _exploreGoBack() async {
    if (_navStack.isNotEmpty) {
      final prev = _navStack.removeLast();
      setState(() {
        _exploreFolder = prev.id == 'root' ? null : prev;
        _exploreItems = [];
      });
      _driveSettingsSetState?.call(() {});
      if (prev.id == 'root') {
        await _fetchExplore(folderId: 'root');
      } else {
        await _fetchExplore(folderId: prev.id ?? 'root');
      }
    } else {
      setState(() {
        _exploreFolder = null;
        _exploreItems = [];
      });
      _driveSettingsSetState?.call(() {});
      await _fetchExplore(folderId: 'root');
    }
  }

  Future<void> _openExploreFolder(drive.File folder) async {
    final tid = DriveUtils.effectiveId(folder);
    if (tid == null) return;

    debugPrint('selected folder changed: ${folder.name} (id: $tid)');

    if (_exploreFolder == null) {
      _navStack.add(drive.File()
        ..id = 'root'
        ..name = 'My Drive');
    } else {
      _navStack.add(_exploreFolder!);
    }

    final display = drive.File()
      ..id = tid
      ..name = folder.name
      ..mimeType = 'application/vnd.google-apps.folder';

    setState(() {
      _exploreFolder = display;
      _exploreItems = [];
    });
    _driveSettingsSetState?.call(() {});

    await _fetchExplore(folderId: tid);
  }

  // ── Playback ──────────────────────────────────────────────────────────────
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => _buildMainShellFromPart();

  Widget _buildSignInScreen() => _buildSignInScreenFromPart();

  // ── Album View ────────────────────────────────────────────────────────────
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

  // ── Library Tab ───────────────────────────────────────────────────────────

  // ── Search Tab ────────────────────────────────────────────────────────────

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
