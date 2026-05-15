part of '../main.dart';

// ─── Embedded Metadata Cache + Fast Tag Reader ─────────────────────────────

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
          _cache[key] =
              TrackMetadata.fromJson(Map<String, dynamic>.from(value));
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

class FastTagReader {
  static const int firstChunk = 256 * 1024;
  static const int largerChunk = 512 * 1024;
  static const int maxTagChunk = 1024 * 1024;

  static Future<TrackReadResult?> read({
    required drive.File file,
    required String token,
    bool readCover = true,
    http.Client? client,
  }) async {
    final id = DriveUtils.effectiveId(file);
    if (id == null) return null;

    final name = (file.name ?? '').toLowerCase();

    if (name.endsWith('.mp3')) {
      return _readMp3(id, token,
          sizeText: file.size, readCover: readCover, client: client);
    }

    if (name.endsWith('.flac')) {
      return _readFlac(id, token, readCover: readCover, client: client);
    }

    if (name.endsWith('.m4a') ||
        name.endsWith('.mp4') ||
        name.endsWith('.aac')) {
      final size = int.tryParse(file.size ?? '');
      return _readM4a(id, token, size, readCover: readCover, client: client);
    }

    return null;
  }

  static Future<Uint8List> _range(
    String fileId,
    String token,
    int start,
    int end, {
    http.Client? client,
  }) async {
    final ownedClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final uri = Uri.parse(
          'https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
      final request = http.Request('GET', uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'User-Agent': 'InfameApp/1.0',
          'Range': 'bytes=$start-$end',
        })
        ..followRedirects = false;

      final response = await ownedClient.send(request);
      http.StreamedResponse finalResponse = response;

      if (response.isRedirect && response.headers.containsKey('location')) {
        final redirectUri = Uri.parse(response.headers['location']!);
        final secondRequest = http.Request('GET', redirectUri)
          ..headers['Range'] = 'bytes=$start-$end';
        finalResponse = await ownedClient.send(secondRequest);
      }

      if (finalResponse.statusCode != 200 && finalResponse.statusCode != 206) {
        return Uint8List(0);
      }

      final bytes = await finalResponse.stream.toBytes();
      return Uint8List.fromList(bytes);
    } finally {
      if (shouldClose) {
        ownedClient.close();
      }
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

  static int _u64be(Uint8List b, int o) {
    if (o + 7 >= b.length) return 0;
    var value = 0;
    for (int i = 0; i < 8; i++) {
      value = (value << 8) | b[o + i];
    }
    return value;
  }

  static Duration? _flacDurationFromStreamInfo(Uint8List b) {
    if (b.length < 18) return null;
    final packed = _u64be(b, 10);
    final sampleRate = packed >> 44;
    final totalSamples = packed & 0xFFFFFFFFF;
    if (sampleRate <= 0 || totalSamples <= 0) return null;
    final ms = ((totalSamples * 1000) / sampleRate).round();
    return Duration(milliseconds: ms);
  }

  static Duration? _mp3DurationFromFrame(
    Uint8List bytes,
    int tagSize,
    String? sizeText,
  ) {
    final fileSize = int.tryParse(sizeText ?? '');
    if (fileSize == null || fileSize <= 0) return null;

    for (int i = tagSize.clamp(0, bytes.length - 4);
        i + 4 <= bytes.length;
        i++) {
      if (bytes[i] != 0xFF || (bytes[i + 1] & 0xE0) != 0xE0) continue;

      final versionBits = (bytes[i + 1] >> 3) & 0x03;
      final layerBits = (bytes[i + 1] >> 1) & 0x03;
      final bitrateIndex = (bytes[i + 2] >> 4) & 0x0F;
      if (versionBits == 1 ||
          layerBits == 0 ||
          bitrateIndex == 0 ||
          bitrateIndex == 15) {
        continue;
      }

      final isMpeg1 = versionBits == 3;
      final isLayer3 = layerBits == 1;
      final isLayer2 = layerBits == 2;
      final isLayer1 = layerBits == 3;

      final table = isLayer1
          ? (isMpeg1
              ? const [
                  0,
                  32,
                  64,
                  96,
                  128,
                  160,
                  192,
                  224,
                  256,
                  288,
                  320,
                  352,
                  384,
                  416,
                  448
                ]
              : const [
                  0,
                  32,
                  48,
                  56,
                  64,
                  80,
                  96,
                  112,
                  128,
                  144,
                  160,
                  176,
                  192,
                  224,
                  256
                ])
          : isLayer2
              ? (isMpeg1
                  ? const [
                      0,
                      32,
                      48,
                      56,
                      64,
                      80,
                      96,
                      112,
                      128,
                      160,
                      192,
                      224,
                      256,
                      320,
                      384
                    ]
                  : const [
                      0,
                      8,
                      16,
                      24,
                      32,
                      40,
                      48,
                      56,
                      64,
                      80,
                      96,
                      112,
                      128,
                      144,
                      160
                    ])
              : isLayer3
                  ? (isMpeg1
                      ? const [
                          0,
                          32,
                          40,
                          48,
                          56,
                          64,
                          80,
                          96,
                          112,
                          128,
                          160,
                          192,
                          224,
                          256,
                          320
                        ]
                      : const [
                          0,
                          8,
                          16,
                          24,
                          32,
                          40,
                          48,
                          56,
                          64,
                          80,
                          96,
                          112,
                          128,
                          144,
                          160
                        ])
                  : const <int>[];

      if (bitrateIndex >= table.length) continue;
      final kbps = table[bitrateIndex];
      if (kbps <= 0) continue;

      final audioBytes = math.max(0, fileSize - tagSize);
      final ms = ((audioBytes * 8) / (kbps * 1000) * 1000).round();
      if (ms <= 0 || ms >= 86400000) return null;
      return Duration(milliseconds: ms);
    }

    return null;
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
      final unit = be
          ? ((bytes[i] << 8) | bytes[i + 1])
          : (bytes[i] | (bytes[i + 1] << 8));
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
      if (encoding == 0)
        return _cleanText(latin1.decode(payload, allowInvalid: true));
      if (encoding == 1) return _cleanText(_decodeUtf16(payload));
      if (encoding == 2)
        return _cleanText(_decodeUtf16(payload, bigEndian: true));
      if (encoding == 3)
        return _cleanText(utf8.decode(payload, allowMalformed: true));
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
    String? sizeText,
    bool readCover = true,
    http.Client? client,
  }) async {
    final header = await _range(fileId, token, 0, 9, client: client);
    if (header.length < 10 || _ascii(header, 0, 3) != 'ID3') return null;

    final version = header[3];
    final tagSize = _synchsafe(header, 6) + 10;
    if (tagSize <= 10) return null;

    final fetchSize = math.min(tagSize, maxTagChunk);
    final bytes = await _range(fileId, token, 0, fetchSize - 1, client: client);
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

      final size =
          version == 4 ? _synchsafe(bytes, pos + 4) : _u32be(bytes, pos + 4);
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
      duration: _mp3DurationFromFrame(bytes, tagSize, sizeText),
    );

