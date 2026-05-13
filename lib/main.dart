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
part 'screens/home_tab.dart';
part 'screens/library_tab.dart';
part 'screens/drive_tab.dart';
part 'widgets/library_widgets.dart';
part 'widgets/player_widgets.dart';

// ─── Compatibility helpers for the local metadata model ─────────────────────
// These keep main.dart in sync even if lib/models/track_metadata.dart only has
// fromJson/toJson and plain fields.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(() {
    debugPrint('main start');
    return true;
  }());
  FlutterForegroundTask.initCommunicationPort();
  await _initAudioService();
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
  runApp(const MusixApp());
}

InfameAudioHandler? _infameAudioHandlerInstance;
bool _initialDarkMode = true;
const _themeModePrefsKey = 'infame_theme_mode';

Future<void> _loadStartupThemePreference() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    _initialDarkMode = prefs.getString(_themeModePrefsKey) != 'light';
  } catch (_) {}
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
const _neonPurple = Color(0xFF4B118C);
const _neonMagenta = Color(0xFFEE09A5);

// Artwork radius for album/song covers (sharp look like real album artwork)
const double kArtworkRadius = 8.0;

// Light Mode
const _lightBg = Color(0xFFFFFBFF);
const _lightSurface = Color(0xFFFFFFFF);
const _lightSurfaceSoft = Color(0xFFFFF1F8);
const _lightGlassBase = Color(0xFFF0EAF1);
const _lightAccentPink = Color(0xFFFF4FA3);
const _lightNavIconPink = Color(0xFFFF4FA3);
const _lightAccentPurple = Color(0xFF9B5CFF);
const _lightAccentMagenta = Color(0xFFE94DFF);
const _lightText = Color(0xFF20151E);
const _lightSubtext = Color(0xFF76616F);
const _lightTextPri = Color(0xFF1A1A1A);
const _lightTextSub = Color(0xFF666666);

// Dark Mode
const _darkBg = Color(0xFF0D0D11);
const _darkTextPri = Color(0xFFFFFFFF);
const _darkTextSub = Color(0xFFA0A0B0);

// Legacy colors for compatibility (will be phased out)
const _bg = Color(0xFF101014);
const _pink = Color(0xFFFF2A7A);
const _accentWhite = Color(0xFFEDEDED);
const _accentChampagne = Color(0xFFE6C8A0);
const _accentBlue = Color(0xFF8EA7FF);
const _accentPink = Color(0xFFFF4D8D);
const _accentDefault = _accentWhite;
const _cyan = Color(0xFF00E5FF);
const _purple = Color(0xFF7C4DFF);
const _textPri = Color(0xFFFFFFFF);
const _textSub = Color(0xFFA0A0B0);
const _glassWhite = Color(0x15FFFFFF);
const glassBorder = Color(0x30FFFFFF);

final List<Color> _defaultDynamicColors = [
  const Color(0xFF1C1C22),
  _accentPink,
  _accentBlue,
  _accentWhite,
];

// ─── Neon-Blob ColorScheme Generator ───────────────────────────────────────

