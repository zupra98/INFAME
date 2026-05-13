part of '../main.dart';

// ─── Embedded Metadata Cache + Fast Tag Reader ─────────────────────────────


  
class TrackMetadataStore extends ChangeNotifier {
  static const String _prefsKey = 'musix_track_metadata_cache_v2';
  final Map<String, TrackMetadata> _cache = {};
  bool _loaded = false;

  int get count => _cache.length;

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
          _cache[key] = TrackMetadata.fromJson(Map<String, dynamic>.from(value));
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

class FastTagReader {
  static const int firstChunk = 1024 * 1024;
  static const int largerChunk = 2 * 1024 * 1024;
  static const int maxTagChunk = 4 * 1024 * 1024;

  static Future<TrackReadResult?> read({
    required drive.File file,
    required String token,
    bool readCover = true,
  }) async {
    final id = DriveUtils.effectiveId(file);
    if (id == null) return null;

    final name = (file.name ?? '').toLowerCase();

    if (name.endsWith('.mp3')) {
      return _readMp3(id, token, readCover: readCover);
    }

    if (name.endsWith('.flac')) {
      return _readFlac(id, token, readCover: readCover);
    }

    if (name.endsWith('.m4a') || name.endsWith('.mp4') || name.endsWith('.aac')) {
      final size = int.tryParse(file.size ?? '');
      return _readM4a(id, token, size, readCover: readCover);
    }

    return null;
  }

  static Future<Uint8List> _range(String fileId, String token, int start, int end) async {
    final client = http.Client();
    try {
      final uri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
      final request = http.Request('GET', uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'User-Agent': 'InfameApp/1.0',
          'Range': 'bytes=$start-$end',
        })
        ..followRedirects = false;

      final response = await client.send(request);
      http.StreamedResponse finalResponse = response;

      if (response.isRedirect && response.headers.containsKey('location')) {
        final redirectUri = Uri.parse(response.headers['location']!);
        final secondRequest = http.Request('GET', redirectUri)
          ..headers['Range'] = 'bytes=$start-$end';
        finalResponse = await client.send(secondRequest);
      }

      if (finalResponse.statusCode != 200 && finalResponse.statusCode != 206) {
        return Uint8List(0);
      }

      final bytes = await finalResponse.stream.toBytes();
      return Uint8List.fromList(bytes);
    } finally {
      client.close();
    }
  }

  static int _u16be(Uint8List b, int o) {
    if (o + 1 >= b.length) return 0;
    return (b[o] << 8) | b[o + 1];
  }

  static int _u24be(Uint8List b, int o) {
    if (o + 2 >= b.length) return 0;
    return (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];
  }

  static int _u32be(Uint8List b, int o) {
    if (o + 3 >= b.length) return 0;
    return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  }

  static int _u32le(Uint8List b, int o) {
    if (o + 3 >= b.length) return 0;
    return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
  }

  static int _synchsafe(Uint8List b, int o) {
    if (o + 3 >= b.length) return 0;
    return (b[o] << 21) | (b[o + 1] << 14) | (b[o + 2] << 7) | b[o + 3];
  }

  static String _ascii(Uint8List b, int o, int len) {
    if (o + len > b.length) return '';
    return String.fromCharCodes(b.sublist(o, o + len));
  }

  static Uint8List _slice(Uint8List b, int start, int end) {
    final s = start.clamp(0, b.length);
    final e = end.clamp(0, b.length);
    if (e <= s) return Uint8List(0);
    return Uint8List.fromList(b.sublist(s, e));
  }

  static String _cleanText(String value) {
    return value.replaceAll(String.fromCharCode(0), '').trim();
  }

