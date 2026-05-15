part of '../main.dart';

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

String _normalizeAlbumKeySegment(String value) {
  final cleaned = value.trim();
  if (cleaned.isEmpty) return '';
  final parts = cleaned
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  if (parts.isEmpty) return '';
  return parts.join(',');
}

String _firstNonEmptyString(Iterable<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return '';
}

extension _MainFormatHelpersExtension on _MainScreenState {
  String _formatDurationMsFromPart(int ms) {
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

  String _formatDurationLabelFromPart(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes
        .remainder(60)
        .toString()
        .padLeft(hours > 0 ? 2 : 1, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }
}
