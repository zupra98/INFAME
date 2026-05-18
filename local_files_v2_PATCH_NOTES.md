# Infame Local Files v2 Patch

Adds local folder support on top of the working Local Files MVP.

## What changed

- Settings now has:
  - Import local audio files
  - Add local music folder
  - Rescan local folders
  - Remove missing local files
- Selected local folders are saved with SharedPreferences.
- Local folder scan is recursive.
- Supported local extensions:
  - mp3, flac, wav, m4a, aac, ogg, opus, wma
- Local metadata scan now reuses the existing metadata cache with file size + modified time freshness.
- Local album covers:
  - tries folder images first: cover/folder/front/album/artwork jpg/png/jpeg
  - then tries embedded artwork from the first 1-3 tracks in an album
  - cached embedded covers are saved under the app documents directory
- Missing local file cleanup removes library index entries for deleted/moved local files.

## Important design

The real logic stays in:

lib/services/local_file_source.dart

main.dart only gets:
- one state field: _selectedLocalFolders
- one initState call: _loadSelectedLocalFolders()

This avoids making main.dart huge again.

## Files included

- lib/main.dart
- lib/services/local_file_source.dart
- lib/services/drive_utils.dart
- lib/widgets/settings_widgets.dart
- AndroidManifest.xml

## Apply on a branch

git checkout -b feature/local-files-v2

Then copy these files into your project and run:

flutter pub get
dart format lib/main.dart lib/services/local_file_source.dart lib/services/drive_utils.dart lib/widgets/settings_widgets.dart
flutter analyze
flutter build apk --debug

## Manual test checklist

1. Open Settings.
2. Tap Add local music folder.
3. Choose a folder containing albums.
4. Confirm local albums appear in Library.
5. Confirm local songs play.
6. Confirm Drive songs still play.
7. Restart app; selected local folders remain.
8. Add a new file to the folder and tap Rescan local folders.
9. Delete/move a local file and tap Remove missing local files.
10. Confirm no duplicate tracks after repeated rescans.

## Notes

Folder picking depends on the Android file picker/provider. Some Android folders may be restricted by scoped storage. If a folder cannot be scanned, try Music/Downloads or a user-created folder.
