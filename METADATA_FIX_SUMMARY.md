# Home and Library Metadata Display Fix

## Problem

Album cards on Home and Library screens were displaying inconsistent metadata:
- Sometimes showing album name
- Sometimes showing artist name
- Sometimes showing "Disc 3" or folder names
- Sometimes just showing "Album"

The subtitle was hardcoded to "Album" instead of showing the artist name.

## Root Cause

### Issue 1: Hardcoded "Album" Text
The `_HomeAlbumCard` widget (used on Home screen) had a hardcoded string "Album" as the subtitle instead of displaying the artist name.

**Location**: `lib/widgets/library_widgets.dart` line 582

### Issue 2: Raw Album Data
The Home tab was passing raw album maps from `_albums` list directly to the display widgets, without resolving the metadata through the proper resolution functions.

The raw album maps contain:
- `name` - folder name (e.g., "Artist - Album", "Disc 3", etc.)
- `displayName` - may or may not be populated
- `artist` - may or may not be populated

### Issue 3: Inconsistent Metadata Resolution
The Library tab was correctly using `_resolvedAlbumMap()` to resolve metadata, but the Home tab was not.

## Solution

### Fix 1: Show Artist Name Instead of "Album"
Changed `_HomeAlbumCard` widget to display the artist name in the subtitle.

**File**: `lib/widgets/library_widgets.dart`
**Lines**: 512, 582-584

**Before**:
```dart
final artist = info['artist'] ?? '';
...
Text(
  'Album',  // Hardcoded!
  style: GoogleFonts.inter(...)
)
```

**After**:
```dart
final artist = info['artist'] ?? 'Unknown Artist';
...
Text(
  artist,  // Dynamic artist name
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: GoogleFonts.inter(...)
)
```

### Fix 2: Use Resolved Album Metadata on Home Tab
Updated all `_HomeAlbumRow` instances in the Home tab to use `_resolvedAlbumMap()` before displaying albums.

**File**: `lib/screens/home_tab.dart`
**Lines**: 158, 187, 216, 245

**Before**:
```dart
_HomeAlbumRow(
  albums: primaryAlbums,  // Raw album data
  onTap: _openAlbumByBrain,
  isDarkMode: _isDarkMode,
)
```

**After**:
```dart
_HomeAlbumRow(
  albums: primaryAlbums.map(_resolvedAlbumMap).toList(),  // Resolved metadata
  onTap: _openAlbumByBrain,
  isDarkMode: _isDarkMode,
)
```

## How Metadata Resolution Works

### `_resolvedAlbumMap()` Function
**Location**: `lib/main.dart` lines 2343-2360

This function creates a new album map with properly resolved metadata:

1. **Album Title** (`displayName`): Resolved via `_resolvedAlbumTitle()`
   - Priority: metadata from tracks → saved brain data → folder name fallback
   - Filters out weak titles like "Disc 3", "Unknown Album", etc.

2. **Artist Name** (`artist`): Resolved via `_resolvedAlbumArtist()`
   - Priority: metadata from tracks → saved brain data → folder parsing
   - Filters out bad artist names like "Unknown Artist", "Various", etc.

3. **Cover Art** (`cover`/`coverUrl`): Resolved via `_resolvedAlbumCover()`
   - Priority: direct album/brain cover → track metadata → embedded covers

### Resolution Chain

```
Raw Album Data
    ↓
_resolvedAlbumMap()
    ↓
├─→ _resolvedAlbumTitle()
│   ├─→ _albumTitleFromRecords() (from track metadata)
│   ├─→ _albumTitleFromTracks() (from track files)
│   └─→ Folder name fallback
│
├─→ _resolvedAlbumArtist()
│   ├─→ _albumArtistFromRecords() (from track metadata)
│   ├─→ _albumArtistFromTracks() (from track files)
│   └─→ Folder parsing fallback
│
└─→ _resolvedAlbumCover()
    ├─→ Album/brain cover paths
    ├─→ Track metadata covers
    └─→ Embedded cover extraction
    ↓
Resolved Album Map
    ↓
Display Widgets
```

## Files Changed

1. **`lib/widgets/library_widgets.dart`**
   - Fixed `_HomeAlbumCard` to show artist name instead of "Album"
   - Changed artist fallback from empty string to "Unknown Artist"

2. **`lib/screens/home_tab.dart`**
   - Updated "Recently Played" row to use resolved metadata
   - Updated "Your Library" row to use resolved metadata
   - Updated "Explore" row to use resolved metadata
   - Updated "Heavy Rotation" row to use resolved metadata

## Expected Behavior After Fix

### Home Screen
Every album card now shows:
1. **Artwork** (top)
2. **Album Name** (below artwork) - resolved from metadata or folder
3. **Artist Name** (below album name) - resolved from metadata or folder

### Library Screen
Already working correctly - shows:
1. **Artwork** (top)
2. **Album Name** (below artwork) - resolved from metadata
3. **Artist Name** (below album name) - resolved from metadata, with fallback to year/genre if artist is empty

## Debug Logging

The resolution functions already include debug logging:
- `AlbumDisplay resolved key=... title="..." artist="..." titleSource=...`
- `AlbumDisplay resolved key=... artist="..." artistSource=...`
- `AlbumCover key=... source=... hasBytes=...`

These logs show:
- Which album is being resolved
- What title/artist was resolved
- Where the metadata came from (metadata/saved/folder_fallback)

## Validation

To verify the fix works:

1. Open the app and navigate to Home tab
2. Check "Recently Played" section - should show album names and artist names
3. Check "Your Library" section - should show album names and artist names
4. Check "Explore" section - should show album names and artist names
5. Navigate to Library tab
6. Check album grid - should show album names and artist names consistently

No more:
- "Album" as subtitle
- "Disc 3" as album name
- Inconsistent metadata display
- Missing artist names