/// Calculates luminance for WCAG contrast ratio
double _calculateLuminance(Color color) {
  final r = color.red / 255;
  final g = color.green / 255;
  final b = color.blue / 255;

  final rr =
      r <= 0.03928 ? r / 12.92 : math.pow((r + 0.055) / 1.055, 2.4).toDouble();
  final gg =
      g <= 0.03928 ? g / 12.92 : math.pow((g + 0.055) / 1.055, 2.4).toDouble();
  final bb =
      b <= 0.03928 ? b / 12.92 : math.pow((b + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * rr + 0.7152 * gg + 0.0722 * bb;
}

/// Calculates contrast ratio between two colors (WCAG)
double _calculateContrastRatio(Color foreground, Color background) {
  final lum1 = _calculateLuminance(foreground);
  final lum2 = _calculateLuminance(background);
  final lighter = math.max(lum1, lum2);
  final darker = math.min(lum1, lum2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Darkens a color to meet WCAG AA contrast (4.5:1) against white
Color _darkenForAccessibility(Color color,
    {Color background = const Color(0xFFFFFFFF)}) {
  Color adjusted = color;
  int steps = 0;
  while (_calculateContrastRatio(adjusted, background) < 4.5 && steps < 100) {
    adjusted = Color.fromARGB(
      adjusted.alpha,
      (adjusted.red * 0.95).round(),
      (adjusted.green * 0.95).round(),
      (adjusted.blue * 0.95).round(),
    );
    steps++;
  }
  return adjusted;
}

/// Lightens a color to meet WCAG AA contrast (4.5:1) against dark background
Color _lightenForAccessibility(Color color,
    {Color background = const Color(0xFF0D0D11)}) {
  Color adjusted = color;
  int steps = 0;
  while (_calculateContrastRatio(adjusted, background) < 4.5 && steps < 100) {
    adjusted = Color.fromARGB(
      adjusted.alpha,
      math.min(255, (adjusted.red + (255 - adjusted.red) * 0.1).round()),
      math.min(255, (adjusted.green + (255 - adjusted.green) * 0.1).round()),
      math.min(255, (adjusted.blue + (255 - adjusted.blue) * 0.1).round()),
    );
    steps++;
  }
  return adjusted;
}

/// Generates a complete ColorScheme for Neon-Blob aesthetic
class NeonBlobColorScheme {
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color disabled;
  final Color onDisabled;
  final Color hover;
  final Color pressed;

  const NeonBlobColorScheme({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.disabled,
    required this.onDisabled,
    required this.hover,
    required this.pressed,
  });

  /// Generate Light Mode ColorScheme
  factory NeonBlobColorScheme.light() {
    // Darken purple and magenta for text on white
    final primary = _darkenForAccessibility(_neonPurple);
    final secondary = _darkenForAccessibility(_neonMagenta);
    final tertiary = _darkenForAccessibility(_neonPurple.withOpacity(0.8));

    return NeonBlobColorScheme(
      primary: primary,
      onPrimary: _lightBg,
      primaryContainer: primary.withOpacity(0.12),
      onPrimaryContainer: primary,
      secondary: secondary,
      onSecondary: _lightBg,
      secondaryContainer: secondary.withOpacity(0.12),
      onSecondaryContainer: secondary,
      tertiary: tertiary,
      onTertiary: _lightBg,
      surface: _lightBg,
      onSurface: _lightTextPri,
      onSurfaceVariant: _lightTextSub,
      outline: primary.withOpacity(0.2),
      outlineVariant: secondary.withOpacity(0.15),
      disabled: Color.lerp(primary, const Color(0xFF808080), 0.5)!,
      onDisabled: _lightTextSub.withOpacity(0.5),
      hover: primary.withOpacity(0.08),
      pressed: primary.withOpacity(0.15),
    );
  }

  /// Generate Dark Mode ColorScheme
  factory NeonBlobColorScheme.dark() {
    // Lighten purple and magenta for text on dark
    final primary = _lightenForAccessibility(_neonPurple);
    final secondary = _lightenForAccessibility(_neonMagenta);
    final tertiary = _lightenForAccessibility(_neonPurple.withOpacity(0.8));

    return NeonBlobColorScheme(
      primary: primary,
      onPrimary: _darkBg,
      primaryContainer: primary.withOpacity(0.15),
      onPrimaryContainer: primary,
      secondary: secondary,
      onSecondary: _darkBg,
      secondaryContainer: secondary.withOpacity(0.15),
      onSecondaryContainer: secondary,
      tertiary: tertiary,
      onTertiary: _darkBg,
      surface: _darkBg,
      onSurface: _darkTextPri,
      onSurfaceVariant: _darkTextSub,
      outline: primary.withOpacity(0.3),
      outlineVariant: secondary.withOpacity(0.2),
      disabled: Color.lerp(primary, const Color(0xFF404040), 0.6)!,
      onDisabled: _darkTextSub.withOpacity(0.4),
      hover: primary.withOpacity(0.12),
      pressed: primary.withOpacity(0.22),
    );
  }
}

// ─── Neon-Blob Background Widget ───────────────────────────────────────────────

class _NeonBlobBackground extends StatelessWidget {
  final bool isDarkMode;

  const _NeonBlobBackground({required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    final purpleOpacity = isDarkMode ? 0.8 : 0.6;
    final magentaOpacity = isDarkMode ? 0.7 : 0.5;

    return RepaintBoundary(
      child: Container(
        color: isDarkMode ? const Color(0xFF050508) : _lightBg,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Top Left Purple Blob
            Positioned(
              top: -130,
              left: -120,
              child: _BlurredBlob(
                size: 360,
                blur: 70,
                colors: isDarkMode
                    ? [
                        _neonPurple.withOpacity(purpleOpacity),
                        _neonMagenta.withOpacity(magentaOpacity * 0.5),
                        Colors.transparent,
                      ]
                    : [
                        _lightAccentPurple.withOpacity(purpleOpacity),
                        _lightAccentPink.withOpacity(magentaOpacity * 0.5),
                        Colors.transparent,
                      ],
              ),
            ),
            // Bottom Right Magenta Blob
            Positioned(
              bottom: -180,
              right: -160,
              child: _BlurredBlob(
                size: 420,
                blur: 85,
                colors: isDarkMode
                    ? [
                        _neonMagenta.withOpacity(magentaOpacity),
                        _neonPurple.withOpacity(purpleOpacity * 0.5),
                        Colors.transparent,
                      ]
                    : [
                        _lightAccentMagenta.withOpacity(magentaOpacity),
                        _lightAccentPurple.withOpacity(purpleOpacity * 0.5),
                        Colors.transparent,
                      ],
              ),
            ),
            // Bottom Left Purple Blob
            Positioned(
              bottom: -130,
              left: 20,
              child: _BlurredBlob(
                size: 380,
                blur: 75,
                colors: isDarkMode
                    ? [
                        _neonPurple.withOpacity(purpleOpacity * 0.6),
                        _neonMagenta.withOpacity(magentaOpacity * 0.4),
                        Colors.transparent,
                      ]
                    : [
                        _lightAccentPurple.withOpacity(purpleOpacity * 0.6),
                        _lightAccentPink.withOpacity(magentaOpacity * 0.4),
                        Colors.transparent,
                      ],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isDarkMode
                          ? [
                              Colors.black.withOpacity(0.10),
                              Colors.black.withOpacity(0.42),
                            ]
                          : [
                              Colors.white.withOpacity(0.10),
                              Colors.white.withOpacity(0.55),
                            ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlurredBlob extends StatelessWidget {
  final double size;
  final double blur;
  final List<Color> colors;

  const _BlurredBlob({
    required this.size,
    required this.blur,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: colors,
              stops: const [0.0, 0.48, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

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

bool _isValidGlassMode(String mode) {
  return mode == glassModePerformance ||
      mode == _glassModeBalanced ||
      mode == glassModePretty;
}

bool _isValidAccentMode(String mode) {
  return mode == _accentModeWhite ||
      mode == _accentModeChampagne ||
      mode == _accentModeBlue ||
      mode == _accentModePink;
}

Color _accentColorForMode(String mode) {
  if (mode == _accentModeWhite) return _accentWhite;
  if (mode == _accentModeBlue) return _accentBlue;
  if (mode == _accentModePink) return _accentPink;
  return _accentChampagne;
}

String _accentModeLabelForMode(String mode) {
  if (mode == _accentModeWhite) return 'White';
  if (mode == _accentModeBlue) return 'Soft Blue';
  if (mode == _accentModePink) return 'Pink';
  return 'Champagne';
}

// ─── 4-Color Deterministic Gradient Generator ────────────────────────────────
List<Color> getAlbumGradient(String name) {
  int hash = 0;
  for (int i = 0; i < name.length; i++) {
    hash = name.codeUnitAt(i) + ((hash << 5) - hash);
  }

  final base = (hash % 360).abs().toDouble();

  return [
    HSLColor.fromAHSL(1.0, base, 0.46, 0.30).toColor(),
    HSLColor.fromAHSL(1.0, (base + 42) % 360, 0.52, 0.44).toColor(),
    HSLColor.fromAHSL(1.0, (base + 120) % 360, 0.38, 0.34).toColor(),
    HSLColor.fromAHSL(1.0, (base + 210) % 360, 0.34, 0.24).toColor(),
  ];
}

List<Color> _safeColors(List<Color> colors) {
  if (colors.length >= 4) return colors;
  return _defaultDynamicColors;
}

String _colorToHex(Color color) {
  return color.value.toRadixString(16).padLeft(8, '0');
}

Color? _colorFromHex(String value) {
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}

class _ArtworkCandidate {
  final String source;
  final String title;
  final String artist;
  final String year;
  final String imageUrl;
  final String thumbnailUrl;
  final double confidence;

  const _ArtworkCandidate({
    required this.source,
    required this.title,
    required this.artist,
    required this.year,
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.confidence,
  });
}

String _normalizeArtworkMatch(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'\[.*?\]|\(.*?\)'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

double _artworkConfidence({
  required String wantedAlbum,
  required String wantedArtist,
  required String candidateAlbum,
  required String candidateArtist,
  String wantedYear = '',
  String candidateYear = '',
}) {
  final album = _normalizeArtworkMatch(wantedAlbum);
  final artist = _normalizeArtworkMatch(wantedArtist);
  final candAlbum = _normalizeArtworkMatch(candidateAlbum);
  final candArtist = _normalizeArtworkMatch(candidateArtist);
  var score = 0.0;

  if (album.isNotEmpty && candAlbum.isNotEmpty) {
    if (album == candAlbum) {
      score += 0.58;
    } else if (candAlbum.contains(album) || album.contains(candAlbum)) {
      score += 0.38;
    }
  }

  if (artist.isNotEmpty &&
      artist != 'unknown artist' &&
      candArtist.isNotEmpty) {
    if (artist == candArtist) {
      score += 0.32;
    } else if (candArtist.contains(artist) || artist.contains(candArtist)) {
      score += 0.20;
    }
  }

  final y = RegExp(r'\d{4}').firstMatch(wantedYear)?.group(0) ?? '';
  final cy = RegExp(r'\d{4}').firstMatch(candidateYear)?.group(0) ?? '';
  if (y.isNotEmpty && cy.isNotEmpty && y == cy) score += 0.10;

  return score.clamp(0.0, 1.0);
}

String _localCoverPath(String source) {
  if (source.startsWith('file://')) {
    return Uri.parse(source).toFilePath();
  }
  return source;
}

bool _isLocalCover(String? source) {
  if (source == null || source.isEmpty) return false;
  return source.startsWith('file://') || source.startsWith('/');
}

// Album art can be massive when it comes from embedded tags. Decoding every
// image at full resolution makes grids feel slow even when the files are
// already cached locally. Keep UI decoding capped to a sensible cover size.
const int _coverThumbDecodeSize = 320;
const int _coverLargeDecodeSize = 900;

ImageProvider? _coverProvider(String? source,
    {int cacheSize = _coverThumbDecodeSize}) {
  if (source == null || source.isEmpty) return null;

  final baseProvider = _isLocalCover(source)
      ? FileImage(File(_localCoverPath(source))) as ImageProvider
      : NetworkImage(source);

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
  if (_isLocalCover(source)) {
    return Image.file(
      File(_localCoverPath(source)),
      fit: fit,
      cacheWidth: cacheSize,
      cacheHeight: cacheSize,
      errorBuilder: errorBuilder,
    );
  }

  return Image.network(
    source,
    fit: fit,
    cacheWidth: cacheSize,
    cacheHeight: cacheSize,
    errorBuilder: errorBuilder,
  );
}

// ─── App Root ────────────────────────────────────────────────────────────────
class MusixApp extends StatelessWidget {
  const MusixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infame',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        sliderTheme: const SliderThemeData(
          thumbColor: _accentDefault,
          activeTrackColor: _pink,
          inactiveTrackColor: _glassWhite,
          trackHeight: 4,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// ─── Now-Playing State ──────────────────────────────────────────────────────

final _nowPlaying = NowPlaying();

class _KeepAlivePage extends StatefulWidget {
  final WidgetBuilder builder;

  const _KeepAlivePage({super.key, required this.builder});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.builder(context);
  }
}

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
  bool _audioServicePlayerAttached = false;
  final Map<String, String> _artistImageCache = {};
  final Map<String, int> _artistImageFailureCooldown = {};
  final Set<String> _artistImageFetchInFlight = {};
  bool _artistImagePrefetchRunning = false;
  bool _changingTrack = false;
  bool _handlingTrackCompletion = false;
  int _playRequestSerial = 0;
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

  void _invalidateHomeBrowseCache() {
    _homeBrowseCacheVersion++;
    _cachedHomeListKey = '';
    _cachedRecentBrainAlbums = [];
    _cachedLastPlayedAlbums = [];
    _cachedHomeLibraryAlbums = [];
    _cachedHomeExploreAlbums = [];
    _cachedHomeHeavyRotationAlbums = [];
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
  final Map<String, List<drive.File>> _albumTracksCache = {};
  final Map<String, Duration> _knownTrackDurations = {};
  final Map<String, Map<String, String>> _libraryBrain = {};
  final Map<String, Map<String, String>> _libraryTrackIndex = {};
  final List<Map<String, String>> _playHistory = [];
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: _navIndex);
    _loadUiPreferences();
    _loadLikedTracks();
    _loadArtistImageCache();
    _loadLastPlayed();
    _loadCachedMetadata();
    _loadLibraryBrainAndHistory();
    _loadLibraryTrackIndex();
    _loadKnownTrackDurations();
    _trySilentSignIn();

    FlutterForegroundTask.addTaskDataCallback(_onMetadataTaskData);
    _startMetadataProgressPolling();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestForegroundMetadataPermissions();
      _initForegroundMetadataService();
    });

    _processingStateSub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _handleTrackCompleted();
      }
      _syncAudioServicePlaybackState();
    });
    _playerStateSub = _player.playerStateStream.listen((_) {
      _syncAudioServicePlaybackState();
    });
    _playbackEventSub = _player.playbackEventStream.listen((_) {
      _syncAudioServicePlaybackState();
    });

    final handler = _infameAudioHandlerInstance;
    handler?.bindCallbacks(
      onPlay: () async {
        await _player.play();
        _infameAudioHandlerInstance?.syncPlaybackStateFromPlayer();
        _syncAudioServicePlaybackState();
      },
      onPause: () async {
        await _player.pause();
        _syncAudioServicePlaybackState();
      },
      onStop: () async {
        await _player.stop();
        _syncAudioServicePlaybackState();
      },
      onSeek: (position) async {
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
    _searchSearchController.text = _searchQuery;
    _ensureAudioServicePlayerAttached();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureAudioServicePlayerAttached();
    });
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onMetadataTaskData);
    _metadataProgressPoller?.cancel();
    _processingStateSub?.cancel();
    _playerStateSub?.cancel();
    _playbackEventSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_shutdownPlaybackService());
    _pageController.dispose();
    _librarySearchController.dispose();
    _searchSearchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(_shutdownPlaybackService());
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
    if (mounted) setState(() {});
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
    final existing = _lastPlayed;
    final sameAsExisting = existing?['fileId'] == fileId;
    final data = <String, String>{
      'fileId': fileId,
      'fileName': file.name ?? meta['title'] ?? 'Unknown',
      'title': meta['title'] ?? file.name ?? 'Unknown',
      'artist': meta['artist'] ?? 'Unknown Artist',
      'coverUrl':
          coverUrl ?? (sameAsExisting ? (existing?['coverUrl'] ?? '') : ''),
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
      if (raw == null || raw.isEmpty) return;

      final decoded = json.decode(raw);
      if (decoded is Map) {
        _libraryTrackIndex.clear();
        decoded.forEach((key, value) {
          if (key is String && value is Map) {
            _libraryTrackIndex[key] = Map<String, String>.from(value);
          }
        });

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

        await _saveLibraryTrackIndex();
        _invalidateLibraryBrowseCache();
        _queueArtistImagePrefetch();
      }
    } catch (_) {}
  }

  Future<void> _saveLibraryTrackIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _libraryTrackIndexKey, json.encode(_libraryTrackIndex));
    } catch (_) {}
  }

  Future<void> _loadKnownTrackDurations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_knownTrackDurationsKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = json.decode(raw);
      if (decoded is Map) {
        _knownTrackDurationsMs.clear();
        decoded.forEach((key, value) {
          if (key is! String) return;
          final durationMs = _validDurationMsFromValue(value);
          if (durationMs == null) return;
          _setKnownTrackDuration(key, durationMs);
        });

        final repaired = _repairLibraryTrackIndexFromAlbums();
        if (repaired) await _saveLibraryTrackIndex();
        if (mounted) setState(() {});
      }
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
    return album['cover'] ??
        album['customCoverUrl'] ??
        album['coverUrl'] ??
        album['thumbnailLink'] ??
        album['artwork'] ??
        '';
  }

  String _albumStableKey(Map<String, String> album) {
    final id = (album['id'] ?? '').trim();
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

  bool _applyAlbumCoverFromMetadataScan(String albumId, String coverPath) {
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
      _saveLibraryBrain();
    }

    for (final record in _libraryTrackIndex.values) {
      if ((record['albumId'] ?? '') == albumId &&
          record['albumCover'] != coverPath) {
        record['albumCover'] = coverPath;
        changed = true;
      }
    }

    if (changed) {
      _librarySearchTextCache.clear();
      _persistAlbums();
      _saveLibraryTrackIndex();
      _invalidateHomeBrowseCache();
      _invalidateLibraryBrowseCache();
      if (mounted) setState(() {});
    }

    return changed;
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

  String _formatDurationMs(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

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
      final source = DriveAudioSource(fileId, token);

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

            // Duration from known cache
            final durationMs = _knownTrackDurationsMs[trackId];

            final record = <String, String>{
              'id': trackId,
              'name': track.name ?? '',
              'albumId': album['id'] ?? '',
              'albumName': album['name'] ?? '',
              'albumArtist': _canonicalArtistName(
                albumArtist: album['artist'],
                trackArtist:
                    meta?.artist ?? trackMeta['artist']?.toString() ?? '',
                albumName: album['name'] ?? '',
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
              record['album'] = album['name'] ?? '';
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
    return drive.File()
      ..id = record['id']
      ..name = record['name']
      ..mimeType = record['mimeType']
      ..thumbnailLink = record['thumbnailLink']
      ..size = record['size'] ?? '0'
      ..modifiedTime = modifiedTime != null
          ? DateTime.fromMillisecondsSinceEpoch(modifiedTime)
          : null;
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
    for (final track in tracks) {
      final trackId = DriveUtils.effectiveId(track);
      if (trackId == null || trackId.isEmpty) continue;

      final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      final trackMeta = DriveUtils.getTrackMeta(track);

      final albumCover = _albumCoverForIndex(album);

      // Duration from known cache
      final durationMs = _knownTrackDurationsMs[trackId];

      final record = <String, String>{
        'id': trackId,
        'name': track.name ?? '',
        'albumId': album['id'] ?? '',
        'albumName': album['name'] ?? '',
        'albumArtist': _canonicalArtistName(
          albumArtist: album['artist'],
          trackArtist: meta?.artist ?? trackMeta['artist']?.toString() ?? '',
          albumName: album['name'] ?? '',
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
        record['title'] = trackMeta['title']?.toString() ?? track.name ?? '';
        record['artist'] = trackMeta['artist']?.toString() ?? '';
        record['album'] = album['name'] ?? '';
        record['year'] = trackMeta['year']?.toString() ?? '';
        record['genre'] = trackMeta['genre']?.toString() ?? '';
        record['trackNumber'] = trackMeta['trackNumber']?.toString() ?? '';
        record['discNumber'] = trackMeta['discNumber']?.toString() ?? '';
      }

      _libraryTrackIndex[trackId] = record;
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

    final artist = _cleanBrainValue(parts.first);
    final album = _cleanBrainValue(parts.sublist(1).join(' - '));
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
      _buildBasicLibraryBrain(save: false);
      _queueArtistImagePrefetch();
    } catch (_) {}
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
      final id = album['id'] ?? '';
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
    final id = album['id'] ?? '';
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
    final commonAlbum = _mostCommon(albumNames);
    final displayName = commonAlbum.isNotEmpty
        ? commonAlbum
        : folderGuess['album'] ?? folderName;
    final commonArtist = _mostCommon(artists);
    final artist = _canonicalArtistName(
      albumArtist: commonArtist,
      trackArtist: existing['artist'] ?? '',
      albumName: folderName,
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
    final albumId = _viewingAlbum?['id'] ?? '';
    final albumName = _viewingAlbum?['name'] ?? '';
    final now = DateTime.now().millisecondsSinceEpoch.toString();

    _playHistory.removeWhere((item) => item['fileId'] == fileId);
    _playHistory.insert(0, {
      'fileId': fileId,
      'title': meta['title'] ?? file.name ?? 'Unknown',
      'artist': meta['artist'] ?? 'Unknown Artist',
      'albumId': albumId,
      'albumName': albumName,
      'cover': coverUrl ?? _viewingAlbum?['cover'] ?? '',
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
      existing['cover'] =
          coverUrl ?? existing['cover'] ?? _viewingAlbum?['cover'] ?? '';
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
          final id = album['id'] ?? '';
          final brain =
              Map<String, String>.from(_libraryBrain[id] ?? <String, String>{});
          brain['albumId'] = id;
          brain['name'] = brain['name'] ?? album['name'] ?? 'Album';
          brain['displayName'] =
              brain['displayName'] ?? brain['name'] ?? 'Album';
          brain['cover'] = album['cover'] ?? brain['cover'] ?? '';
          brain['dateAdded'] = album['dateAdded'] ?? brain['dateAdded'] ?? '0';
          return brain;
        })
        .where((item) => (item['albumId'] ?? '').isNotEmpty)
        .toList();

    return items;
  }

  Map<String, String>? _albumById(String id) {
    for (final album in _albums) {
      if ((album['id'] ?? '') == id) return album;
    }
    return null;
  }

  void _openAlbumByBrain(Map<String, String> info) {
    final id = info['albumId'] ?? info['id'] ?? '';
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
      final albumId = data['albumId']?.toString() ?? '';
      final coverPath = data['coverPath']?.toString() ?? '';
      _applyAlbumCoverFromMetadataScan(albumId, coverPath);
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

    setState(() {
      _navIndex = index;
      _viewingAlbum = null;
      _currentDynamicColors = List<Color>.from(_defaultDynamicColors);
    });

    if (_pageController.hasClients) {
      if (animate) {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } else {
        _pageController.jumpToPage(index);
      }
    }
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

  void _openSettingsSheet() {
    final colors = _safeColors(_currentDynamicColors);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.70),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            _settingsSheetSetState = setSheetState;
            final accent = _appAccent;

            final progress = _metadataTotal > 0
                ? (_metadataDone / _metadataTotal).clamp(0.0, 1.0)
                : null;

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
              child: Container(
                height: MediaQuery.of(sheetContext).size.height * 0.88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.zero,
                  border: Border(
                      top: BorderSide(
                          color: _isDarkMode
                              ? Colors.white.withOpacity(0.12)
                              : Colors.black.withOpacity(0.08))),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _isDarkMode
                        ? [
                            colors[0].withOpacity(0.22),
                            _bg.withOpacity(0.98),
                            Colors.black,
                          ]
                        : [
                            _lightGlassBase.withOpacity(0.92),
                            _lightBg.withOpacity(0.98),
                            _lightBg,
                          ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 34),
                            ),
                            const Spacer(),
                            Text(
                              'Settings',
                              style: GoogleFonts.inter(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: _isDarkMode ? _textPri : _lightText,
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
                          children: [
                            Text(
                              'Infame Control Center',
                              style: GoogleFonts.inter(
                                color:
                                    _isDarkMode ? _textPri : _lightText,
                                fontSize: 27,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Library tools, background metadata scanning, cache cleanup and safety controls live here now.',
                              style: GoogleFonts.inter(
                                color:
                                    _isDarkMode ? _textSub : _lightSubtext,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 22),
                            GlassyContainer(
                              radius: 24,
                              padding: const EdgeInsets.all(16),
                              customColor: _isDarkMode
                                  ? Colors.white.withOpacity(0.075)
                                  : _lightGlassBase.withOpacity(0.78),
                              customBorder: _isDarkMode
                                  ? accent.withOpacity(0.22)
                                  : Colors.black.withOpacity(0.08),
                              child: Row(
                                children: [
                                  Icon(
                                    _isDarkMode
                                        ? Icons.dark_mode_rounded
                                        : Icons.light_mode_rounded,
                                    color: accent,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _isDarkMode ? 'Dark Mode' : 'Light Mode',
                                      style: GoogleFonts.inter(
                                        color: _isDarkMode ? _textPri : _lightText,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: _isDarkMode,
                                    onChanged: (value) {
                                      setState(() => _isDarkMode = value);
                                      setSheetState(() {});
                                      _saveUiPreferences();
                                    },
                                    activeColor: accent,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            GlassyContainer(
                              radius: 24,
                              padding: const EdgeInsets.all(16),
                              customColor: _isDarkMode
                                  ? Colors.white.withOpacity(0.075)
                                  : _lightGlassBase.withOpacity(0.78),
                              customBorder: _isDarkMode
                                  ? accent.withOpacity(0.22)
                                  : Colors.black.withOpacity(0.08),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _loadingMetadata
                                            ? Icons.sync_rounded
                                            : Icons.library_music_rounded,
                                        color: accent,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _metadataStatusLabel(),
                                          style: GoogleFonts.inter(
                                            color: _isDarkMode
                                                ? _textPri
                                                : _lightText,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 6,
                                      backgroundColor: _isDarkMode
                                          ? Colors.white.withOpacity(0.14)
                                          : Colors.black.withOpacity(0.08),
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(accent),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      _MetadataStat(
                                          label: 'Fast', value: _metadataFast),
                                      _MetadataStat(
                                          label: 'Deep',
                                          value: _metadataDeep,
                                          isDarkMode: _isDarkMode),
                                      _MetadataStat(
                                          label: 'Failed',
                                          value: _metadataFailed,
                                          isDarkMode: _isDarkMode),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            _SettingsPrimaryButton(
                              label: _loadingMetadata
                                  ? 'Cancel metadata scan'
                                  : 'Scan missing metadata (whole library)',
                              icon: _loadingMetadata
                                  ? Icons.stop_rounded
                                  : Icons.sync_rounded,
                              accent: accent,
                              destructive: _loadingMetadata,
                              isDarkMode: _isDarkMode,
                              onTap: () {
                                if (_loadingMetadata) {
                                  _cancelForegroundMetadataScan();
                                } else {
                                  _startForegroundLibraryMetadataScan();
                                }
                                setSheetState(() {});
                              },
                            ),
                            const SizedBox(height: 24),
                            _SettingsSectionTitle(
                                title: 'Library', isDarkMode: _isDarkMode),
                            _SettingsInfoCard(
                              icon: Icons.album_rounded,
                              title: '${_albums.length} albums saved',
                              subtitle:
                                  '${_metaStore.count} cached song metadata entries',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                            ),
                            const SizedBox(height: 10),
                            _SettingsActionRow(
                              icon: Icons.restore_rounded,
                              title: 'Restore previous library',
                              subtitle:
                                  'Recover the backup saved before clearing the app library.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: _restoreLibraryBackup,
                            ),
                            _SettingsActionRow(
                              icon: Icons.refresh_rounded,
                              title: 'Rescan current Drive folder',
                              subtitle: _exploreFolder == null
                                  ? 'Open a folder in Search first, then scan it here.'
                                  : 'Scan "${_exploreFolder!.name ?? 'folder'}" into your library.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: _exploreFolder == null || _isScanning
                                  ? null
                                  : () => _scanFolderToLibrary(_exploreFolder!),
                            ),
                            _SettingsActionRow(
                              icon: Icons.image_search_rounded,
                              title: 'Find covers for all albums',
                              subtitle:
                                  'Searches embedded art and online sources for albums without covers.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: _findCoversForAllAlbums,
                            ),
                            const SizedBox(height: 18),
                            _SettingsSectionTitle(
                                title: 'Music source', isDarkMode: _isDarkMode),
                            _SettingsActionRow(
                              icon: Icons.storage_rounded,
                              title: 'Google Drive',
                              subtitle:
                                  'Open your Drive folders, select sources and scan music.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: () {
                                Navigator.pop(sheetContext);
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted) _openDriveSourcePage();
                                });
                              },
                            ),
                            const SizedBox(height: 18),
                            _SettingsSectionTitle(
                                title: 'Cache', isDarkMode: _isDarkMode),
                            _SettingsActionRow(
                              icon: Icons.tag_rounded,
                              title: 'Clear metadata cache',
                              subtitle:
                                  'Forces titles, artists and albums to be scanned again.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: _clearMetadataCacheSafely,
                            ),
                            _SettingsActionRow(
                              icon: Icons.image_not_supported_rounded,
                              title: 'Clear embedded cover cache',
                              subtitle:
                                  'Removes local cover images saved by metadata scans.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: _clearCoverCacheSafely,
                            ),
                            const SizedBox(height: 18),
                            _SettingsSectionTitle(
                                title: 'Home Screen', isDarkMode: _isDarkMode),
                            _SettingsActionRow(
                              icon: Icons.auto_awesome_rounded,
                              title: 'Rebuild Smart Home index',
                              subtitle:
                                  'Refreshes Home sections from cached metadata and opened albums.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: _rebuildSmartHomeIndex,
                            ),
                            _SettingsSwitchRow(
                              icon: Icons.history_rounded,
                              title: 'Continue listening',
                              subtitle:
                                  'Show recent albums and recent tracks on Home.',
                              value: _homeShowContinue,
                              accent: colors[1],
                              isDarkMode: _isDarkMode,
                              onChanged: (value) {
                                setState(() => _homeShowContinue = value);
                                setSheetState(() {});
                                _saveUiPreferences();
                              },
                            ),
                            // Hidden until genre section exists
                            // _SettingsSwitchRow(
                            //   icon: Icons.category_rounded,
                            //   title: 'Genre shelves',
                            //   subtitle: 'Show Hip-Hop, Soul, Jazz and other shelves when tags exist.',
                            //   value: _homeShowGenres,
                            //   accent: colors[1],
                            //   onChanged: (value) {
                            //     setState(() => _homeShowGenres = value);
                            //     setSheetState(() {});
                            //     _saveUiPreferences();
                            //   },
                            // ),
                            // Hidden until decade section exists
                            // _SettingsSwitchRow(
                            //   icon: Icons.calendar_month_rounded,
                            //   title: 'Decade shelves',
                            //   subtitle: 'Show 90s, 2000s and other year-based rows when metadata exists.',
                            //   value: _homeShowDecades,
                            //   accent: colors[1],
                            //   onChanged: (value) {
                            //     setState(() => _homeShowDecades = value);
                            //     setSheetState(() {});
                            //     _saveUiPreferences();
                            //   },
                            // ),
                            _SettingsSwitchRow(
                              icon: Icons.person_rounded,
                              title: 'Your Library',
                              subtitle: 'Show your library albums on home.',
                              value: _homeShowArtists,
                              accent: colors[1],
                              isDarkMode: _isDarkMode,
                              onChanged: (value) {
                                setState(() => _homeShowArtists = value);
                                setSheetState(() {});
                                _saveUiPreferences();
                              },
                            ),
                            _SettingsSwitchRow(
                              icon: Icons.casino_rounded,
                              title: 'Discovery card',
                              subtitle: 'Show the random-library pick card.',
                              value: _homeShowDiscovery,
                              accent: colors[1],
                              isDarkMode: _isDarkMode,
                              onChanged: (value) {
                                setState(() => _homeShowDiscovery = value);
                                setSheetState(() {});
                                _saveUiPreferences();
                              },
                            ),
                            const SizedBox(height: 18),
                            _SettingsSectionTitle(
                                title: 'Performance', isDarkMode: _isDarkMode),
                            _SettingsActionRow(
                              icon: Icons.tune_rounded,
                              title:
                                  'Glass mode: ${_glassModeLabel(_glassMode)}',
                              subtitle: _glassModeDescription(_glassMode),
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: () => _cycleGlassMode(setSheetState),
                            ),
                            _SettingsSwitchRow(
                              icon: Icons.gradient_rounded,
                              title: 'Background glow',
                              subtitle:
                                  'Soft mesh glow without list blur. Turn off only if page swipes still feel heavy.',
                              value: _showBackgroundGlow,
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onChanged: (value) {
                                setState(() => _showBackgroundGlow = value);
                                setSheetState(() {});
                                _saveUiPreferences();
                              },
                            ),
                            _SettingsInfoCard(
                              icon: Icons.speed_rounded,
                              title: 'Album opening optimized',
                              subtitle:
                                  'Track lists are cached in memory, album colors are cached, and scrolling cards use fake glass.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                            ),
                            const SizedBox(height: 18),
                            _SettingsSectionTitle(
                                title: 'Appearance', isDarkMode: _isDarkMode),
                            _SettingsActionRow(
                              icon: Icons.palette_rounded,
                              title:
                                  'Accent color: ${_accentModeLabelForMode(_accentMode)}',
                              subtitle:
                                  'Cycles White, Champagne, Soft Blue and Pink. No loud yellow.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: () => _cycleAccentMode(setSheetState),
                            ),
                            const SizedBox(height: 10),
                            _SettingsInfoCard(
                              icon: Icons.auto_awesome_rounded,
                              title: 'Dark glass UI enabled',
                              subtitle:
                                  'No rainbow headers. The app uses controlled glass, album-color glow, and cheaper scrolling cards.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                            ),
                            const SizedBox(height: 18),
                            _SettingsSectionTitle(
                                title: 'Danger Zone', isDarkMode: _isDarkMode),
                            _SettingsActionRow(
                              icon: Icons.delete_outline_rounded,
                              title: 'Clear app library cache',
                              subtitle:
                                  'Does not touch Google Drive files. Requires typing CLEAR.',
                              accent: Colors.redAccent,
                              destructive: true,
                              isDarkMode: _isDarkMode,
                              onTap: _clearLibraryCacheSafely,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _settingsSheetSetState = null;
    });
  }

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
      await _loadAlbums();
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

    _nowPlaying.setTrack(
      drive.File()..name = '',
      [],
      -1,
      coverUrl: null,
      colors: _defaultDynamicColors,
    );
    _nowPlaying.track = null;
    _nowPlaying.refresh();

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
    if (changed) await _persistAlbums();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _precacheAlbumCovers(limit: 36);
    });
  }

  void _precacheAlbumCovers({int limit = 36}) {
    final candidates = _albums
        .map((album) => album['cover'] ?? '')
        .where((cover) => cover.isNotEmpty)
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
    bool changed = false;

    void applyToAlbum(Map<String, String> album) {
      album['cover'] = coverPath;
      changed = true;
    }

    if (albumRecord != null) {
      final albumId = albumRecord['id'];
      for (final album in _albums) {
        if (album['id'] == albumId) {
          applyToAlbum(album);
          break;
        }
      }

      if (_viewingAlbum != null && _viewingAlbum!['id'] == albumId) {
        _viewingAlbum!['cover'] = coverPath;
        changed = true;
      }
    } else if (_viewingAlbum != null && fileId != null) {
      final inCurrentAlbum =
          _albumTracks.any((track) => DriveUtils.effectiveId(track) == fileId);
      if (inCurrentAlbum) {
        _viewingAlbum!['cover'] = coverPath;
        for (final album in _albums) {
          if (album['id'] == _viewingAlbum!['id']) {
            album['cover'] = coverPath;
            break;
          }
        }
        changed = true;
      }
    }

    if (_nowPlaying.track != null && fileId != null) {
      final activeId = DriveUtils.effectiveId(_nowPlaying.track!);
      if (activeId == fileId) {
        _nowPlaying.currentCoverUrl = coverPath;
        _nowPlaying.refresh();
      }
    }

    if (changed) {
      final albumIdForCover = albumRecord?['id'] ?? _viewingAlbum?['id'] ?? '';
      if (albumIdForCover.isNotEmpty) {
        for (final record in _libraryTrackIndex.values) {
          if ((record['albumId'] ?? '') == albumIdForCover) {
            record['albumCover'] = coverPath;
          }
        }
        _saveLibraryTrackIndex();
      }
      _persistAlbums();
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadMetadataFor(
    drive.File file,
    String token, {
    Map<String, String>? albumRecord,
  }) async {
    final fileId = DriveUtils.effectiveId(file);
    if (fileId == null) return;

    final cachedFresh = _metaStore.peekFresh(file);
    final cachedDurationMs =
        _validDurationMsFromValue(_knownTrackDurationsMs[fileId]);
    if (cachedFresh != null && cachedDurationMs != null) return;

    File? tempFile;

    try {
      final fallback = DriveUtils.getTrackMeta(file);
      TrackReadResult? fastResult =
          await FastTagReader.read(file: file, token: token);
      String? embeddedCoverPath;

      if (fastResult?.coverBytes != null) {
        embeddedCoverPath =
            await _saveEmbeddedCover(file, fastResult!.coverBytes!);
        if (embeddedCoverPath != null) {
          _applyEmbeddedCoverToAlbum(file, embeddedCoverPath,
              albumRecord: albumRecord);
        }
      }

      // Extract duration using temporary player if not already cached
      if (_knownTrackDurationsMs[fileId] == null) {
        final duration = await _getDurationWithTemporaryPlayer(file, token);
        if (duration != null &&
            duration.inMilliseconds > 0 &&
            duration.inMilliseconds < 86400000) {
          final durationMs = duration.inMilliseconds;
          _knownTrackDurationsMs[fileId] = durationMs;
          _knownTrackDurations[fileId] = duration;

          // Update library track index if record exists
          if (_libraryTrackIndex.containsKey(fileId)) {
            _libraryTrackIndex[fileId]!['durationMs'] = durationMs.toString();
          }
        }
      }

      if (fastResult != null && fastResult.hasUsefulText) {
        await _metaStore.put(
          file,
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
          ),
        );

        _nowPlaying.refresh();
        if (mounted) setState(() {});
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

      await _metaStore.put(
        file,
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
        ),
      );

      _nowPlaying.refresh();
      if (mounted) setState(() {});
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

      const batchSize = 2;

      for (int i = 0; i < tracks.length; i += batchSize) {
        if (!mounted) return;

        final batch = tracks.skip(i).take(batchSize).toList();
        await Future.wait(batch.map((track) => _loadMetadataFor(track, token)));
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
      final id = DriveUtils.effectiveId(track);
      final metadataMissing = _metaStore.peekFresh(track) == null;
      final durationMissing = id == null ||
          _validDurationMsFromValue(_knownTrackDurationsMs[id]) == null;
      return metadataMissing || durationMissing;
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
      const batchSize = 2;
      int tracksProcessed = 0;

      for (int i = 0; i < missing.length; i += batchSize) {
        if (!mounted) return;

        final batch = missing.skip(i).take(batchSize).toList();

        await Future.wait(
          batch.map((track) async {
            await _loadMetadataFor(track, token, albumRecord: _viewingAlbum);
            if (mounted) {
              setState(() => _albumMetadataDone++);
            }
          }),
        );

        tracksProcessed += batch.length;

        // Save durations every 20 tracks
        if (tracksProcessed % 20 == 0) {
          await _saveKnownTrackDurations();
        }
      }

      if (!mounted) return;

      // Final save of durations
      await _saveKnownTrackDurations();

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

      final missing = uniqueTracks.values.where((track) {
        final id = DriveUtils.effectiveId(track);
        final metadataMissing = _metaStore.peekFresh(track) == null;
        final durationMissing = id == null ||
            _validDurationMsFromValue(_knownTrackDurationsMs[id]) == null;
        return metadataMissing || durationMissing;
      }).toList()
        ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

      if (!mounted) return;

      if (missing.isEmpty) {
        setState(() => _loadingMetadata = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Metadata is already loaded for your whole library.',
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

      const batchSize = 2;
      int tracksProcessed = 0;

      for (int i = 0; i < missing.length; i += batchSize) {
        if (!mounted) return;

        final batch = missing.skip(i).take(batchSize).toList();

        await Future.wait(
          batch.map((track) async {
            final id = DriveUtils.effectiveId(track);
            await _loadMetadataFor(
              track,
              token,
              albumRecord: id == null ? null : trackAlbums[id],
            );
            if (mounted) {
              _metadataDone++;
              _updateMetadataProgressUi();
            }
          }),
        );

        tracksProcessed += batch.length;

        // Save durations and library index every 20 tracks
        if (tracksProcessed % 20 == 0) {
          await _saveKnownTrackDurations();
          await _saveLibraryTrackIndex();
        }
      }

      if (!mounted) return;

      setState(() => _loadingMetadata = false);
      _updateMetadataProgressUi(force: true);
      await _persistAlbums();

      // Final save of durations and library index
      await _saveKnownTrackDurations();

      for (final album in _albums) {
        final albumId = album['id'] ?? '';
        final cachedTracks = _albumTracksCache[albumId];
        if (cachedTracks != null) {
          _indexTracksForAlbum(album, cachedTracks);
        }
      }
      await _saveLibraryTrackIndex();

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
      }

      await _persistAlbums();
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
    final tracks = _albumTracks.isNotEmpty
        ? _sortTracksForAlbum(_albumTracks)
        : _albumTracksCache[album['id'] ?? ''] ?? <drive.File>[];

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

  Future<void> _findCoversForAllAlbums() async {
    if (_user == null || _albums.isEmpty) {
      _showError('Please sign in first.');
      return;
    }

    _showSuccess('Starting cover search for ${_albums.length} albums...');
    int found = 0;
    int failed = 0;

    for (final album in _albums) {
      final albumId = album['id'] ?? '';
      final brain = _libraryBrain[albumId] ?? const <String, String>{};
      final albumName = brain['displayName'] ??
          album['displayName'] ??
          album['name'] ??
          'Unknown Album';
      final artist = _cleanBrainValue(brain['artist']).isNotEmpty
          ? brain['artist']!
          : _cleanBrainValue(album['artist']).isNotEmpty
              ? album['artist']!
              : 'Unknown Artist';

      if (album['cover'] != null && album['cover']!.isNotEmpty) {
        continue;
      }

      final embedded = await _findEmbeddedCoverForAlbum(album);
      if (embedded != null && embedded.isNotEmpty) {
        album['cover'] = embedded;
        found++;
        await _extractAlbumColors(embedded, albumName);
        continue;
      }

      final fetched = await _fetchCoverArt(albumName, artist);
      if (fetched != null && fetched.isNotEmpty) {
        album['cover'] = fetched;
        found++;
        await _extractAlbumColors(fetched, albumName);
      } else {
        failed++;
      }
    }

    await _persistAlbums();
    _showSuccess('Cover search complete: $found found, $failed failed.');
  }

  String _albumTitleForArtwork(Map<String, String> album) {
    final id = album['id'] ?? '';
    final brain = _libraryBrain[id] ?? const <String, String>{};
    return (brain['displayName'] ??
            album['displayName'] ??
            album['name'] ??
            'Unknown Album')
        .trim();
  }

  String _albumArtistForArtwork(Map<String, String> album) {
    final id = album['id'] ?? '';
    final brain = _libraryBrain[id] ?? const <String, String>{};
    final fromBrain = _cleanBrainValue(brain['artist'] ?? '');
    if (fromBrain.isNotEmpty) return fromBrain;
    final fromAlbum = _cleanBrainValue(album['artist'] ?? '');
    if (fromAlbum.isNotEmpty) return fromAlbum;
    if (_albumTracks.isNotEmpty) {
      final meta = _metaStore.peekFresh(_albumTracks.first) ??
          _metaStore.peek(_albumTracks.first);
      if ((meta?.artist ?? '').trim().isNotEmpty) return meta!.artist.trim();
      return DriveUtils.getTrackMeta(_albumTracks.first)['artist'] ??
          'Unknown Artist';
    }
    return 'Unknown Artist';
  }

  String _albumYearForArtwork(Map<String, String> album) {
    final id = album['id'] ?? '';
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

    if (_nowPlaying.currentCoverUrl == currentCover ||
        (_viewingAlbum != null && (_viewingAlbum!['id'] ?? '') == albumId)) {
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
    final albumId = album['id'] ?? '';
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
      if ((savedAlbum['id'] ?? '') == albumId) {
        revert(savedAlbum);
        break;
      }
    }
    if (_viewingAlbum != null && (_viewingAlbum!['id'] ?? '') == albumId) {
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
                child: GestureDetector(
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

    final albumId = album['id'] ?? '';
    final brain = _libraryBrain[albumId] ?? const <String, String>{};
    final albumName = brain['displayName'] ??
        album['displayName'] ??
        album['name'] ??
        'Unknown Album';
    final artist = _cleanBrainValue(brain['artist']).isNotEmpty
        ? brain['artist']!
        : _cleanBrainValue(album['artist']).isNotEmpty
            ? album['artist']!
            : _albumTracks.isNotEmpty
                ? DriveUtils.getTrackMeta(_albumTracks.first)['artist'] ??
                    'Unknown Artist'
                : 'Unknown Artist';

    _showSuccess('Checking embedded cover first...');

    final embedded = await _findEmbeddedCoverForAlbum(album);
    if (embedded != null && embedded.isNotEmpty) {
      setState(() {
        album['cover'] = embedded;
        for (final savedAlbum in _albums) {
          if (savedAlbum['id'] == album['id']) {
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
        if (savedAlbum['id'] == album['id']) {
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

  void _showSuccess(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: GoogleFonts.inter(
                color: Colors.black, fontWeight: FontWeight.w900)),
        backgroundColor: _accentDefault,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

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
      final caa = await _coverFromCoverArtArchive(albumName, artistName);
      if (caa != null && caa.isNotEmpty) return caa;
    } catch (_) {}

    try {
      final itunes = await _coverFromITunes(albumName, artistName);
      if (itunes != null && itunes.isNotEmpty) return itunes;
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

    try {
      final provider = _coverProvider(coverUrl);
      if (provider == null) throw Exception('Missing cover provider');

      // Sample entire image to capture edge colors
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        maximumColorCount: 40,
        region: null, // Full image sampling
      );

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
    }
  }

  // ── Album View Logic ──────────────────────────────────────────────────────
  Future<void> _openAlbum(Map<String, String> album) async {
    final albumId = album['id'] ?? album['name'] ?? '';
    final albumName = album['name'] ?? 'Unknown Album';
    final cachedTracks = _albumTracksCache[albumId];
    final sortedCachedTracks =
        cachedTracks == null ? null : _sortTracksForAlbum(cachedTracks);
    final cachedColors = _albumColorCache[albumId];

    setState(() {
      _viewingAlbum = album;
      _loadingAlbum = sortedCachedTracks == null;
      _albumTracks = sortedCachedTracks ?? <drive.File>[];
      _albumMetadataLoading = false;
      _albumMetadataDone = 0;
      _albumMetadataTotal = 0;
      _currentDynamicColors = cachedColors ?? getAlbumGradient(albumName);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _extractAlbumColors(
        album['cover'] ?? '',
        albumName,
        cacheKey: albumId,
      );
    });

    if (sortedCachedTracks != null) {
      _applyFirstCachedEmbeddedCover(album, sortedCachedTracks);
      _indexAlbumFromTracks(album, sortedCachedTracks);
      _indexTracksForAlbum(album, sortedCachedTracks);
      return;
    }

    try {
      final headers = await _user!.authHeaders;
      final api = drive.DriveApi(GoogleAuthClient(headers));
      final tracks =
          _sortTracksForAlbum(await _fetchTracksForAlbumRecord(api, album));

      if (!mounted) return;

      _albumTracksCache[albumId] = tracks;
      _applyFirstCachedEmbeddedCover(album, tracks);
      _indexAlbumFromTracks(album, tracks, save: false);
      _indexTracksForAlbum(album, tracks);
      _saveLibraryBrain();
      _persistAlbums();

      setState(() {
        _albumTracks = tracks;
        _loadingAlbum = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _precacheTrackArtwork(album['cover'] ?? '');
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
    if (coverUrl.isEmpty) return;
    final provider = _coverProvider(coverUrl);
    if (provider != null) {
      precacheImage(provider, context).catchError((_) {});
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
  Future<void> _handleTrackCompleted() async {
    if (_changingTrack || _handlingTrackCompletion) return;

    _handlingTrackCompletion = true;

    try {
      if (_nowPlaying.repeatOne) {
        await _player.seek(Duration.zero);
        await _player.play();
        return;
      }

      await _playNext(autoAdvance: true);
    } catch (e) {
      _showError('Could not continue playback: $e');
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      _handlingTrackCompletion = false;
    }
  }

  String _trackKey(drive.File file) {
    final id = DriveUtils.effectiveId(file);
    if (id != null && id.trim().isNotEmpty) return id.trim();
    return (file.name ?? '').trim().toLowerCase();
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
  }) async {
    _ensureAudioServicePlayerAttached();
    final fileId = DriveUtils.effectiveId(file);
    if (fileId == null || _user == null) return;

    final requestSerial = ++_playRequestSerial;
    final activeQueue = _cleanPlaybackQueue(queue, file);
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

      final authHeaders = await _user!.authHeaders;
      if (requestSerial != _playRequestSerial) return;

      String token = '';
      final bearer =
          authHeaders['Authorization'] ?? authHeaders['authorization'] ?? '';
      if (bearer.startsWith('Bearer ')) token = bearer.substring(7);

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
      _loadMetadataFor(activeFile, token, albumRecord: _viewingAlbum);

      final source = DriveAudioSource(activeFileId, token);
      debugPrint(
        'Infame _playSong loading ${source.runtimeType} '
        'id=$activeFileId name=${activeFile.name}',
      );
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

      final loadedDuration = _player.duration;
      final activeKey = _trackKey(activeFile);
      if (activeKey.isNotEmpty &&
          loadedDuration != null &&
          loadedDuration.inSeconds > 0) {
        _knownTrackDurations[activeKey] = loadedDuration;
        final durationMs = loadedDuration.inMilliseconds;
        _knownTrackDurationsMs[activeKey] = durationMs;

        // Update library track index if exists
        if (_libraryTrackIndex.containsKey(activeKey)) {
          _libraryTrackIndex[activeKey]!['durationMs'] = durationMs.toString();
          _saveLibraryTrackIndex();
        }
        _saveKnownTrackDurations();
      }

      await _player.play();
      await Future<void>.delayed(Duration.zero);
      _infameAudioHandler?.syncPlaybackStateFromPlayer();
      _syncAudioServicePlaybackState();
      _recordPlay(activeFile, coverUrl: resolvedCoverUrl);
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

  String _formatDurationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes
        .remainder(60)
        .toString()
        .padLeft(hours > 0 ? 2 : 1, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  String _trackDurationLabel(drive.File file) {
    final key = _trackKey(file);
    if (key.isEmpty) return '';

    // Check persistent cache first
    final durationMs = _knownTrackDurationsMs[key];
    if (durationMs != null && durationMs > 0) {
      return _formatDurationMs(durationMs);
    }

    // Fall back to in-memory cache
    final duration = _knownTrackDurations[key];
    if (duration == null || duration.inSeconds <= 0) return '';
    return _formatDurationLabel(duration);
  }

  void _addTracksPlayNext(List<drive.File> tracks) {
    _enqueueTracks(tracks, insertAfterCurrent: true);
  }

  void _addTracksToQueueEnd(List<drive.File> tracks) {
    _enqueueTracks(tracks, insertAfterCurrent: true);
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
    _nowPlaying.refresh();
    if (mounted) setState(() {});
    _showSuccess(insertAfterCurrent ? 'Added next' : 'Added to queue.');
  }

  void _showError(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: _textPri)),
        backgroundColor: _pink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showCoverZoom(String heroTag, String coverUrl, List<Color> gradient) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.86),
        pageBuilder: (BuildContext context, _, __) {
          return GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Center(
              child: Hero(
                tag: heroTag,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.86,
                  height: MediaQuery.of(context).size.width * 0.86,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kArtworkRadius),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: gradient[0].withOpacity(0.50),
                        blurRadius: 45,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: coverUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(kArtworkRadius),
                          child: _coverImage(coverUrl,
                              fit: BoxFit.cover,
                              cacheSize: _coverLargeDecodeSize),
                        )
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return _buildSignInScreen();
    }

    final accent = _appAccent;
    final bgColor = _isDarkMode ? _darkBg : _lightBg;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: bgColor,
      extendBody: false,
      body: Stack(
        children: [
          Positioned.fill(child: _NeonBlobBackground(isDarkMode: _isDarkMode)),
          SafeArea(
            bottom: false,
            child: _viewingAlbum != null
                ? _buildAlbumView()
                : PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    itemCount: 3,
                    onPageChanged: (index) {
                      setState(() {
                        _navIndex = index;
                        _viewingAlbum = null;
                        _currentDynamicColors =
                            List<Color>.from(_defaultDynamicColors);
                      });
                    },
                    itemBuilder: (context, index) {
                      switch (index) {
                        case 0:
                          return _KeepAlivePage(
                            key: const PageStorageKey('home_keep_alive'),
                            builder: (_) => buildHomeTab(),
                          );
                        case 1:
                          return _KeepAlivePage(
                            key: const PageStorageKey('now_playing_keep_alive'),
                            builder: (_) => _buildNowPlayingTab(),
                          );
                        case 2:
                          return _KeepAlivePage(
                            key: const PageStorageKey('library_keep_alive'),
                            builder: (_) => buildLibraryTab(),
                          );
                        default:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
          ),
          ListenableBuilder(
            listenable: _nowPlaying,
            builder: (context, _) {
              final hasCurrentTrack = _nowPlaying.track != null;
              if (!hasCurrentTrack || _navIndex == 1) {
                return const SizedBox.shrink();
              }
              return Positioned(
                bottom: 88 + safeBottom,
                left: 16,
                right: 16,
                child: _PlayerFloatingBar(
                  player: _player,
                  onNext: () => _playNext(),
                  onPrev: () => _playPrev(),
                  onOpenNowPlaying: () => _selectRootTab(1),
                  onPlayFromQueue: (track, index) => _playSong(
                    track,
                    queue: _nowPlaying.queue,
                    idx: index,
                    coverUrl: _resolveCurrentTrackCover(
                      track,
                      queue: _nowPlaying.queue,
                      idx: index,
                      fallbackCoverUrl: _nowPlaying.currentCoverUrl,
                    ),
                    colors: _currentDynamicColors,
                  ),
                  isDarkMode: _isDarkMode,
                  knownTrackDurationsMs: _knownTrackDurationsMs,
                  knownTrackDurations: _knownTrackDurations,
                ),
              );
            },
          ),
          Positioned(
            bottom: 18 + safeBottom,
            left: 14,
            right: 14,
            child: SafeArea(
              top: false,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    height: 64,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isDarkMode
                          ? (_darkBg).withOpacity(0.45)
                          : _lightGlassBase.withOpacity(0.86),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: _isDarkMode
                            ? _neonPurple.withOpacity(0.25)
                            : _lightAccentPink.withOpacity(0.22),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _isDarkMode
                              ? _neonPurple.withOpacity(0.15)
                              : _lightAccentPink.withOpacity(0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: _NavBarItem(
                            icon: Icons.home_rounded,
                            label: 'Home',
                            isDarkMode: _isDarkMode,
                            isSelected: _navIndex == 0,
                            onTap: () => _selectRootTab(0),
                          ),
                        ),
                        Expanded(
                          child: _NavBarItem(
                            icon: Icons.album_rounded,
                            label: 'Now Playing',
                            isDarkMode: _isDarkMode,
                            isSelected: _navIndex == 1,
                            onTap: () => _selectRootTab(1),
                          ),
                        ),
                        Expanded(
                          child: _NavBarItem(
                            icon: Icons.library_music_rounded,
                            label: 'Library',
                            isDarkMode: _isDarkMode,
                            isSelected: _navIndex == 2,
                            onTap: () => _selectRootTab(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInScreen() {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildAppBackground(
              [_pink, _accentDefault, _purple, _cyan],
              signIn: true,
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildGradientText('INFAME', size: 52, spacing: 4),
                  const SizedBox(height: 12),
                  Text(
                    'Stream your Google Drive library with a proper music-player feel.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: _textSub,
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 42),
                  _signingIn
                      ? const CircularProgressIndicator(color: _pink)
                      : GestureDetector(
                          onTap: _signIn,
                          child: GlassyContainer(
                            radius: 30,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 30, vertical: 16),
                            customBorder: _pink.withOpacity(0.35),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.cloud_rounded,
                                    color: _accentDefault),
                                const SizedBox(width: 10),
                                Text(
                                  'Connect Google Drive',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Album View ────────────────────────────────────────────────────────────
  Widget _buildAlbumView() {
    final albumId = _viewingAlbum!['id'] ?? '';
    final brain = _libraryBrain[albumId] ?? <String, String>{};
    final rawName = _viewingAlbum!['name'] ?? 'Unknown Album';
    final albumName =
        brain['displayName'] ?? _viewingAlbum!['displayName'] ?? rawName;
    final artist = brain['artist'] ?? _viewingAlbum!['artist'] ?? '';
    final year = brain['year'] ?? _viewingAlbum!['year'] ?? '';
    final genre = brain['genre'] ?? _viewingAlbum!['genre'] ?? '';
    final coverUrl = _viewingAlbum!['cover'] ?? brain['cover'] ?? '';
    final colors = _safeColors(_currentDynamicColors);
    final glowColor = _isDarkMode ? _neonPurple : _neonMagenta;
    final fallbackGradient = getAlbumGradient(albumName);
    final albumDetails = [
      if (artist.trim().isNotEmpty) artist.trim(),
      if (year.trim().isNotEmpty) year.trim(),
      if (genre.trim().isNotEmpty) genre.trim(),
    ].join(' • ');

    // Calculate enhanced metadata from tracks
    String enhancedAlbumInfo = '';
    if (_albumTracks.isNotEmpty) {
      final infoParts = <String>[];

      // Artist from metadata or brain
      String metadataArtist = '';
      for (final track in _albumTracks) {
        final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
        if (meta != null && meta.artist.isNotEmpty) {
          metadataArtist = meta.artist;
          break;
        }
      }
      final displayArtist = metadataArtist.isNotEmpty ? metadataArtist : artist;
      if (displayArtist.trim().isNotEmpty) infoParts.add(displayArtist.trim());

      // Year from metadata or brain
      String metadataYear = '';
      for (final track in _albumTracks) {
        final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
        if (meta != null) {
          if (meta.year != null && meta.year!.length >= 4) {
            final yearMatch = RegExp(r'\d{4}').firstMatch(meta.year!);
            if (yearMatch != null) {
              metadataYear = yearMatch.group(0)!;
              break;
            }
          }
        }
      }
      final displayYear = metadataYear.isNotEmpty ? metadataYear : year;
      if (displayYear.trim().isNotEmpty) infoParts.add(displayYear.trim());

      // Genre from metadata or brain
      String metadataGenre = '';
      for (final track in _albumTracks) {
        final meta = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
        if (meta != null && meta.genre != null && meta.genre!.isNotEmpty) {
          metadataGenre = meta.genre!;
          break;
        }
      }
      final displayGenre = metadataGenre.isNotEmpty ? metadataGenre : genre;
      if (displayGenre.trim().isNotEmpty) infoParts.add(displayGenre.trim());

      // Track count
      final trackCount = _albumTracks.length;
      infoParts.add(trackCount == 1 ? '1 track' : '$trackCount tracks');

      enhancedAlbumInfo = infoParts.join(' • ');
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          pinned: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _textPri),
            onPressed: _closeAlbum,
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, color: _textPri),
              color: const Color(0xFF1A1A22),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              onSelected: (value) {
                if (value == 'load_metadata') {
                  _loadMetadataForCurrentAlbum();
                } else if (value == 'choose_artwork') {
                  _showArtworkSourcePicker();
                } else if (value == 'refresh_cover') {
                  _refreshCurrentAlbumCover();
                } else if (value == 'remove_album') {
                  _removeCurrentAlbumFromLibrary();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'load_metadata',
                  enabled: !_albumMetadataLoading && !_loadingMetadata,
                  child: Row(
                    children: [
                      Icon(Icons.tag_rounded, color: glowColor, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        _albumMetadataLoading
                            ? 'Loading metadata...'
                            : 'Load metadata for album',
                        style: GoogleFonts.inter(
                          color: _textPri,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'choose_artwork',
                  child: Row(
                    children: [
                      Icon(Icons.image_search_rounded,
                          color: glowColor, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'Choose artwork source',
                        style: GoogleFonts.inter(
                          color: _textPri,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'remove_album',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'Remove from app library',
                        style: GoogleFonts.inter(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () =>
                      _showCoverZoom('album_hero_$albumName', coverUrl, colors),
                  child: Hero(
                    tag: 'album_hero_$albumName',
                    child: Container(
                      width: 154,
                      height: 154,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(kArtworkRadius),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [glowColor, glowColor.withOpacity(0.7)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: glowColor.withOpacity(0.42),
                            blurRadius: 34,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: coverUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(kArtworkRadius),
                              child: _coverImage(
                                coverUrl,
                                fit: BoxFit.cover,
                                cacheSize: _coverLargeDecodeSize,
                                errorBuilder: (_, __, ___) =>
                                    _AlbumFallbackCover(
                                  name: albumName,
                                  colors: fallbackGradient,
                                  radius: kArtworkRadius,
                                ),
                              ),
                            )
                          : _AlbumFallbackCover(
                              name: albumName,
                              colors: fallbackGradient,
                              radius: kArtworkRadius,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  albumName,
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: _isDarkMode ? Colors.white : _neonMagenta,
                    height: 1.04,
                    letterSpacing: -1.0,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  enhancedAlbumInfo.isNotEmpty
                      ? enhancedAlbumInfo
                      : (albumDetails.isNotEmpty
                          ? albumDetails
                          : 'Album • Drive Library'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: _isDarkMode
                        ? const Color(0xFFFFB6E1).withOpacity(0.9)
                        : Colors.black.withOpacity(0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _AlbumActionButton(
                        icon: Icons.play_arrow_rounded,
                        label: 'Play',
                        accent: _isDarkMode ? Colors.white : _neonMagenta,
                        primary: true,
                        onTap: () => _playCurrentAlbum(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AlbumActionButton(
                        icon: Icons.shuffle_rounded,
                        label: 'Shuffle',
                        accent: _isDarkMode ? Colors.white : _neonMagenta,
                        onTap: () => _playCurrentAlbum(shuffle: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_albumMetadataLoading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: glowColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Loading album metadata $_albumMetadataDone/$_albumMetadataTotal',
                              style: GoogleFonts.inter(
                                color: _textSub,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _albumMetadataTotal > 0
                                ? (_albumMetadataDone / _albumMetadataTotal)
                                    .clamp(0.0, 1.0)
                                : null,
                            minHeight: 4,
                            backgroundColor: Colors.white.withOpacity(0.13),
                            valueColor:
                                AlwaysStoppedAnimation<Color>(glowColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        if (_loadingAlbum)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator(color: _pink)),
          )
        else if (_albumTracks.isEmpty)
          const SliverFillRemaining(
            child: Center(
              child: Text('No tracks found in this album.',
                  style: TextStyle(color: _textSub)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((ctx, i) {
                return _TrackGlassTile(
                  key: ValueKey(DriveUtils.effectiveId(_albumTracks[i])),
                  track: _albumTracks[i],
                  queue: _albumTracks,
                  index: i,
                  coverUrl: coverUrl,
                  durationText: _trackDurationLabel(_albumTracks[i]),
                  isLiked: _isTrackLiked(_albumTracks[i]),
                  onTap: () => _playSong(
                    _albumTracks[i],
                    queue: _albumTracks,
                    idx: i,
                    coverUrl: coverUrl,
                    colors: colors,
                  ),
                  onToggleLiked: () => _toggleLikedTrack(_albumTracks[i]),
                  onPlayNext: () => _addTracksPlayNext([_albumTracks[i]]),
                  onAddToQueue: () => _addTracksToQueueEnd([_albumTracks[i]]),
                  isDarkMode: _isDarkMode,
                );
              }, childCount: _albumTracks.length),
            ),
          ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 170),
        ),
      ],
    );
  }

  // ── Home Tab ──────────────────────────────────────────────────────────────

  List<Widget> _homeAlbumShelfSlivers({
    required String title,
    required String subtitle,
    required List<Map<String, String>> items,
    double bottomPadding = 22,
  }) {
    if (items.isEmpty) return const <Widget>[];

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        sliver: SliverToBoxAdapter(
          child: _HomeSectionHeader(title: title, subtitle: subtitle),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding),
        sliver: SliverToBoxAdapter(
          child: SizedBox(
            height: 214,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final info = items[i];
                return _HomeAlbumCard(
                  info: info,
                  onTap: () => _openAlbumByBrain(info),
                  isDarkMode: _isDarkMode,
                );
              },
            ),
          ),
        ),
      ),
    ];
  }

  // ── Library Tab ───────────────────────────────────────────────────────────

  // ── Search Tab ────────────────────────────────────────────────────────────

  Widget _buildNowPlayingTab() {
    return ListenableBuilder(
      listenable: _nowPlaying,
      builder: (context, _) {
        final track = _nowPlaying.track;
        if (track == null) {
          final textColor = _isDarkMode ? _darkTextPri : _lightTextPri;
          final subTextColor = _isDarkMode ? _darkTextSub : _lightTextSub;
          final accent = _isDarkMode ? _neonPurple : _lightAccentPink;
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.music_off_rounded, size: 52, color: accent),
                  const SizedBox(height: 16),
                  Text(
                    'Nothing playing',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick something from Home or Library',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: subTextColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final trackId = DriveUtils.effectiveId(track) ?? '';
        final record = trackId.isEmpty ? null : _libraryTrackIndex[trackId];
        final albumName =
            ((record?['album'] ?? record?['albumName'] ?? '')).trim();

        return _FullScreenPlayerSheet(
          player: _player,
          onNext: () => _playNext(),
          onPrev: () => _playPrev(),
          onPlayFromQueue: (queueTrack, index) => _playSong(
            queueTrack,
            queue: _nowPlaying.queue,
            idx: index,
            coverUrl: _resolveCurrentTrackCover(
              queueTrack,
              queue: _nowPlaying.queue,
              idx: index,
              fallbackCoverUrl: _nowPlaying.currentCoverUrl,
            ),
            colors: _currentDynamicColors,
          ),
          isDarkMode: _isDarkMode,
          albumName: albumName,
          isLiked: _isTrackLiked(track),
          onToggleLiked: () => _toggleLikedTrack(track),
          knownTrackDurationsMs: _knownTrackDurationsMs,
          knownTrackDurations: _knownTrackDurations,
          embedded: true,
        );
      },
    );
  }

  Widget _buildSearchTab() {
    final colors = _safeColors(_currentDynamicColors);
    final query = _searchQuery.trim().toLowerCase();
    final selectedMode = _searchViewMode;
    final bgColor = _isDarkMode ? _darkBg : _lightBg;
    final albumsCache = _cachedVisibleAlbumsForQuery(query);
    final songsCache = _cachedVisibleSongsForQuery(query);
    final likedSongsCache = _cachedVisibleSongsForQuery(query, likedOnly: true);
    final artistsCache = _cachedVisibleArtistsForQuery(query);
    final albums = albumsCache;
    final songs = songsCache.records;
    final songFiles = songsCache.files;
    final likedSongs = likedSongsCache.records;
    final likedSongFiles = likedSongsCache.files;
    final artists = artistsCache.grouped;
    final visibleArtists = artistsCache.names;
    final showAll = selectedMode == 'all';
    final showAlbums = showAll || selectedMode == 'albums';
    final showArtists = showAll || selectedMode == 'artists';
    final showSongs = showAll || selectedMode == 'songs';
    final showLiked = showAll || selectedMode == 'liked';
    final hasVisibleResults = showAll
        ? albums.isNotEmpty ||
            visibleArtists.isNotEmpty ||
            songs.isNotEmpty ||
            likedSongs.isNotEmpty
        : showAlbums
            ? albums.isNotEmpty
            : showArtists
                ? visibleArtists.isNotEmpty
                : showSongs
                    ? songs.isNotEmpty
                    : likedSongs.isNotEmpty;

    debugPrint(
        '[Search] results rebuilt: category=$selectedMode count=${showAll ? (albums.length + visibleArtists.length + songs.length + likedSongs.length) : (showAlbums ? albums.length : showArtists ? visibleArtists.length : showSongs ? songs.length : likedSongs.length)}');

    return RepaintBoundary(
      child: Container(
        color: bgColor,
        child: CustomScrollView(
          key: const PageStorageKey('search_tab_scroll'),
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildGradientText('Search',
                              size: 34, spacing: -1.4),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Search songs, albums, artists and liked tracks.',
                      style: GoogleFonts.inter(
                        color: _textSub,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildLibrarySearchBar(
                      colors,
                      hintText: 'Search Nas, albums, artists...',
                      controller: _searchSearchController,
                      onChanged: (value) {
                        debugPrint('[Search] query changed: "$value"');
                        setState(() => _searchQuery = value);
                      },
                      query: _searchQuery,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SearchModePill(
                          label: 'All',
                          isSelected: selectedMode == 'all',
                          isDarkMode: _isDarkMode,
                          onTap: () {
                            debugPrint('[Search] category selected: all');
                            setState(() => _searchViewMode = 'all');
                          },
                        ),
                        _SearchModePill(
                          label: 'Albums',
                          isSelected: selectedMode == 'albums',
                          isDarkMode: _isDarkMode,
                          onTap: () {
                            debugPrint('[Search] category selected: albums');
                            setState(() => _searchViewMode = 'albums');
                          },
                        ),
                        _SearchModePill(
                          label: 'Artists',
                          isSelected: selectedMode == 'artists',
                          isDarkMode: _isDarkMode,
                          onTap: () {
                            debugPrint('[Search] category selected: artists');
                            setState(() => _searchViewMode = 'artists');
                          },
                        ),
                        _SearchModePill(
                          label: 'Songs',
                          isSelected: selectedMode == 'songs',
                          isDarkMode: _isDarkMode,
                          onTap: () {
                            debugPrint('[Search] category selected: songs');
                            setState(() => _searchViewMode = 'songs');
                          },
                        ),
                        if (_likedTrackKeys.isNotEmpty)
                          _SearchModePill(
                            label: 'Liked',
                            isSelected: selectedMode == 'liked',
                            isDarkMode: _isDarkMode,
                            onTap: () {
                              debugPrint('[Search] category selected: liked');
                              setState(() => _searchViewMode = 'liked');
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (!hasVisibleResults)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'No results found.',
                        style: GoogleFonts.inter(
                          color: _textPri,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () {
                          _searchSearchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: Text(
                          'Clear search',
                          style: GoogleFonts.inter(
                            color: colors[1],
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              if (showArtists && visibleArtists.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Artists',
                      style: GoogleFonts.inter(
                        color: _isDarkMode ? Colors.white : _textPri,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((ctx, i) {
                      final artist = visibleArtists[i];
                      final records =
                          artists[artist] ?? const <Map<String, String>>[];
                      final albumSet = <String>{};
                      for (final record in records) {
                        final album = record['albumName'] ?? '';
                        if (album.isNotEmpty) albumSet.add(album);
                      }

                      final artistAlbums = _albums.where((album) {
                        final albumArtist = _canonicalArtistName(
                          albumArtist: _libraryAlbumArtist(album),
                          trackArtist: _libraryBrain[album['id'] ?? '']
                                  ?['artist'] ??
                              album['artist'] ??
                              '',
                          albumName:
                              album['name'] ?? album['displayName'] ?? '',
                        );
                        return albumArtist.toLowerCase() ==
                            artist.toLowerCase();
                      }).map((album) {
                        final merged = Map<String, String>.from(album);
                        final brain = _libraryBrain[album['id'] ?? ''];
                        if (brain != null) merged.addAll(brain);
                        merged['artist'] = _libraryAlbumArtist(album);
                        merged['displayName'] = _libraryAlbumTitle(album);
                        return merged;
                      }).toList();

                      return GestureDetector(
                        key: ValueKey('search-artist-$artist'),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _ArtistDetailPage(
                                artistName: artist,
                                artistImageUrl: _artistImageCache[
                                        _artistImageCacheKey(artist)] ??
                                    '',
                                artistAlbums: artistAlbums,
                                artistTrackRecords: records,
                                isDarkMode: _isDarkMode,
                                accentColors: _safeColors(colors),
                                onOpenAlbum: _openAlbum,
                                onPlayTrack: (file,
                                    {queue, idx, coverUrl, colors}) {
                                  return _playSong(
                                    file,
                                    queue: queue,
                                    idx: idx,
                                    coverUrl: coverUrl,
                                    colors: colors,
                                  );
                                },
                              ),
                            ),
                          );
                        },
                        behavior: HitTestBehavior.opaque,
                        child: GlassyContainer(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          radius: 20,
                          child: Row(
                            children: [
                              _ArtistAvatar(
                                artistName: artist,
                                imageUrl: _artistImageCache[
                                    _artistImageCacheKey(artist)],
                                colors: colors,
                                size: 56,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: _textPri,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${records.length} songs • ${albumSet.length} albums',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: _textSub,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: _textSub),
                            ],
                          ),
                        ),
                      );
                    }, childCount: visibleArtists.length),
                  ),
                ),
              ],
              if (showAlbums && albums.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Albums',
                      style: GoogleFonts.inter(
                        color: _isDarkMode ? Colors.white : _textPri,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((ctx, i) {
                      final album = albums[i];
                      final brain = _libraryBrain[album['id'] ?? ''];
                      final name = _libraryAlbumTitle(album);
                      final artist = _libraryAlbumArtist(album);
                      final year = brain?['year'] ?? album['year'] ?? '';
                      final genre = brain?['genre'] ?? album['genre'] ?? '';
                      final coverUrl = album['cover'] ?? brain?['cover'] ?? '';
                      final gradient = getAlbumGradient(name);

                      return GestureDetector(
                        key: ValueKey(
                            'search-album-${album['id'] ?? album['name']}'),
                        onTap: () => _openAlbum(album),
                        behavior: HitTestBehavior.opaque,
                        child: GlassyContainer(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          radius: 20,
                          child: Row(
                            children: [
                              Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(kArtworkRadius),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: gradient,
                                  ),
                                ),
                                child: coverUrl.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                            kArtworkRadius),
                                        child: _coverImage(
                                          coverUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _AlbumFallbackCover(
                                            name: name,
                                            colors: gradient,
                                            radius: kArtworkRadius,
                                            small: true,
                                          ),
                                        ),
                                      )
                                    : _AlbumFallbackCover(
                                        name: name,
                                        colors: gradient,
                                        radius: kArtworkRadius,
                                        small: true,
                                      ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: _textPri,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      artist.isNotEmpty
                                          ? artist
                                          : year.isNotEmpty
                                              ? year
                                              : genre.isNotEmpty
                                                  ? genre
                                                  : 'Album • Drive',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: _textSub,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: _textSub),
                            ],
                          ),
                        ),
                      );
                    }, childCount: albums.length),
                  ),
                ),
              ],
              if (showSongs && songs.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Songs',
                      style: GoogleFonts.inter(
                        color: _isDarkMode ? Colors.white : _textPri,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 18),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((ctx, i) {
                      final record = songs[i];
                      final file = songFiles[i];
                      final coverUrl = record['albumCover'] ?? '';
                      return _TrackGlassTile(
                        key: ValueKey('search-song-${record['id']}'),
                        track: file,
                        queue: songFiles,
                        index: i,
                        coverUrl: coverUrl,
                        isLiked: _isTrackLiked(file),
                        onTap: () {
                          unawaited(_playSong(
                            file,
                            queue: songFiles,
                            idx: i,
                            coverUrl: coverUrl,
                            colors: _currentDynamicColors,
                          ));
                        },
                        onToggleLiked: () => _toggleLikedTrack(file),
                        onPlayNext: () => _addTracksPlayNext([file]),
                        onAddToQueue: () => _addTracksToQueueEnd([file]),
                        isDarkMode: _isDarkMode,
                      );
                    }, childCount: songs.length),
                  ),
                ),
              ],
              if (showLiked && likedSongs.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Liked',
                      style: GoogleFonts.inter(
                        color: _isDarkMode ? Colors.white : _textPri,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 18),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((ctx, i) {
                      final record = likedSongs[i];
                      final file = likedSongFiles[i];
                      final coverUrl = record['albumCover'] ?? '';

                      return _TrackGlassTile(
                        key: ValueKey('search-liked-${record['id']}'),
                        track: file,
                        queue: [file],
                        index: 0,
                        coverUrl: coverUrl,
                        isLiked: true,
                        onTap: () {
                          unawaited(_playSong(
                            file,
                            queue: [file],
                            idx: 0,
                            coverUrl: coverUrl,
                            colors: _currentDynamicColors,
                          ));
                        },
                        onToggleLiked: () => _toggleLikedTrack(file),
                        onPlayNext: () => _addTracksPlayNext([file]),
                        onAddToQueue: () => _addTracksToQueueEnd([file]),
                        isDarkMode: _isDarkMode,
                      );
                    }, childCount: likedSongs.length),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 170)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAppBackground(List<Color> colors, {bool signIn = false}) {
    final safe = _safeColors(colors);
    final glowOpacity = _glassMode == glassModePerformance ? 0.52 : 0.80;

    return Container(
      color: _bg,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF17171D),
                    Color.alphaBlend(safe[3].withOpacity(0.22), _bg),
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),
          if (_showBackgroundGlow) ...[
            Positioned(
                top: signIn ? -120 : -130,
                left: -130,
                child: _buildBlob(safe[0], 360 * glowOpacity)),
            Positioned(
                top: signIn ? 100 : 46,
                right: -150,
                child: _buildBlob(safe[2], 310 * glowOpacity)),
            Positioned(
                bottom: 90,
                right: -110,
                child: _buildBlob(safe[1], 330 * glowOpacity)),
            Positioned(
                bottom: -140,
                left: -130,
                child: _buildBlob(safe[3], 320 * glowOpacity)),
            if (_glassMode == glassModePretty)
              Positioned(
                  top: 260,
                  left: 36,
                  child: _buildBlob(safe[1].withOpacity(0.8), 190)),
          ],
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(signIn ? 0.08 : 0.14),
                    Colors.black.withOpacity(0.22),
                    Colors.black.withOpacity(0.50),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlob(Color color, double size) {
    final opacity = _glassMode == glassModePerformance ? 0.18 : 0.28;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(opacity),
            color.withOpacity(opacity * 0.42),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }

  Widget _buildGradientText(String text,
      {required double size, double spacing = 0}) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w900,
        color: _textPri,
        letterSpacing: spacing,
      ),
    );
  }
}
