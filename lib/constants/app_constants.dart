part of '../main.dart';

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

// â”€â”€â”€ 4-Color Deterministic Gradient Generator â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

// â”€â”€â”€ App Root â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

// â”€â”€â”€ Now-Playing State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

final _nowPlaying = NowPlaying();

const String _libraryTrackIndexKey = 'library_track_index';
const String _knownTrackDurationsKey = _knownTrackDurationsPrefsKey;