    return result.hasUsefulText ||
            result.coverBytes != null ||
            result.hasUsefulDuration
        ? result
        : null;
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
    http.Client? client,
  }) async {
    final bytes =
        await _range(fileId, token, 0, largerChunk - 1, client: client);
    if (bytes.length < 8 || _ascii(bytes, 0, 4) != 'fLaC') return null;

    String? title;
    String? artist;
    String? album;
    String? year;
    String? genre;
    int? trackNumber;
    int? discNumber;
    Duration? duration;
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

      if (type == 0) {
        duration = _flacDurationFromStreamInfo(block) ?? duration;
      }

      if (type == 4) {
        final comments = _parseVorbisComments(block);
        title = comments['TITLE'] ?? title;
        artist = comments['ARTIST'] ?? comments['ALBUMARTIST'] ?? artist;
        album = comments['ALBUM'] ?? album;
        year = _parseYear(comments['DATE'] ??
                comments['YEAR'] ??
                comments['ORIGINALYEAR']) ??
            year;
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
      duration: duration,
    );

    return result.hasUsefulText ||
            result.coverBytes != null ||
            result.hasUsefulDuration
        ? result
        : null;
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
      final text =
          utf8.decode(_slice(b, pos, pos + length), allowMalformed: true);
      pos += length;
      final eq = text.indexOf('=');
      if (eq > 0) {
        comments[text.substring(0, eq).toUpperCase()] =
            text.substring(eq + 1).trim();
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
    http.Client? client,
  }) async {
    final first =
        await _range(fileId, token, 0, largerChunk - 1, client: client);
    final firstResult = _parseM4a(first, readCover: readCover);
    if (firstResult != null &&
        (firstResult.hasUsefulText ||
            firstResult.coverBytes != null ||
            firstResult.hasUsefulDuration)) {
      return firstResult;
    }

    if (size != null && size > largerChunk) {
      final start = math.max(0, size - largerChunk);
      final tail = await _range(fileId, token, start, size - 1, client: client);
      final tailResult =
          _parseM4a(tail, allowIlistScan: true, readCover: readCover);
      if (tailResult != null &&
          (tailResult.hasUsefulText ||
              tailResult.coverBytes != null ||
              tailResult.hasUsefulDuration)) {
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
      duration: found['duration'] as Duration?,
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
      } else if (type == 'mdhd') {
        final duration = _parseMdhdDuration(b, pos + header, boxEnd);
        if (duration != null) found['duration'] ??= duration;
      } else if (type == 'moov' ||
          type == 'udta' ||
          type == 'trak' ||
          type == 'mdia' ||
          type == 'minf' ||
          type == 'stbl') {
        _walkMp4Boxes(b, pos + header, boxEnd, found, depth + 1,
            readCover: readCover);
      } else if (type == 'meta') {
        _walkMp4Boxes(b, pos + header + 4, boxEnd, found, depth + 1,
            readCover: readCover);
      }

      pos = boxEnd;
    }
  }

  static Duration? _parseMdhdDuration(Uint8List b, int start, int end) {
    if (start + 24 > end || start + 24 > b.length) return null;
    final version = b[start];
    int timescale;
    int duration;

    if (version == 1) {
      if (start + 36 > end || start + 36 > b.length) return null;
      timescale = _u32be(b, start + 20);
      duration = _u64be(b, start + 24);
    } else {
      timescale = _u32be(b, start + 12);
      duration = _u32be(b, start + 16);
    }

    if (timescale <= 0 || duration <= 0) return null;
    final ms = ((duration * 1000) / timescale).round();
    if (ms <= 0 || ms >= 86400000) return null;
    return Duration(milliseconds: ms);
  }

  static List<int>? _findBox(Uint8List b, String type) {
    final codes = type.codeUnits;
    for (int i = 4; i + 4 < b.length; i++) {
      if (b[i] == codes[0] &&
          b[i + 1] == codes[1] &&
          b[i + 2] == codes[2] &&
          b[i + 3] == codes[3]) {
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
      if (readCover && type == 'covr' && value is Uint8List)
        found['coverBytes'] = value;

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
        if (text.isNotEmpty &&
            text.codeUnits.every((c) => c >= 32 || c == 10 || c == 13)) {
          return text;
        }

        return payload;
      }

      pos += size;
    }

    return null;
  }
}