  static String _decodeUtf16(Uint8List bytes, {bool? bigEndian}) {
    if (bytes.isEmpty) return '';

    int offset = 0;
    bool be = bigEndian ?? false;

    if (bytes.length >= 2) {
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        be = true;
        offset = 2;
      } else if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        be = false;
        offset = 2;
      }
    }

    final units = <int>[];
    for (int i = offset; i + 1 < bytes.length; i += 2) {
      final unit = be ? ((bytes[i] << 8) | bytes[i + 1]) : (bytes[i] | (bytes[i + 1] << 8));
      if (unit == 0) continue;
      units.add(unit);
    }

    return String.fromCharCodes(units);
  }

  static String _decodeId3Text(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    final encoding = bytes[0];
    final payload = _slice(bytes, 1, bytes.length);

    try {
      if (encoding == 0) return _cleanText(latin1.decode(payload, allowInvalid: true));
      if (encoding == 1) return _cleanText(_decodeUtf16(payload));
      if (encoding == 2) return _cleanText(_decodeUtf16(payload, bigEndian: true));
      if (encoding == 3) return _cleanText(utf8.decode(payload, allowMalformed: true));
    } catch (_) {}

    return _cleanText(utf8.decode(payload, allowMalformed: true));
  }

  static int? _parseFirstInt(String? value) {
    if (value == null) return null;
    final buffer = StringBuffer();
    for (final code in value.codeUnits) {
      if (code >= 48 && code <= 57) {
        buffer.writeCharCode(code);
      } else if (buffer.isNotEmpty) {
        break;
      }
    }
    if (buffer.isEmpty) return null;
    return int.tryParse(buffer.toString());
  }

  static String? _parseYear(String? value) {
    if (value == null) return null;
    final match = RegExp(r'(19|20)\d{2}').firstMatch(value);
    return match?.group(0);
  }

  static String? _cleanGenre(String? value) {
    if (value == null) return null;
    var genre = value.trim();
    if (genre.isEmpty) return null;

    // ID3 sometimes stores numeric genres like "(17)" or "(17)Rock".
    genre = genre.replaceAll(RegExp(r'^\(\d+\)\s*'), '').trim();

    final numericOnly = RegExp(r'^\d+$').hasMatch(genre);
    if (numericOnly) return null;

    if (genre.length > 40) genre = genre.substring(0, 40).trim();
    return genre.isEmpty ? null : genre;
  }

  static Future<TrackReadResult?> _readMp3(
    String fileId,
    String token, {
    bool readCover = true,
  }) async {
    final header = await _range(fileId, token, 0, 9);
    if (header.length < 10 || _ascii(header, 0, 3) != 'ID3') return null;

    final version = header[3];
    final tagSize = _synchsafe(header, 6) + 10;
    if (tagSize <= 10) return null;

    final fetchSize = math.min(tagSize, maxTagChunk);
    final bytes = await _range(fileId, token, 0, fetchSize - 1);
    if (bytes.length < 20) return null;

    String? title;
    String? artist;
    String? album;
    String? trackRaw;
    String? discRaw;
    String? yearRaw;
    String? genreRaw;
    Uint8List? cover;

    int pos = 10;
    while (pos + 10 <= bytes.length && pos < tagSize) {
      final id = _ascii(bytes, pos, 4);
      if (id.trim().isEmpty) break;

      final size = version == 4 ? _synchsafe(bytes, pos + 4) : _u32be(bytes, pos + 4);
      if (size <= 0 || pos + 10 + size > bytes.length) break;

      final payload = _slice(bytes, pos + 10, pos + 10 + size);

      if (id == 'TIT2') title = _decodeId3Text(payload);
      if (id == 'TPE1') artist = _decodeId3Text(payload);
      if (id == 'TALB') album = _decodeId3Text(payload);
      if (id == 'TRCK') trackRaw = _decodeId3Text(payload);
      if (id == 'TPOS') discRaw = _decodeId3Text(payload);
      if (id == 'TDRC' || id == 'TYER') yearRaw = _decodeId3Text(payload);
      if (id == 'TCON') genreRaw = _decodeId3Text(payload);
      if (readCover && (id == 'APIC' || id == 'PIC') && cover == null) {
        cover = _parseApic(payload);
      }

      pos += 10 + size;
    }

    final result = TrackReadResult(
      title: title,
      artist: artist,
      album: album,
      trackNumber: _parseFirstInt(trackRaw),
      discNumber: _parseFirstInt(discRaw),
      year: _parseYear(yearRaw),
      genre: _cleanGenre(genreRaw),
      coverBytes: cover,
    );

    return result.hasUsefulText || result.coverBytes != null ? result : null;
  }

  static Uint8List? _parseApic(Uint8List payload) {
    if (payload.length < 8) return null;
    final encoding = payload[0];
    int pos = 1;

    while (pos < payload.length && payload[pos] != 0) {
      pos++;
    }
    pos++;

    if (pos >= payload.length) return null;
    pos++;

    if (encoding == 1 || encoding == 2) {
      while (pos + 1 < payload.length) {
        if (payload[pos] == 0 && payload[pos + 1] == 0) {
          pos += 2;
          break;
        }
        pos += 2;
      }
    } else {
      while (pos < payload.length && payload[pos] != 0) {
        pos++;
      }
      pos++;
    }

    if (pos >= payload.length) return null;
    return _slice(payload, pos, payload.length);
  }

  static Future<TrackReadResult?> _readFlac(
    String fileId,
    String token, {
    bool readCover = true,
  }) async {
    final bytes = await _range(fileId, token, 0, largerChunk - 1);
    if (bytes.length < 8 || _ascii(bytes, 0, 4) != 'fLaC') return null;

    String? title;
    String? artist;
    String? album;
    String? year;
    String? genre;
    int? trackNumber;
    int? discNumber;
    Uint8List? cover;

    int pos = 4;
    bool last = false;

    while (!last && pos + 4 <= bytes.length) {
      final header = bytes[pos];
      last = (header & 0x80) != 0;
      final type = header & 0x7F;
      final length = _u24be(bytes, pos + 1);
      final start = pos + 4;
      final end = start + length;
      if (end > bytes.length) break;

      final block = _slice(bytes, start, end);

      if (type == 4) {
        final comments = _parseVorbisComments(block);
        title = comments['TITLE'] ?? title;
        artist = comments['ARTIST'] ?? comments['ALBUMARTIST'] ?? artist;
        album = comments['ALBUM'] ?? album;
        year = _parseYear(comments['DATE'] ?? comments['YEAR'] ?? comments['ORIGINALYEAR']) ?? year;
        genre = _cleanGenre(comments['GENRE']) ?? genre;
        trackNumber = _parseFirstInt(comments['TRACKNUMBER']) ?? trackNumber;
        discNumber = _parseFirstInt(comments['DISCNUMBER']) ?? discNumber;
      }

      if (readCover && type == 6 && cover == null) {
        cover = _parseFlacPicture(block);
      }

      pos = end;
    }

    final result = TrackReadResult(
      title: title,
      artist: artist,
      album: album,
      year: year,
      genre: genre,
      trackNumber: trackNumber,
      discNumber: discNumber,
      coverBytes: cover,
    );

    return result.hasUsefulText || result.coverBytes != null ? result : null;
  }

  static Map<String, String> _parseVorbisComments(Uint8List b) {
    final comments = <String, String>{};
    int pos = 0;
    if (pos + 4 > b.length) return comments;

    final vendorLength = _u32le(b, pos);
    pos += 4 + vendorLength;
    if (pos + 4 > b.length) return comments;

    final count = _u32le(b, pos);
    pos += 4;

    for (int i = 0; i < count; i++) {
      if (pos + 4 > b.length) break;
      final length = _u32le(b, pos);
      pos += 4;
      if (pos + length > b.length) break;
      final text = utf8.decode(_slice(b, pos, pos + length), allowMalformed: true);
      pos += length;
      final eq = text.indexOf('=');
      if (eq > 0) {
        comments[text.substring(0, eq).toUpperCase()] = text.substring(eq + 1).trim();
      }
    }

    return comments;
  }

  static Uint8List? _parseFlacPicture(Uint8List b) {
    int pos = 0;
    if (pos + 8 > b.length) return null;
    pos += 4;

    final mimeLength = _u32be(b, pos);
    pos += 4 + mimeLength;
    if (pos + 4 > b.length) return null;

    final descLength = _u32be(b, pos);
    pos += 4 + descLength;
    if (pos + 20 > b.length) return null;

    pos += 16;
    final dataLength = _u32be(b, pos);
    pos += 4;
    if (pos + dataLength > b.length) return null;

    return _slice(b, pos, pos + dataLength);
  }

  static Future<TrackReadResult?> _readM4a(
    String fileId,
    String token,
    int? size, {
    bool readCover = true,
  }) async {
    final first = await _range(fileId, token, 0, largerChunk - 1);
    final firstResult = _parseM4a(first, readCover: readCover);
    if (firstResult != null && (firstResult.hasUsefulText || firstResult.coverBytes != null)) {
      return firstResult;
    }

    if (size != null && size > largerChunk) {
      final start = math.max(0, size - largerChunk);
      final tail = await _range(fileId, token, start, size - 1);
      final tailResult = _parseM4a(tail, allowIlistScan: true, readCover: readCover);
      if (tailResult != null && (tailResult.hasUsefulText || tailResult.coverBytes != null)) {
        return tailResult;
      }
    }

    return null;
  }

  static TrackReadResult? _parseM4a(
    Uint8List bytes, {
    bool allowIlistScan = false,
    bool readCover = true,
  }) {
    final found = <String, dynamic>{};
    _walkMp4Boxes(bytes, 0, bytes.length, found, 0, readCover: readCover);

    if (allowIlistScan && found.isEmpty) {
      final ilst = _findBox(bytes, 'ilst');
      if (ilst != null) {
        _parseIlst(bytes, ilst[0] + 8, ilst[1], found, readCover: readCover);
      }
    }

    if (found.isEmpty) return null;

    return TrackReadResult(
      title: found['title'] as String?,
      artist: (found['artist'] ?? found['albumArtist']) as String?,
      album: found['album'] as String?,
      year: _parseYear(found['year'] as String?),
      genre: _cleanGenre(found['genre'] as String?),
      trackNumber: found['trackNumber'] as int?,
      discNumber: found['discNumber'] as int?,
      coverBytes: found['coverBytes'] as Uint8List?,
    );
  }

  static void _walkMp4Boxes(
    Uint8List b,
    int start,
    int end,
    Map<String, dynamic> found,
    int depth, {
    bool readCover = true,
  }) {
    if (depth > 8) return;
    int pos = start;

    while (pos + 8 <= end && pos + 8 <= b.length) {
      int size = _u32be(b, pos);
      final type = _ascii(b, pos + 4, 4);
      int header = 8;

      if (size == 1 && pos + 16 <= b.length) {
        final high = _u32be(b, pos + 8);
        final low = _u32be(b, pos + 12);
        if (high != 0) break;
        size = low;
        header = 16;
      }

      if (size < header) break;
      final boxEnd = pos + size;
      if (boxEnd > end || boxEnd > b.length) break;

      if (type == 'ilst') {
        _parseIlst(b, pos + header, boxEnd, found, readCover: readCover);
      } else if (type == 'moov' || type == 'udta' || type == 'trak' || type == 'mdia' || type == 'minf' || type == 'stbl') {
        _walkMp4Boxes(b, pos + header, boxEnd, found, depth + 1, readCover: readCover);
      } else if (type == 'meta') {
        _walkMp4Boxes(b, pos + header + 4, boxEnd, found, depth + 1, readCover: readCover);
      }

      pos = boxEnd;
    }
  }

  static List<int>? _findBox(Uint8List b, String type) {
    final codes = type.codeUnits;
    for (int i = 4; i + 4 < b.length; i++) {
      if (b[i] == codes[0] && b[i + 1] == codes[1] && b[i + 2] == codes[2] && b[i + 3] == codes[3]) {
        final start = i - 4;
        final size = _u32be(b, start);
        final end = start + size;
        if (size >= 8 && end <= b.length) return [start, end];
      }
    }
    return null;
  }

  static void _parseIlst(
    Uint8List b,
    int start,
    int end,
    Map<String, dynamic> found, {
    bool readCover = true,
  }) {
    final nam = String.fromCharCodes([0xA9, 0x6E, 0x61, 0x6D]);
    final art = String.fromCharCodes([0xA9, 0x41, 0x52, 0x54]);
    final alb = String.fromCharCodes([0xA9, 0x61, 0x6C, 0x62]);
    final day = String.fromCharCodes([0xA9, 0x64, 0x61, 0x79]);
    final gen = String.fromCharCodes([0xA9, 0x67, 0x65, 0x6E]);

    int pos = start;
    while (pos + 8 <= end && pos + 8 <= b.length) {
      final size = _u32be(b, pos);
      final type = _ascii(b, pos + 4, 4);
      if (size < 8 || pos + size > end || pos + size > b.length) break;

      final value = _parseM4aDataAtom(b, pos + 8, pos + size);

      if (type == nam && value is String) found['title'] = value;
      if ((type == art || type == 'aART') && value is String) {
        if (type == 'aART') {
          found['albumArtist'] = value;
        } else {
          found['artist'] = value;
        }
      }
      if (type == alb && value is String) found['album'] = value;
      if (type == day && value is String) found['year'] = value;
      if (type == gen && value is String) found['genre'] = value;
      if (type == 'trkn' && value is int) found['trackNumber'] = value;
      if (type == 'disk' && value is int) found['discNumber'] = value;
      if (readCover && type == 'covr' && value is Uint8List) found['coverBytes'] = value;

      pos += size;
    }
  }

  static dynamic _parseM4aDataAtom(Uint8List b, int start, int end) {
    int pos = start;
    while (pos + 16 <= end && pos + 16 <= b.length) {
      final size = _u32be(b, pos);
      final type = _ascii(b, pos + 4, 4);
      if (size < 16 || pos + size > end || pos + size > b.length) break;

      if (type == 'data') {
        final payloadStart = pos + 16;
        final payload = _slice(b, payloadStart, pos + size);
        if (payload.isEmpty) return null;

        if (payload.length >= 6 && payload[0] == 0 && payload[1] == 0) {
          return _u16be(payload, 2);
        }

        final text = utf8.decode(payload, allowMalformed: true).trim();
        if (text.isNotEmpty && text.codeUnits.every((c) => c >= 32 || c == 10 || c == 13)) {
          return text;
        }

        return payload;
      }

      pos += size;
    }

    return null;
  }
}

