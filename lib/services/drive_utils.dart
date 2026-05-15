part of '../main.dart';

// ─── Safe Static Utils ──────────────────────────────────────────────────────
class DriveUtils {
  static const String localSourcePrefix = 'local:';

  static bool isLocalFile(drive.File f) {
    final id = f.id ?? '';
    final source = f.appProperties?['source'] ?? f.properties?['source'] ?? '';
    return id.startsWith(localSourcePrefix) || source == 'local';
  }

  static String? localPath(drive.File f) {
    final direct = f.appProperties?['path'] ??
        f.appProperties?['localPath'] ??
        f.properties?['path'] ??
        f.properties?['localPath'];
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();

    final id = f.id ?? '';
    if (id.startsWith(localSourcePrefix)) {
      final encoded = id.substring(localSourcePrefix.length);
      return Uri.decodeComponent(encoded);
    }
    return null;
  }

  static String? localSourceRef(drive.File f) {
    final direct = f.appProperties?['path'] ??
        f.appProperties?['localPath'] ??
        f.appProperties?['localUri'] ??
        f.properties?['path'] ??
        f.properties?['localPath'] ??
        f.properties?['localUri'];
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();

    final id = f.id ?? '';
    if (id.startsWith(localSourcePrefix)) {
      final encoded = id.substring(localSourcePrefix.length);
      return Uri.decodeComponent(encoded);
    }
    return null;
  }

  static bool isContentUriString(String value) {
    final lower = value.trim().toLowerCase();
    return lower.startsWith('content://');
  }

  static Uri? localAudioUri(drive.File f) {
    final ref = localSourceRef(f);
    if (ref == null || ref.trim().isEmpty) return null;
    if (isContentUriString(ref)) return Uri.parse(ref);
    return Uri.file(ref);
  }

  static String localIdForPath(String path) {
    return localIdForSource(path);
  }

  static String localIdForSource(String source) {
    return '$localSourcePrefix${Uri.encodeComponent(source)}';
  }

  static String? effectiveId(drive.File f) {
    if (f.mimeType == 'application/vnd.google-apps.shortcut' &&
        f.shortcutDetails?.targetId != null) {
      return f.shortcutDetails!.targetId;
    }
    return f.id;
  }

  static String? effectiveMimeType(drive.File f) {
    if (f.mimeType == 'application/vnd.google-apps.shortcut' &&
        f.shortcutDetails?.targetMimeType != null) {
      return f.shortcutDetails!.targetMimeType;
    }
    return f.mimeType;
  }

  static bool isFolder(drive.File f) {
    return effectiveMimeType(f) == 'application/vnd.google-apps.folder';
  }

  static bool isAudio(drive.File f) {
    final n = (f.name ?? '').toLowerCase();
    return n.endsWith('.mp3') ||
        n.endsWith('.flac') ||
        n.endsWith('.wav') ||
        n.endsWith('.m4a') ||
        n.endsWith('.aac') ||
        n.endsWith('.ogg') ||
        n.endsWith('.wma') ||
        n.endsWith('.opus') ||
        n.endsWith('.alac') ||
        n.endsWith('.aiff') ||
        n.endsWith('.aif');
  }

  static Map<String, String> getTrackMeta(drive.File f) {
    final cached = _metaStore.peekFresh(f) ?? _metaStore.peek(f);
    if (cached != null) return cached.toMap();
    String title = f.name ?? 'Unknown';
    title = title.replaceAll(
      RegExp(
        r'\.(mp3|flac|wav|m4a|aac|ogg|wma|opus|alac|aiff|aif)$',
        caseSensitive: false,
      ),
      '',
    );

    String artist = 'Unknown Artist';

    title = title.replaceFirst(RegExp(r'^\s*\d+[\s\.\-_]*'), '').trim();

    if (title.contains('-')) {
      final parts = title.split('-');
      artist = parts[0].trim();
      title = parts.sublist(1).join('-').trim();
    }

    return {
      'title': title.isEmpty ? f.name ?? 'Unknown' : title,
      'artist': artist.isEmpty ? 'Unknown Artist' : artist,
    };
  }

  static String audioExtension(drive.File f) {
    final name = (f.name ?? '').toLowerCase().trim();
    final match = RegExp(r'\.([a-z0-9]+)$').firstMatch(name);
    final ext = match?.group(1) ?? '';
    if (ext == 'm4a' || ext == 'mp4' || ext == 'aac') return 'AAC';
    if (ext == 'flac') return 'FLAC';
    if (ext == 'wav') return 'WAV';
    if (ext == 'ogg') return 'OGG';
    if (ext == 'wma') return 'WMA';
    if (ext == 'opus') return 'OPUS';
    if (ext == 'alac') return 'ALAC';
    if (ext == 'aiff' || ext == 'aif') return 'AIFF';
    if (ext == 'mp3') return 'MP3';
    return ext.isEmpty ? 'AUDIO' : ext.toUpperCase();
  }

  static bool isLosslessAudio(drive.File f) {
    final ext = audioExtension(f);
    return ext == 'FLAC' || ext == 'WAV' || ext == 'ALAC' || ext == 'AIFF';
  }

  static int? estimatedBitrateKbps(drive.File f, Duration? duration) {
    final sizeBytes = int.tryParse(f.size ?? '');
    if (sizeBytes == null || sizeBytes <= 0) return null;
    if (duration == null || duration.inMilliseconds <= 0) return null;

    final seconds = duration.inMilliseconds / 1000.0;
    if (seconds <= 0) return null;

    return ((sizeBytes * 8) / seconds / 1000).round();
  }

  static int? roundedCommonBitrateKbps(int? kbps) {
    if (kbps == null || kbps <= 0) return null;
    const common = [64, 96, 128, 160, 192, 224, 256, 320];
    var best = common.first;
    var diff = (kbps - best).abs();
    for (final value in common.skip(1)) {
      final d = (kbps - value).abs();
      if (d < diff) {
        best = value;
        diff = d;
      }
    }
    return diff <= 28 ? best : kbps;
  }

  static String audioQualityLabel(drive.File f, Duration? duration) {
    final ext = audioExtension(f);
    final rawKbps = estimatedBitrateKbps(f, duration);
    final kbps = ext == 'MP3' || ext == 'AAC' || ext == 'OGG'
        ? roundedCommonBitrateKbps(rawKbps)
        : rawKbps;

    if (ext == 'FLAC') {
      return kbps == null
          ? 'FLAC • Lossless'
          : 'FLAC • Lossless • ${kbps} kbps';
    }

    if (ext == 'WAV') {
      return kbps == null ? 'WAV • Lossless' : 'WAV • Lossless • ${kbps} kbps';
    }

    if (kbps == null) return ext;

    final quality = kbps >= 300
        ? 'Very high'
        : kbps >= 240
            ? 'High'
            : kbps >= 160
                ? 'Good'
                : kbps >= 128
                    ? 'Standard'
                    : 'Low';

    return '$ext • ${kbps} kbps • $quality';
  }
}