void _sendAlbumCoverFoundBackground(String albumId, String coverPath) {
  if (albumId.trim().isEmpty || coverPath.trim().isEmpty) return;
  FlutterForegroundTask.sendDataToMain({
    'type': 'album_cover_found',
    'albumId': albumId,
    'albumKey': albumId,
    'coverPath': coverPath,
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

class _ScanConcurrencyController {
  _ScanConcurrencyController({
    required int initialConcurrency,
    required this.maxConcurrency,
    this.minConcurrency = 3,
  }) : _currentConcurrency =
            initialConcurrency.clamp(minConcurrency, maxConcurrency).toInt();

  final int maxConcurrency;
  final int minConcurrency;
  int _currentConcurrency;

  int get currentConcurrency => _currentConcurrency;

  void increase({String reason = '', int step = 2}) {
    final next = (_currentConcurrency + step)
        .clamp(minConcurrency, maxConcurrency)
        .toInt();
    if (next == _currentConcurrency) return;
    _currentConcurrency = next;
    debugPrint(
        'MetadataScan concurrency increased to $_currentConcurrency reason=$reason');
  }

  void reduce({String reason = '', int step = 2}) {
    final next = (_currentConcurrency - step)
        .clamp(minConcurrency, maxConcurrency)
        .toInt();
    if (next == _currentConcurrency) return;
    _currentConcurrency = next;
    debugPrint(
        'MetadataScan concurrency reduced to $_currentConcurrency reason=$reason');
  }
}

bool _looksLikeRateLimitScanError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('429') ||
      text.contains('403') ||
      text.contains('rate limit') ||
      text.contains('rate-limit') ||
      text.contains('too many requests') ||
      text.contains('timeout') ||
      text.contains('socketexception') ||
      text.contains('503') ||
      text.contains('502');
}

Future<void> _runWithConcurrency<T>(
  List<T> items,
  _ScanConcurrencyController controller,
  Future<void> Function(T item, int index) worker,
) async {
  if (items.isEmpty) return;

  var nextIndex = 0;
  var active = 0;
  var completed = 0;
  final completer = Completer<void>();

  void pump() {
    if (completer.isCompleted) return;

    while (active < controller.currentConcurrency && nextIndex < items.length) {
      final item = items[nextIndex];
      final index = nextIndex;
      nextIndex++;
      active++;

      () async {
        Object? error;
        try {
          await worker(item, index);
        } catch (e) {
          error = e;
        } finally {
          active--;
          completed++;

          if (error != null) {
            if (_looksLikeRateLimitScanError(error)) {
              controller.reduce(reason: error.toString());
            } else if (completed % 25 == 0) {
              controller.reduce(reason: 'errors');
            }
          } else if (completed % 100 == 0) {
            controller.increase(reason: 'stable');
          }

          if (completed >= items.length && active == 0) {
            if (!completer.isCompleted) completer.complete();
          } else {
            pump();
          }
        }
      }();
    }
  }

  pump();
  await completer.future;
}

void _saveMetadataProgressSnapshot(Map<String, dynamic> payload) {
  final encoded = json.encode(payload);

  // Store progress in both places. sendDataToMain is not always delivered while
  // Android is busy or when the UI is rebuilding, so the app also polls this.
  FlutterForegroundTask.saveData(
      key: _metadataProgressPrefsKey, value: encoded);

  SharedPreferences.getInstance().then((prefs) {
    prefs.setString(_metadataProgressPrefsKey, encoded);
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
  int _lastPublishedDone = 0;
  String _phase = 'Preparing';

  void _publish(
      {bool running = true, bool force = false, int throttleMs = 450}) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Updating the Android notification and SharedPreferences for every single
    // track is surprisingly expensive. Throttle normal progress updates, but
    // still allow important phase changes/final states to publish immediately.
    if (!force) {
      final doneDelta = (_done - _lastPublishedDone).abs();
      if (nowMs - _lastPublishMs < throttleMs && doneDelta < 25) return;
    }
    _lastPublishMs = nowMs;
    _lastPublishedDone = _done;

    final phaseLower = _phase.toLowerCase();
    final notificationText = phaseLower.contains('cover')
        ? (_total == 0
            ? 'Preparing embedded cover scan...'
            : 'Scanning covers $_done/$_total • Found: $_fast • Skipped: $_deep • Missing: $_failed')
        : phaseLower.contains('saving')
            ? 'Saving metadata cache...'
            : _total == 0
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

      final token =
          await FlutterForegroundTask.getData<String>(key: 'metadata_token');
      final albumsRaw =
          await FlutterForegroundTask.getData<String>(key: 'metadata_albums');

      if (token == null ||
          token.isEmpty ||
          albumsRaw == null ||
          albumsRaw.isEmpty) {
        _phase = 'Missing scan data';
        _publish(running: false, force: true);
        await FlutterForegroundTask.stopService();
        return;
      }

      final albums = List<Map<String, String>>.from(
        (json.decode(albumsRaw) as List)
            .map((e) => Map<String, String>.from(e)),
      );

      _phase = 'Collecting tracks';
      _publish();

      final api =
          drive.DriveApi(GoogleAuthClient({'Authorization': 'Bearer $token'}));
      final Map<String, drive.File> uniqueTracks = {};
      final Map<String, Map<String, String>> trackAlbums = {};
      final Map<String, List<drive.File>> albumTracks = {};

      for (final album in albums) {
        if (_cancelled) break;
        final tracks = await _fetchTracksForAlbumRecordBackground(api, album);
        albumTracks[_albumCacheKey(album, source: 'metadata_album_tracks')] =
            tracks;

        for (final track in tracks) {
          final id = DriveUtils.effectiveId(track);
          if (id == null) continue;
          uniqueTracks[id] = track;
          trackAlbums[id] = album;
        }
      }

      final missing = uniqueTracks.values
          .where((track) => _metaStore.peekFresh(track) == null)
          .toList()
        ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

      _total = missing.length;
      _done = 0;
      _publish();

      if (missing.isNotEmpty) {
        _phase = 'Fast text scan';
        _publish(force: true, throttleMs: 900);
        final textScanStart = DateTime.now();
        final controller = _ScanConcurrencyController(
          initialConcurrency: 8,
          maxConcurrency: 12,
        );
        final textClient = http.Client();
        try {
          await _runWithConcurrency<drive.File>(
            missing,
            controller,
            (track, index) async {
              if (_cancelled) return;
              final ok = await _loadFastTextMetadataBackground(
                track,
                token,
                client: textClient,
              );
              if (ok) {
                _fast++;
              } else {
                _failed++;
              }
              _done++;
              _publish(throttleMs: 900);
              if (_done % 100 == 0) {
                await _metaStore.persistNow();
              }
            },
          );
        } finally {
          textClient.close();
        }

        await _metaStore.persistNow();
        final textElapsedMs = math.max(
            1, DateTime.now().difference(textScanStart).inMilliseconds);
        final textRate = (_done * 60000 / textElapsedMs).toStringAsFixed(1);
        debugPrint(
          'MetadataScan perf text completed=$_done/${missing.length} rate=$textRate tracks/min errors=$_failed',
        );
      }

      // Even when all text metadata is already fresh, covers may still be
      // missing. Do not skip this phase just because there are no tracks in
      // the text-metadata queue.
      final coverTargets = <Map<String, String>>[];
      var skipped = 0;
      for (final album in albums) {
        if (_cancelled) break;

        final albumId = _albumCacheKey(album, source: 'cover_scan_album_id');
        final tracks = albumTracks[albumId] ?? <drive.File>[];
        final resolvedCover = _resolvedAlbumCoverBackground(album, tracks);
        final currentCover = (album['cover'] ?? '').trim();
        if (resolvedCover.isNotEmpty) {
          skipped++;
          debugPrint(
            'CoverScan skip cached albumKey=${_albumCoverScanKey(album)} reason=existing_cover',
          );
          continue;
        }

        if (!_isAlbumCoverScanStale(album)) {
          skipped++;
          debugPrint(
            'CoverScan skip cached albumKey=${_albumCoverScanKey(album)} reason=already_checked',
          );
          continue;
        }

        if (tracks.isEmpty) {
          album[_embeddedCoverScanFingerprintKey] =
              _albumCoverScanFingerprint(album);
          skipped++;
          debugPrint(
            'CoverScan skip cached albumKey=${_albumCoverScanKey(album)} reason=no_tracks',
          );
          continue;
        }

        if (currentCover.isNotEmpty && resolvedCover.isEmpty) {
          debugPrint(
            'CoverScan key mismatch suspected oldKey=${album['id'] ?? ''} normalizedKey=${_albumCoverScanKey(album)}',
          );
        }

        coverTargets.add(album);
      }

      debugPrint(
        'CoverScan started albumsMissingCover=${coverTargets.length}',
      );

      _phase = 'Embedded cover scan';
      _total = coverTargets.length;
      _done = 0;
      _fast = 0;
      _deep = skipped;
      _failed = 0;
      _publish(force: true, throttleMs: 2000);
      final coverStart = DateTime.now();

      final controller = _ScanConcurrencyController(
        initialConcurrency: 2,
        maxConcurrency: 3,
      );
      var found = 0;
      var coverMissing = 0;

      final coverClient = http.Client();
      try {
        await _runWithConcurrency<Map<String, String>>(
          coverTargets,
          controller,
          (album, index) async {
            if (_cancelled) return;

            final albumId =
                _albumCacheKey(album, source: 'cover_scan_worker_album_id');
            final albumKey = _albumCoverScanKey(album);
            final tracks = albumTracks[albumId] ?? <drive.File>[];
            final fingerprint = _albumCoverScanFingerprint(album);

            final coverPath = await _probeAlbumEmbeddedCoverBackground(
              album,
              tracks,
              token,
              client: coverClient,
            );

            album[_embeddedCoverScanFingerprintKey] = fingerprint;
            if (coverPath != null && coverPath.isNotEmpty) {
              album['cover'] = coverPath;
              _applyAlbumCoverPathToTrackCacheBackground(tracks, coverPath);
              _sendAlbumCoverFoundBackground(albumId, coverPath);
              found++;
              debugPrint(
                'CoverScan saved albumKey=$albumKey bytes=${coverPath.isNotEmpty ? '1' : '0'}',
              );
            } else {
              coverMissing++;
              debugPrint('CoverScan not found albumKey=$albumKey');
            }

            _done++;
            _fast = found;
            _deep = skipped;
            _failed = coverMissing;
            _publish(throttleMs: 2000);
          },
        );
      } finally {
        coverClient.close();
      }

      debugPrint(
        'CoverScan complete found=$found missing=$coverMissing skipped=$skipped',
      );
      final coverElapsedMs =
          math.max(1, DateTime.now().difference(coverStart).inMilliseconds);
      final avgCoverMs = coverTargets.isEmpty
          ? 0
          : (coverElapsedMs / coverTargets.length).round();
      debugPrint(
        'ArtworkHydration perf albumsDone=${coverTargets.length} coversFound=$found avgCoverMs=$avgCoverMs skippedCached=$skipped noCover=$coverMissing',
      );

      await _metaStore.persistNow();
      await _persistAlbumsBackground(albums);

      _enrichAlbumsBackground(albums, albumTracks);
      await _metaStore.persistNow();
      await _persistAlbumsBackground(albums);
      debugPrint('UI refresh after cover scan');

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
    final folderIds = _albumCacheKey(album, source: 'fetch_tracks_album_id')
        .split(',')
        .where((id) => id.trim().isNotEmpty);

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

  Future<bool> _loadFastTextMetadataBackground(
    drive.File file,
    String token, {
    http.Client? client,
  }) async {
    try {
      final fallback = DriveUtils.getTrackMeta(file);
      final fastResult = await FastTagReader.read(
        file: file,
        token: token,
        readCover: false,
        client: client,
      );

      final hasFastText = fastResult != null && fastResult.hasUsefulText;
      final durationMs = _validDurationMsFromBackgroundValue(
        fastResult?.duration?.inMilliseconds,
      );

      _metaStore.putMemory(
        file,
        TrackMetadata(
          title: hasFastText && fastResult!.title?.trim().isNotEmpty == true
              ? fastResult.title!.trim()
              : fallback['title'] ?? file.name ?? 'Unknown',
          artist: hasFastText && fastResult!.artist?.trim().isNotEmpty == true
              ? fastResult.artist!.trim()
              : fallback['artist'] ?? 'Unknown Artist',
          album: hasFastText && fastResult!.album?.trim().isNotEmpty == true
              ? fastResult.album!.trim()
              : null,
          year: hasFastText ? fastResult!.year : null,
          genre: hasFastText ? fastResult!.genre : null,
          trackNumber: hasFastText ? fastResult!.trackNumber : null,
          discNumber: hasFastText ? fastResult!.discNumber : null,
          modifiedTime: file.modifiedTime?.toIso8601String(),
          size: file.size,
          durationMs: durationMs,
        ),
      );

      return true;
    } catch (_) {
      try {
        final fallback = DriveUtils.getTrackMeta(file);
        _metaStore.putMemory(
          file,
          TrackMetadata(
            title: fallback['title'] ?? file.name ?? 'Unknown',
            artist: fallback['artist'] ?? 'Unknown Artist',
            album: null,
            year: null,
            genre: null,
            trackNumber: null,
            discNumber: null,
            modifiedTime: file.modifiedTime?.toIso8601String(),
            size: file.size,
          ),
        );
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> _loadDeepMetadataBackground(
      drive.File file, String token) async {
    File? tempFile;

    try {
      final fileId = DriveUtils.effectiveId(file);
      if (fileId == null) return false;

      final fallback = DriveUtils.getTrackMeta(file);
      tempFile = await _downloadTrackToTempBackground(
          fileId, token, _audioExtensionFromFile(file));
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
          album: metadata.album?.trim().isNotEmpty == true
              ? metadata.album!.trim()
              : null,
          year: null,
          genre: null,
          trackNumber: metadata.trackNumber,
          discNumber: metadata.discNumber,
          modifiedTime: file.modifiedTime?.toIso8601String(),
          size: file.size,
        ),
      );

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
      if (coverPath != null &&
          coverPath.isNotEmpty &&
          (!(_isLocalCover(coverPath)) ||
              File(_localCoverPath(coverPath)).existsSync())) {
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
          modifiedTime:
              cached?.modifiedTime ?? track.modifiedTime?.toIso8601String(),
          size: cached?.size ?? track.size,
        ),
      );
    }
  }

  bool _isAlbumCoverScanStale(Map<String, String> album) {
    final fingerprint = _albumCoverScanFingerprint(album);
    final cachedFingerprint =
        _cleanBackgroundValue(album[_embeddedCoverScanFingerprintKey]);
    return cachedFingerprint != fingerprint;
  }

  Future<String?> _probeAlbumEmbeddedCoverBackground(
    Map<String, String> album,
    List<drive.File> tracks,
    String token, {
    http.Client? client,
  }) async {
    final albumKey = _albumCoverScanKey(album);

    final cachedCover = _firstCachedAlbumCoverPathBackground(tracks);
    if (cachedCover != null &&
        (!(_isLocalCover(cachedCover)) ||
            File(_localCoverPath(cachedCover)).existsSync())) {
      debugPrint('CoverScan found album=$albumKey from cache');
      return cachedCover;
    }

    for (final track in tracks.take(3)) {
      debugPrint(
        'CoverScan probe album=$albumKey track=${track.name ?? 'unknown'}',
      );
      final result = await FastTagReader.read(
        file: track,
        token: token,
        readCover: true,
        client: client,
      );
      final bytes = result?.coverBytes;
      if (bytes == null || bytes.isEmpty) continue;
      debugPrint('CoverScan found album=$albumKey bytes=${bytes.length}');
      final coverPath = await _saveEmbeddedCoverBackground(track, bytes);
      if (coverPath != null && coverPath.isNotEmpty) {
        return coverPath;
      }
    }

    return null;
  }

  String _cleanBackgroundValue(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty ||
        v.toLowerCase() == 'unknown' ||
        v.toLowerCase() == 'unknown artist') {
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
    if (has('electronic') || has('house') || has('techno') || has('dance'))
      return 'Electronic';
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
      final albumId = _albumCacheKey(album, source: 'enrich_album_id');
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

Future<File> _downloadTrackToTempBackground(
  String fileId,
  String token,
  String extension,
) async {
  final dir = await getTemporaryDirectory();
  final unique = DateTime.now().microsecondsSinceEpoch;
  final path =
      '${dir.path}/musix_deep_${_safeCacheNameGlobal(fileId)}_$unique$extension';
  final tempFile = File(path);

  final uri =
      Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
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

Future<String?> _saveEmbeddedCoverBackground(
    drive.File file, Uint8List bytes) async {
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
