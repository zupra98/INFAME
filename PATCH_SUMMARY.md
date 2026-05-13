# Drive Settings and Search Tab Fix - Summary

## Problem Analysis

### Drive Settings Issue
**Root Cause**: The `_fetchExplore()` method was called AFTER the Navigator.push() completed, using a post-frame callback. This meant the Drive tab widget was built with empty state (`_exploreItems.isEmpty` and `_loadingExplore = false`), showing "Loading your Drive folders..." forever without actually loading.

**Fix**: Moved `_fetchExplore()` call to BEFORE Navigator.push(), and added a guard to prevent duplicate loads if already loading or loaded.

### Search Tab Issue
**Root Cause**: The filtering variables (`showAlbums`, `showArtists`, `showSongs`, `showLiked`) were defined but NOT used in the actual section rendering. The code still checked `if (albums.isNotEmpty)` instead of `if (showAlbums && albums.isNotEmpty)`, so clicking category buttons updated state but didn't filter results.

**Fix**: Updated all section conditionals to use the `show*` variables, ensuring results are filtered by selected category.

## Files Changed

### 1. `lib/main.dart`

#### Drive Settings Fix (lines 2909-2946)
- **Changed**: `_openDriveSourcePage()` method
- **What**: Call `_fetchExplore(folderId: 'root')` BEFORE Navigator.push()
- **Added**: Guard to prevent duplicate loads: `if (_exploreItems.isEmpty && _exploreFolder == null && !_loadingExplore)`
- **Added**: Debug logging for Drive Settings opened, load started, folders already loaded

#### Drive Explorer Logging (lines 6007-6054)
- **Changed**: `_fetchExplore()` method
- **Added**: Debug logs for load started, load completed with counts, load failed
- **Added**: Filtered file count logging (folders vs tracks)

#### Drive Folder Selection Logging (lines 6074-6099)
- **Changed**: `_openExploreFolder()` method
- **Added**: Debug log for selected folder changed

#### Drive Scan Logging (line 5480)
- **Changed**: `_scanFolderToLibrary()` method
- **Added**: Debug log for scan started

#### Search Tab Fix (lines 7185-7806)
- **Changed**: `_buildSearchTab()` method
- **Fixed**: `showLiked` logic to only show in 'liked' mode (was showing in 'all' mode too)
- **Added**: Debug log for results rebuilt with category and counts
- **Added**: Debug logs for each category button tap
- **Added**: Debug log for query changed
- **Fixed**: Empty results check to include `showLiked && _likedTrackKeys.isEmpty`
- **Fixed**: Artists section conditional: `if (showArtists && visibleArtists.isNotEmpty)`
- **Fixed**: Albums section conditional: `if (showAlbums && albums.isNotEmpty)`
- **Note**: Songs and Liked sections already had correct conditionals

### 2. `lib/widgets/library_widgets.dart` (lines 1506-1564)
- **Added**: `_SearchModePill` widget class (already added in previous patch)
- **Purpose**: Clickable pill buttons for search category filtering

### 3. `lib/screens/drive_tab.dart`
- **No changes needed**: Already uses `_loadingExplore` and `_exploreItems` correctly

## State Flow

### Drive Settings
1. User opens Settings → Drive Settings
2. `_openDriveSourcePage()` is called
3. **Debug**: "[DriveSettings] opened"
4. Check: `_exploreItems.isEmpty && _exploreFolder == null && !_loadingExplore`
5. If true: Call `_fetchExplore(folderId: 'root')` immediately
6. **Debug**: "[DriveSettings] starting Drive folder load"
7. `_fetchExplore()` sets `_loadingExplore = true`
8. **Debug**: "[DriveExplore] load started for folder: root"
9. Navigator pushes Drive tab page
10. Drive tab shows loading spinner (because `_loadingExplore = true`)
11. API call completes, `_exploreItems` populated, `_loadingExplore = false`
12. **Debug**: "[DriveExplore] load completed: X items (Y folders, Z tracks)"
13. Drive tab shows folder list

### Search Tab
1. User types search query
2. **Debug**: "[Search] query changed: \"query\""
3. `_buildSearchTab()` rebuilds
4. **Debug**: "[Search] results rebuilt: category=all, albums=X, artists=Y, songs=Z, liked=W"
5. User clicks category button (e.g., "Albums")
6. **Debug**: "[Search] category selected: albums"
7. `setState(() => _searchViewMode = 'albums')`
8. `_buildSearchTab()` rebuilds
9. **Debug**: "[Search] results rebuilt: category=albums, albums=X, artists=Y, songs=Z, liked=W"
10. Only albums section renders (because `showAlbums = true`, others = false)

## State Variables

### Drive Settings
- **Loading state**: `_loadingExplore` (bool) - prevents infinite loading
- **Folder list**: `_exploreItems` (List<drive.File>) - populated by `_fetchExplore()`
- **Current folder**: `_exploreFolder` (drive.File?) - null = root
- **User auth**: `_user` (GoogleSignInAccount?) - required for API calls

### Search Tab
- **Selected category**: `_searchViewMode` (String) - 'all', 'albums', 'artists', 'songs', 'liked'
- **Search query**: `_searchQuery` (String)
- **Filter flags**: `showAlbums`, `showArtists`, `showSongs`, `showLiked` (bool, computed)

## Method Responsibilities

### Drive Settings
- **`_openDriveSourcePage()`**: Opens Drive Settings page, triggers folder load if needed
- **`_fetchExplore({required String folderId})`**: Loads Drive folders/files from API
- **`_openExploreFolder(drive.File folder)`**: Navigates into a folder
- **`_scanFolderToLibrary(drive.File rootFolder)`**: Scans folder and adds albums to library

### Search Tab
- **`_buildSearchTab()`**: Builds Search tab UI with filtered results
- **`_cachedVisibleAlbumsForQuery(String query)`**: Returns filtered albums
- **`_cachedVisibleSongsForQuery(String query)`**: Returns filtered songs
- **`_cachedVisibleArtistsForQuery(String query)`**: Returns filtered artists

## Debug Logs Added

### Drive Settings
- `[DriveSettings] opened`
- `[DriveSettings] starting Drive folder load`
- `[DriveSettings] folders already loaded or loading: items=X, loading=true/false`
- `[DriveExplore] user not signed in`
- `[DriveExplore] load started for folder: folderId`
- `[DriveExplore] load completed: X items (Y folders, Z tracks)`
- `[DriveExplore] load failed: error`
- `[DriveExplore] selected folder changed: folderName (id: folderId)`
- `[DriveScan] scan started for folder: folderName`

### Search Tab
- `[Search] query changed: "query"`
- `[Search] category selected: all/albums/artists/songs/liked`
- `[Search] results rebuilt: category=X, albums=Y, artists=Z, songs=W, liked=V`

## Validation Commands

```bash
# Format code
dart format lib/main.dart lib/screens/drive_tab.dart lib/widgets/library_widgets.dart

# Analyze for errors
flutter analyze

# Build debug APK
flutter build apk --debug
```

## String Search Results

- **"open search to load your drive folders"**: ✅ Not found (removed)
- **"Loading your Drive folders..."**: ✅ Found only in `drive_tab.dart` with proper loading logic

## Bottom Navigation

- **Width**: 70px per item (already fixed in previous patch)
- **Items**: Home, Search, Library (3 items × 70px = 210px)
- **Overflow**: Fixed (was 6px overflow with 74px width)