void _saveMetadataProgressSnapshot(Map<String, dynamic> payload) {
  final encoded = json.encode(payload);

  // Store progress in both places. sendDataToMain is not always delivered while
  // Android is busy or when the UI is rebuilding, so the app also polls this.
  FlutterForegroundTask.saveData(key: _metadataProgressPrefsKey, value: encoded);

  SharedPreferences.getInstance().then((prefs) {
    prefs.setString(_metadataProgressPrefsKey, encoded);
  });
}

int? _validDurationMsFromBackgroundValue(Object? value) {
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

void _sendAlbumCoverFoundBackground(String albumId, String coverPath) {
  if (albumId.trim().isEmpty || coverPath.trim().isEmpty) return;
  FlutterForegroundTask.sendDataToMain({
    'type': 'album_cover_found',
    'albumId': albumId,
    'coverPath': coverPath,
  });
}

@pragma('vm:entry-point')
void metadataScanStartCallback() {
  FlutterForegroundTask.setTaskHandler(MetadataScanTaskHandler());
}

class MetadataScanTaskHandler extends TaskHandler {
  bool _cancelled = false;
  bool _scanStarted = false;
  int _done = 0;
  int _total = 0;
  int _fast = 0;
  int _deep = 0;
  int _failed = 0;
  int _lastPublishMs = 0;
  String _phase = 'Preparing';

  void _publish({bool running = true, bool force = false}) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Updating the Android notification and SharedPreferences for every single
    // track is surprisingly expensive. Throttle normal progress updates, but
    // still allow important phase changes/final states to publish immediately.
    if (!force && nowMs - _lastPublishMs < 450) return;
    _lastPublishMs = nowMs;

    final notificationText = _total == 0
        ? 'Preparing metadata scan...'
        : 'Scanning metadata $_done/$_total • Fast: $_fast • Deep: $_deep • Failed: $_failed';

    FlutterForegroundTask.updateService(
      notificationTitle: 'Infame metadata scan',
      notificationText: notificationText,
    );

    final payload = {
      'type': 'metadata_progress',
      'done': _done,
      'total': _total,
      'fast': _fast,
      'deep': _deep,
      'failed': _failed,
      'phase': _phase,
      'running': running,
      'updatedAt': nowMs,
    };

    _saveMetadataProgressSnapshot(payload);
    FlutterForegroundTask.sendDataToMain(payload);
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    DartPluginRegistrant.ensureInitialized();

    // IMPORTANT: Start the real scan from inside onStart.
    // Waiting for sendDataToTask() after startService() can make the plugin
    // hit the foreground-service request timeout on some Android devices.
    _scanStarted = true;
    _phase = 'Starting';

    FlutterForegroundTask.updateService(
      notificationTitle: 'Infame metadata scan',
      notificationText: 'Starting metadata scan...',
    );

    _publish(force: true);

    Future.microtask(_runScan);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _publish();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    final payload = {
      'type': 'metadata_progress',
      'done': _done,
      'total': _total,
      'fast': _fast,
      'deep': _deep,
      'failed': _failed,
      'phase': isTimeout ? 'Stopped by Android timeout' : _phase,
      'running': false,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    _saveMetadataProgressSnapshot(payload);
    FlutterForegroundTask.sendDataToMain(payload);
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'start_metadata_scan') {
      if (_scanStarted) return;
      _scanStarted = true;
      Future.microtask(_runScan);
      return;
    }

    if (data == 'cancel_metadata_scan') {
      _cancelled = true;
      _phase = 'Cancelling';
      _publish();
    }
  }

  Future<void> _runScan() async {
    try {
      await _metaStore.load();

      final token = await FlutterForegroundTask.getData<String>(key: 'metadata_token');
      final albumsRaw = await FlutterForegroundTask.getData<String>(key: 'metadata_albums');

      if (token == null || token.isEmpty || albumsRaw == null || albumsRaw.isEmpty) {
        _phase = 'Missing scan data';
        _publish(running: false, force: true);
        await FlutterForegroundTask.stopService();
        return;
      }

      final albums = List<Map<String, String>>.from(
        (json.decode(albumsRaw) as List).map((e) => Map<String, String>.from(e)),
      );

      _phase = 'Collecting tracks';
      _publish();

      final api = drive.DriveApi(GoogleAuthClient({'Authorization': 'Bearer $token'}));
      final Map<String, drive.File> uniqueTracks = {};
      final Map<String, Map<String, String>> trackAlbums = {};
      final Map<String, List<drive.File>> albumTracks = {};

      for (final album in albums) {
        if (_cancelled) break;
        final tracks = await _fetchTracksForAlbumRecordBackground(api, album);
        albumTracks[album['id'] ?? ''] = tracks;

        for (final track in tracks) {
          final id = DriveUtils.effectiveId(track);
          if (id == null) continue;
          uniqueTracks[id] = track;
          trackAlbums[id] = album;
        }
      }

      // Load durations map to check for missing durations
      final prefs = await SharedPreferences.getInstance();
      final durationsRaw = prefs.getString(_knownTrackDurationsPrefsKey);
      final Map<String, dynamic> durations = (durationsRaw != null && durationsRaw.isNotEmpty)
          ? Map<String, dynamic>.from(json.decode(durationsRaw) as Map)
          : <String, dynamic>{};

      final missing = uniqueTracks.values
          .where((track) {
            final fileId = DriveUtils.effectiveId(track);
            if (fileId == null) return false;
            
            // Check if metadata is missing
            final metadataMissing = _metaStore.peekFresh(track) == null;
            
            // Check if duration is missing. Some older cache payloads may
            // contain strings, so parse defensively instead of casting.
            final durationMissing = _validDurationMsFromBackgroundValue(durations[fileId]) == null;

            return metadataMissing || durationMissing;
          })
          .toList()
        ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

      _total = missing.length;
      _done = 0;
      _publish();

      final List<drive.File> deepFallback = [];

      if (missing.isNotEmpty) {
        _phase = 'Fast text scan';
        _publish(force: true);

        const fastBatchSize = 6;
        for (int i = 0; i < missing.length; i += fastBatchSize) {
          if (_cancelled) break;
          final batch = missing.skip(i).take(fastBatchSize).toList();

          await Future.wait(batch.map((track) async {
            final ok = await _loadFastTextMetadataBackground(track, token);
            if (ok) {
              _fast++;
            } else {
              deepFallback.add(track);
            }
            _done++;
            _publish();
          }));

          if (i % 60 == 0) {
            await _metaStore.persistNow();
          }
        }

        await _metaStore.persistNow();
      }

      // Even when all text metadata is already fresh, covers may still be
      // missing. Do not skip this phase just because there are no tracks in
      // the text-metadata queue.
      _phase = 'Album cover scan';
      _publish(force: true);

      for (final album in albums) {
        if (_cancelled) break;

        final albumId = album['id'] ?? '';
        final currentCover = album['cover'] ?? '';
        if (_isLocalCover(currentCover)) {
          final tracks = albumTracks[albumId] ?? <drive.File>[];
          _applyAlbumCoverPathToTrackCacheBackground(tracks, currentCover);
          _sendAlbumCoverFoundBackground(albumId, currentCover);
          continue;
        }

        final tracks = albumTracks[albumId] ?? <drive.File>[];
        if (tracks.isEmpty) continue;

        // First reuse any already cached embedded cover from any track in the
        // album. This makes rescans nearly instant and fixes the case where
        // the app says metadata is done but album cards still wait for art.
        final cachedCover = _firstCachedAlbumCoverPathBackground(tracks);
        if (cachedCover != null) {
          album['cover'] = cachedCover;
          _applyAlbumCoverPathToTrackCacheBackground(tracks, cachedCover);
          _sendAlbumCoverFoundBackground(albumId, cachedCover);
          continue;
        }

        // Match the single-album cover behavior: probe a handful of tracks,
        // because some albums only have embedded art on track 2/3/etc.
        for (final coverTrack in tracks.take(8)) {
          final result = await FastTagReader.read(
            file: coverTrack,
            token: token,
            readCover: true,
          );

          final bytes = result?.coverBytes;
          if (bytes == null || bytes.isEmpty) continue;

          final coverPath = await _saveEmbeddedCoverBackground(coverTrack, bytes);
          if (coverPath == null || coverPath.isEmpty) continue;

          album['cover'] = coverPath;
          _applyAlbumCoverPathToTrackCacheBackground(tracks, coverPath);
          _sendAlbumCoverFoundBackground(albumId, coverPath);
          break;
        }
      }

      await _metaStore.persistNow();
      await _persistAlbumsBackground(albums);

      if (deepFallback.isNotEmpty) {
        _phase = 'Deep fallback scan';
        _publish(force: true);
      }

      for (final track in deepFallback) {
        if (_cancelled) break;

        final ok = await _loadDeepMetadataBackground(track, token);
        if (ok) {
          _deep++;
        } else {
          _failed++;
        }
        await _metaStore.persistNow();
        _publish();
      }

      _enrichAlbumsBackground(albums, albumTracks);
      await _metaStore.persistNow();
      await _persistAlbumsBackground(albums);

      _phase = _cancelled ? 'Cancelled' : 'Complete';
      _publish(running: false, force: true);
      await FlutterForegroundTask.stopService();
    } catch (_) {
      _phase = 'Failed';
      _failed++;
      _publish(running: false, force: true);
      await FlutterForegroundTask.stopService();
    }
  }

  Future<List<drive.File>> _fetchTracksForAlbumRecordBackground(
    drive.DriveApi api,
    Map<String, String> album,
  ) async {
    final List<drive.File> tracks = [];
    final folderIds = (album['id'] ?? '').split(',').where((id) => id.trim().isNotEmpty);

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

  Future<bool> _loadFastTextMetadataBackground(drive.File file, String token) async {
    try {
      final fallback = DriveUtils.getTrackMeta(file);
      final fastResult = await FastTagReader.read(
        file: file,
        token: token,
        readCover: false,
      );

      // Duration belongs to the same metadata scan pass. Save it even if
      // the text tags are already bad/missing so the UI gets timestamps at
      // the same time as the rest of the scan results.
      await _extractAndSaveDurationBackground(file, token);

      if (fastResult == null || !fastResult.hasUsefulText) return false;

      _metaStore.putMemory(
        file,
        TrackMetadata(
          title: fastResult.title?.trim().isNotEmpty == true
              ? fastResult.title!.trim()
              : fallback['title'] ?? file.name ?? 'Unknown',
          artist: fastResult.artist?.trim().isNotEmpty == true
              ? fastResult.artist!.trim()
              : fallback['artist'] ?? 'Unknown Artist',
          album: fastResult.album?.trim().isNotEmpty == true ? fastResult.album!.trim() : null,
          year: fastResult.year,
          genre: fastResult.genre,
          trackNumber: fastResult.trackNumber,
          discNumber: fastResult.discNumber,
          modifiedTime: file.modifiedTime?.toIso8601String(),
          size: file.size,
        ),
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _extractAndSaveDurationBackground(drive.File file, String token) async {
    final fileId = DriveUtils.effectiveId(file);
    if (fileId == null) return;

    final prefs = await SharedPreferences.getInstance();

    Future<Map<String, dynamic>> loadDurations() async {
      final raw = prefs.getString(_knownTrackDurationsPrefsKey);
      if (raw == null || raw.isEmpty) return <String, dynamic>{};
      try {
        final decoded = json.decode(raw);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
      } catch (_) {
        return <String, dynamic>{};
      }
    }

    final existing = await loadDurations();
    if (_validDurationMsFromBackgroundValue(existing[fileId]) != null) return;

    final tempPlayer = AudioPlayer();
    try {
      final source = DriveAudioSource(fileId, token);

      Duration? duration = await tempPlayer
          .setAudioSource(source)
          .timeout(const Duration(seconds: 10), onTimeout: () => null);

      duration ??= await tempPlayer.durationStream
          .firstWhere((value) => value != null)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      final durationMs = _validDurationMsFromBackgroundValue(duration?.inMilliseconds);
      if (durationMs == null) return;

      final durations = await loadDurations();
      durations[fileId] = durationMs;
      await prefs.setString(_knownTrackDurationsPrefsKey, json.encode(durations));

      FlutterForegroundTask.sendDataToMain({
        'type': 'duration_found',
        'fileId': fileId,
        'durationMs': durationMs,
      });
    } catch (_) {
      // Keep the metadata scan moving if one file cannot expose a duration.
    } finally {
      await tempPlayer.dispose();
    }
  }

  Future<bool> _loadDeepMetadataBackground(drive.File file, String token) async {
    File? tempFile;

    try {
      final fileId = DriveUtils.effectiveId(file);
      if (fileId == null) return false;

      final fallback = DriveUtils.getTrackMeta(file);
      tempFile = await _downloadTrackToTempBackground(fileId, token, _audioExtensionFromFile(file));
      final metadata = readMetadata(tempFile, getImage: false);

      _metaStore.putMemory(
        file,
        TrackMetadata(
          title: metadata.title?.trim().isNotEmpty == true
              ? metadata.title!.trim()
              : fallback['title'] ?? file.name ?? 'Unknown',
          artist: metadata.artist?.trim().isNotEmpty == true
              ? metadata.artist!.trim()
              : fallback['artist'] ?? 'Unknown Artist',
          album: metadata.album?.trim().isNotEmpty == true ? metadata.album!.trim() : null,
          year: null,
          genre: null,
          trackNumber: metadata.trackNumber,
          discNumber: metadata.discNumber,
          modifiedTime: file.modifiedTime?.toIso8601String(),
          size: file.size,
        ),
      );

      // Extract and save duration
      await _extractAndSaveDurationBackground(file, token);

      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }


  String? _firstCachedAlbumCoverPathBackground(List<drive.File> tracks) {
    for (final track in tracks) {
      final coverPath = _metaStore.peek(track)?.coverPath;
      if (coverPath != null && coverPath.isNotEmpty) {
        return coverPath;
      }
    }
    return null;
  }

  void _applyAlbumCoverPathToTrackCacheBackground(
    List<drive.File> tracks,
    String coverPath,
  ) {
    if (coverPath.isEmpty) return;

    for (final track in tracks) {
      final fallback = DriveUtils.getTrackMeta(track);
      final cached = _metaStore.peek(track);

      if (cached != null && cached.coverPath == coverPath) continue;

      _metaStore.putMemory(
        track,
        TrackMetadata(
          title: cached?.title ?? fallback['title'] ?? track.name ?? 'Unknown',
          artist: cached?.artist ?? fallback['artist'] ?? 'Unknown Artist',
          album: cached?.album,
          trackNumber: cached?.trackNumber,
          discNumber: cached?.discNumber,
          coverPath: coverPath,
          year: cached?.year,
          genre: cached?.genre,
          modifiedTime: cached?.modifiedTime ?? track.modifiedTime?.toIso8601String(),
          size: cached?.size ?? track.size,
        ),
      );
    }
  }

  String _cleanBackgroundValue(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty || v.toLowerCase() == 'unknown' || v.toLowerCase() == 'unknown artist') {
      return '';
    }
    return v;
  }

  String _mostCommonBackground(List<String> values) {
    final counts = <String, int>{};
    for (final raw in values) {
      final value = _cleanBackgroundValue(raw);
      if (value.isEmpty) continue;
      counts[value] = (counts[value] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        if (c != 0) return c;
        return a.key.compareTo(b.key);
      });
    return entries.first.key;
  }

  String _yearBackground(String? value) {
    if (value == null) return '';
    final match = RegExp(r'(19|20)\d{2}').firstMatch(value);
    return match?.group(0) ?? '';
  }

  String _genreBackground(String? value) {
    final g = _cleanBackgroundValue(value);
    if (g.isEmpty) return '';

    final first = g.split('/').first.split(';').first.split(',').first.trim();
    final t = first.toLowerCase();
    final normalized = t.replaceAll(RegExp(r'[^a-z0-9&]+'), ' ').trim();
    final words = normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();

    bool has(String word) => words.contains(word);

    if (normalized.contains('hip hop') || t.contains('hip-hop') || has('rap') || has('trap')) {
      return 'Hip-Hop';
    }
    if (t.contains('r&b') || has('rnb') || has('soul') || has('funk')) return 'Soul / R&B';
    if (has('jazz')) return 'Jazz';
    if (has('rock') || has('metal') || has('punk')) return 'Rock';
    if (has('electronic') || has('house') || has('techno') || has('dance')) return 'Electronic';
    if (has('soundtrack') || has('score')) return 'Soundtracks';
    if (has('pop')) return 'Pop';
    return first;
  }

  void _enrichAlbumsBackground(
    List<Map<String, String>> albums,
    Map<String, List<drive.File>> albumTracks,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch.toString();

    for (final album in albums) {
      final albumId = album['id'] ?? '';
      if (albumId.isEmpty) continue;
      final tracks = albumTracks[albumId] ?? <drive.File>[];
      if (tracks.isEmpty) continue;

      final artists = <String>[];
      final albumNames = <String>[];
      final years = <String>[];
      final genres = <String>[];

      for (final track in tracks) {
        final cached = _metaStore.peek(track);
        if (cached == null) continue;
        artists.add(cached.artist);
        if (cached.album != null) albumNames.add(cached.album!);
        if (cached.year != null) years.add(cached.year!);
        if (cached.genre != null) genres.add(cached.genre!);
      }

      final folderName = album['name'] ?? 'Album';
      final folderGuess = _artistAlbumFromFolderBackground(folderName);
      final displayName = _mostCommonBackground(albumNames).isNotEmpty
          ? _mostCommonBackground(albumNames)
          : folderGuess['album'] ?? folderName;
      final artist = _mostCommonBackground(artists).isNotEmpty
          ? _mostCommonBackground(artists)
          : folderGuess['artist'] ?? '';
      final year = _mostCommonBackground(years).isNotEmpty
          ? _yearBackground(_mostCommonBackground(years))
          : _yearBackground('$displayName $folderName');
      final genre = _genreBackground(_mostCommonBackground(genres));

      album['displayName'] = displayName;
      album['artist'] = artist;
      album['year'] = year;
      album['genre'] = genre;
      album['trackCount'] = tracks.length.toString();
      album['dateAdded'] = album['dateAdded'] ?? now;
    }
  }
}


Map<String, String> _artistAlbumFromFolderBackground(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'\s*\[(19|20)\d{2}\]\s*'), ' ')
      .replaceAll(RegExp(r'\s*\((19|20)\d{2}\)\s*'), ' ')
      .trim();

  final parts = cleaned.split(RegExp(r'\s+[–—-]\s+'));
  if (parts.length < 2) return const <String, String>{};

  final artist = _cleanMetadataValue(parts.first);
  final album = _cleanMetadataValue(parts.sublist(1).join(' - '));
  if (artist.isEmpty || album.isEmpty) return const <String, String>{};

  return {
    'artist': artist,
    'album': album,
  };
}
String _cleanMetadataValue(String? value) {
  final cleaned = (value ?? '')
      .replaceAll('\u0000', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (cleaned.isEmpty) return '';

  final lower = cleaned.toLowerCase();
  if (lower == 'unknown' ||
      lower == 'unknown artist' ||
      lower == 'untitled' ||
      lower == 'null' ||
      lower == 'none') {
    return '';
  }

  return cleaned;
}

String _safeCacheNameGlobal(String id) {
  return id
      .replaceAll('/', '_')
      .replaceAll(':', '_')
      .replaceAll('?', '_')
      .replaceAll('&', '_')
      .replaceAll('=', '_');
}

String _audioExtensionFromFile(drive.File file) {
  final name = file.name ?? 'track.mp3';
  final dot = name.lastIndexOf('.');
  if (dot == -1) return '.mp3';
  return name.substring(dot).toLowerCase();
}

String _coverExtensionFromBytesGlobal(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return '.png';
  }

  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return '.jpg';
  }

  if (bytes.length >= 12 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
    return '.webp';
  }

  return '.jpg';
}

Future<File> _downloadTrackToTempBackground(
  String fileId,
  String token,
  String extension,
) async {
  final dir = await getTemporaryDirectory();
  final unique = DateTime.now().microsecondsSinceEpoch;
  final path = '${dir.path}/musix_deep_${_safeCacheNameGlobal(fileId)}_$unique$extension';
  final tempFile = File(path);

  final uri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
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
      throw Exception('Could not download metadata file: ${finalResponse.statusCode}');
    }

    final sink = tempFile.openWrite();
    await finalResponse.stream.pipe(sink);
    return tempFile;
  } finally {
    client.close();
  }
}

Future<String?> _saveEmbeddedCoverBackground(drive.File file, Uint8List bytes) async {
  final fileId = DriveUtils.effectiveId(file);
  if (fileId == null || bytes.isEmpty) return null;

  try {
    final dir = await getApplicationDocumentsDirectory();
    final coverDir = Directory('${dir.path}/musix_embedded_covers');
    if (!await coverDir.exists()) {
      await coverDir.create(recursive: true);
    }

    final ext = _coverExtensionFromBytesGlobal(bytes);
    final path = '${coverDir.path}/${_safeCacheNameGlobal(fileId)}$ext';
    final out = File(path);
    await out.writeAsBytes(bytes, flush: true);
    return 'file://$path';
  } catch (_) {
    return null;
  }
}

Future<void> _persistAlbumsBackground(List<Map<String, String>> albums) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_albumsPrefsKey, json.encode(albums));
}
