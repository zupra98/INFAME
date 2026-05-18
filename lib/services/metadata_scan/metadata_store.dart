part of '../../main.dart';

// â”€â”€â”€ Embedded Metadata Cache + Fast Tag Reader â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class TrackMetadataStore extends ChangeNotifier {
  static const String _prefsKey = 'musix_track_metadata_cache_v2';
  final Map<String, TrackMetadata> _cache = {};
  bool _loaded = false;

  int get count => _cache.length;

  Map<String, int> get cachedDurationsMs {
    final result = <String, int>{};
    _cache.forEach((key, value) {
      final durationMs = value.durationMs;
      if (durationMs != null && durationMs > 0 && durationMs < 86400000) {
        result[key] = durationMs;
      }
    });
    return result;
  }

  TrackMetadata? peek(drive.File file) {
    final id = DriveUtils.effectiveId(file);
    if (id == null) return null;
    return _cache[id];
  }

  TrackMetadata? peekFresh(drive.File file) {
    final cached = peek(file);
    if (cached == null) return null;
    return cached.matchesFile(file) ? cached : null;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = json.decode(raw);
      if (decoded is! Map) return;

      _cache.clear();
      decoded.forEach((key, value) {
        if (key is String && value is Map) {
          _cache[key] = TrackMetadata.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });

      notifyListeners();
    } catch (_) {
      return;
    }
  }

  Future<void> reload() async {
    _loaded = false;
    _cache.clear();
    await load();
  }

  Future<void> put(drive.File file, TrackMetadata metadata) async {
    final id = DriveUtils.effectiveId(file);
    if (id == null) return;

    _cache[id] = metadata;
    notifyListeners();
    await persistNow();
  }

  void putMemory(drive.File file, TrackMetadata metadata) {
    final id = DriveUtils.effectiveId(file);
    if (id == null) return;
    _cache[id] = metadata;
  }

  Future<void> clear() async {
    _cache.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  Future<void> persistNow() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{};

    _cache.forEach((key, value) {
      payload[key] = value.toJson();
    });

    await prefs.setString(_prefsKey, json.encode(payload));
  }
}

final _metaStore = TrackMetadataStore();

const String _embeddedCoverScanFingerprintKey = 'embeddedCoverScanFingerprint';

String _cleanBackgroundValue(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty ||
      v.toLowerCase() == 'unknown' ||
      v.toLowerCase() == 'unknown artist') {
    return '';
  }
  return v;
}

String _albumCoverScanKey(Map<String, String> album) {
  return _albumCacheKey(album, source: 'cover_scan');
}

String _albumCoverScanFingerprint(Map<String, String> album) {
  final id = _albumCoverScanKey(album);
  final title = _cleanBackgroundValue(album['displayName'] ?? album['name']);
  final artist = _cleanBackgroundValue(album['artist']);
  final trackCount = _cleanBackgroundValue(album['trackCount']);
  return '$id|${artist.toLowerCase()}|${title.toLowerCase()}|$trackCount';
}

String _resolvedAlbumCoverBackground(
  Map<String, String> album,
  List<drive.File> tracks,
) {
  final direct = _sanitizeCoverSource(
    album['cover'] ?? album['coverUrl'] ?? album['artwork'] ?? '',
  );
  if (direct.isNotEmpty) return direct;

  for (final track in tracks) {
    final cached = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
    final cover = _sanitizeCoverSource(cached?.coverPath);
    if (cover.isNotEmpty) return cover;
  }

  return '';
}
