import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;

class TrackMetadata {
  final String title;
  final String artist;
  final String? album;
  final int? trackNumber;
  final int? discNumber;
  final String? coverPath;
  final String? year;
  final String? genre;
  final String? modifiedTime;
  final String? size;

  const TrackMetadata({
    required this.title,
    required this.artist,
    this.album,
    this.trackNumber,
    this.discNumber,
    this.coverPath,
    this.year,
    this.genre,
    this.modifiedTime,
    this.size,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'album': album,
        'trackNumber': trackNumber,
        'discNumber': discNumber,
        'coverPath': coverPath,
        'year': year,
        'genre': genre,
        'modifiedTime': modifiedTime,
        'size': size,
      };

  factory TrackMetadata.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      return int.tryParse(value.toString());
    }

    String? parseString(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    return TrackMetadata(
      title: parseString(json['title']) ?? 'Unknown',
      artist: parseString(json['artist']) ?? 'Unknown Artist',
      album: parseString(json['album']),
      trackNumber: parseInt(json['trackNumber']),
      discNumber: parseInt(json['discNumber']),
      coverPath: parseString(json['coverPath']),
      year: parseString(json['year']),
      genre: parseString(json['genre']),
      modifiedTime: parseString(json['modifiedTime']),
      size: parseString(json['size']),
    );
  }

  Map<String, String> toMap() {
    final map = <String, String>{
      'title': title.trim().isEmpty ? 'Unknown' : title.trim(),
      'artist': artist.trim().isEmpty ? 'Unknown Artist' : artist.trim(),
    };

    void add(String key, String? value) {
      final cleaned = value?.trim() ?? '';
      if (cleaned.isNotEmpty) map[key] = cleaned;
    }

    add('album', album);
    add('coverPath', coverPath);
    add('year', year);
    add('genre', genre);
    add('modifiedTime', modifiedTime);
    add('size', size);

    if (trackNumber != null) {
      map['trackNumber'] = trackNumber.toString();
    }

    if (discNumber != null) {
      map['discNumber'] = discNumber.toString();
    }

    return map;
  }

  bool matchesFile(drive.File file) {
    final currentModifiedTime = file.modifiedTime?.toIso8601String();
    final currentSize = file.size;

    if (modifiedTime != null &&
        currentModifiedTime != null &&
        modifiedTime != currentModifiedTime) {
      return false;
    }

    if (size != null && currentSize != null && size != currentSize) {
      return false;
    }

    return true;
  }
}

class TrackReadResult {
  final String? title;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final int? discNumber;
  final String? year;
  final String? genre;
  final Uint8List? coverBytes;

  const TrackReadResult({
    this.title,
    this.artist,
    this.album,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genre,
    this.coverBytes,
  });

  bool get hasUsefulText {
    bool useful(String? value) {
      final cleaned = value?.trim() ?? '';
      if (cleaned.isEmpty) return false;

      final lower = cleaned.toLowerCase();
      return lower != 'unknown' &&
          lower != 'unknown artist' &&
          lower != 'untitled';
    }

    return useful(title) ||
        useful(artist) ||
        useful(album) ||
        useful(year) ||
        useful(genre) ||
        trackNumber != null ||
        discNumber != null;
  }
}