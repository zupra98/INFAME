# Infame Local Files MVP Patch

Files changed:
- pubspec.yaml
- AndroidManifest.xml
- lib/main.dart
- lib/services/drive_utils.dart
- lib/services/local_file_source.dart
- lib/widgets/settings_widgets.dart

What it adds:
- Adds file_picker dependency.
- Adds Android media read permissions.
- Adds Settings -> Import local audio files.
- Imports selected local audio files into the same album/library model.
- Parses local title/artist/album/track number using audio_metadata_reader.
- Saves imported local library entries to SharedPreferences using the existing album/index stores.
- Plays local files through AudioSource.uri(Uri.file(path)) while Drive tracks still use DriveAudioSource.

Limitations in this MVP:
- Imports selected files, not whole folders yet.
- Local embedded cover extraction is not implemented yet; it keeps existing/fallback covers.
- If a local file is moved/deleted after import, playback will fail until it is re-imported.
- Keep this on a feature branch first and test before merging into main.

After copying files:
flutter pub get
dart format lib/main.dart lib/services/drive_utils.dart lib/services/local_file_source.dart lib/widgets/settings_widgets.dart
flutter analyze
flutter build apk --debug
