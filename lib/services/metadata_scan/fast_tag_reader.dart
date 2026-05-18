part of '../../main.dart';

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
      return _readMp3(
        id,
        token,
        sizeText: file.size,
        readCover: readCover,
        client: client,
      );
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
        'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
      );
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
                  448,
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
                  256,
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
                      384,
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
                      160,
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
                          320,
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
                          160,
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
    final bytes = await _range(
      fileId,
      token,
      0,
      largerChunk - 1,
      client: client,
    );
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
        year = _parseYear(
              comments['DATE'] ?? comments['YEAR'] ?? comments['ORIGINALYEAR'],
            ) ??
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
      final text = utf8.decode(
        _slice(b, pos, pos + length),
        allowMalformed: true,
      );
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
    final first = await _range(
      fileId,
      token,
      0,
      largerChunk - 1,
      client: client,
    );
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
      final tailResult = _parseM4a(
        tail,
        allowIlistScan: true,
        readCover: readCover,
      );
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
        _walkMp4Boxes(
          b,
          pos + header,
          boxEnd,
          found,
          depth + 1,
          readCover: readCover,
        );
      } else if (type == 'meta') {
        _walkMp4Boxes(
          b,
          pos + header + 4,
          boxEnd,
          found,
          depth + 1,
          readCover: readCover,
        );
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
