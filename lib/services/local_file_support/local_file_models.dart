part of '../../main.dart';

// â”€â”€â”€ Local Files Source â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Keeps local files inside the same album/track model as Drive tracks by
// representing them as drive.File objects with source=local app properties.
//
// v2 adds:
// - selected local folders
// - recursive folder rescans
// - unchanged-file metadata cache reuse
// - folder.jpg/cover.jpg artwork
// - light embedded artwork fallback
// - missing-file cleanup

const String _localFoldersPrefsKey = 'infame_selected_local_folders_v1';
const MethodChannel _localMusicChannel = MethodChannel('musix/local_music');

class _LocalAudioEntry {
  const _LocalAudioEntry({
    required this.sourceRef,
    required this.displayName,
    this.importBatchId = '',
    this.importGroupKey = '',
    this.importGroupTitle = '',
    this.parentFolderRef = '',
    this.relativePath = '',
    this.size,
    this.modifiedTimeMs,
    this.mimeType = '',
    this.isContentUri = false,
  });

  final String sourceRef;
  final String displayName;
  final String importBatchId;
  final String importGroupKey;
  final String importGroupTitle;
  final String parentFolderRef;
  final String relativePath;
  final int? size;
  final int? modifiedTimeMs;
  final String mimeType;
  final bool isContentUri;
}

const Set<String> _supportedLocalAudioExtensions = <String>{
  'mp3',
  'flac',
  'wav',
  'm4a',
  'aac',
  'ogg',
  'opus',
  'wma',
  'alac',
  'aiff',
  'aif',
};

const Set<String> _ignoredLocalExtensions = <String>{
  'cue',
  'jpg',
  'jpeg',
  'png',
  'txt',
  'log',
  'm3u',
  'm3u8',
};

const List<String> _localFolderCoverNames = <String>[
  'cover.jpg',
  'folder.jpg',
  'front.jpg',
  'album.jpg',
  'artwork.jpg',
  'cover.jpeg',
  'folder.jpeg',
  'front.jpeg',
  'album.jpeg',
  'artwork.jpeg',
  'cover.png',
  'folder.png',
  'front.png',
  'album.png',
  'artwork.png',
];
