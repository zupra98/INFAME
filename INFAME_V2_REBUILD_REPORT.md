# INFAME v2 Clean Rebuild Report

## Migration map

| Old reference file / feature | New target file(s) | Strategy |
| --- | --- | --- |
| `lib/main.dart` app bootstrap, globals, main screen state | `lib/main.dart`, `lib/constants/app_constants.dart`, `lib/app/infame_app.dart`, `lib/controllers/*.dart`, `lib/services/*_service.dart` | Split into feature-owned Dart parts while preserving existing behavior and private state access. |
| `lib/widgets/player_shell_widgets.dart` MaterialApp and shell/navigation | `lib/app/infame_app.dart`, `lib/app/app_shell.dart` | Move app root and shell separately. |
| `lib/screens/home_tab.dart` Home UI | `lib/screens/home_screen.dart`, `lib/widgets/home/home_sections.dart` | Split screen extension from home section/card widgets. |
| `lib/screens/library_tab.dart` Library tab | `lib/screens/library_screen.dart` | Move/rename. |
| `lib/screens/drive_tab.dart` Drive explorer UI | `lib/screens/drive_screen.dart` | Move/rename. |
| `lib/widgets/library_widgets.dart` shared settings/home/album/nav widgets | `lib/widgets/settings/settings_shared_widgets.dart`, `lib/widgets/home/home_cards.dart`, `lib/widgets/album/album_cards.dart`, `lib/widgets/shared/navigation_widgets.dart` | Split by UI responsibility. |
| `lib/widgets/player_widgets.dart` player art, lyrics, queue, mini player, full player | `lib/widgets/player/*.dart` | Split by player responsibility. |
| `lib/services/local_file_source.dart` local folder/file import, SAF scan, local metadata/artwork | `lib/services/local_file_support/*.dart` | Split by local source responsibility. |
| `lib/services/metadata_service.dart` metadata cache, tag reader, foreground scan task | `lib/services/metadata_scan/*.dart` | Split store, reader, and scan task. |
| Drive auth/client/audio source/audio handler | `lib/services/auth_service.dart`, `lib/services/drive_audio_source.dart`, `lib/services/playback_service.dart` | Move/rename without behavior changes. |
| Main library persistence/index/history/metadata methods | `lib/controllers/library_controller.dart`, `lib/controllers/library_index_controller.dart`, `lib/services/library_persistence_service.dart`, `lib/controllers/library_brain_controller.dart` | Move into extensions on `_MainScreenState`. |
| Playback queue/autoadvance/just_audio coordination | `lib/controllers/player_controller.dart`, `lib/controllers/player_autoadvance_controller.dart`, `lib/services/playback_controller_service.dart` | Move into extensions; preserve queue and autoadvance logic. |
| Artwork lookup/apply/revert | `lib/controllers/artwork_controller.dart`, `lib/services/artwork_service.dart` | Split lookup from apply/revert UI coordination. |
| Palette/dynamic colors | `lib/services/palette_service.dart`, `lib/utils/color_utils.dart` | Move color extraction controller and pure color helpers. |
| Existing models | `lib/models/track_model.dart`, `lib/models/player_state.dart`, etc. | Preserve existing `TrackMetadata`; add small typed model placeholders for future edits. |

## Notes

- The first pass prioritizes compile safety and behavior preservation over a complete public API rewrite.
- Services/controllers are separated by file ownership, but several remain Dart `part` files so fragile private state does not need to be re-threaded through new APIs in one risky jump.
- `android/app/google-services.json` stays ignored by git. If present in the reference, it may be copied locally for Android/Firebase compatibility.
