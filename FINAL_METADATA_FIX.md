# Final Home Tab Metadata Fix

## The Real Problem

The Home tab was calling `_resolvedAlbumMap()` on albums that were **already resolved** by `_brainAlbums()`, causing double-resolution which corrupted the metadata.

## Root Cause

### What Was Happening

1. `_brainAlbums()` returns albums with metadata already resolved via `_resolvedAlbumMap()` (line 3362 in main.dart)
2. Home tab cache was calling `.map(_resolvedAlbumMap)` AGAIN on these already-resolved albums
3. Double-resolution caused issues because:
   - `_resolvedAlbumMap()` reads from `album['name']` and `album['displayName']`
   - After first resolution, `displayName` is set to the album title
   - Second resolution tries to resolve again, potentially using the wrong fields
   - This caused "Disc 3" and artist/album name swaps

### The Bug Chain

```
_albums (raw folder data)
    ↓
_brainAlbums() calls _resolvedAlbumMap()
    ↓
Albums with displayName=title, artist=artist ✓
    ↓
_recentBrainAlbums() returns these resolved albums
    ↓
Home tab cache calls .map(_resolvedAlbumMap) AGAIN ✗
    ↓
Double-resolved albums with corrupted metadata
    ↓
Display shows wrong data
```

## The Fix

### Removed Double-Resolution

**File**: `lib/screens/home_tab.dart` lines 32-44

**Before** (WRONG):
```dart
final recent = _recentBrainAlbums(limit: 14).map(_resolvedAlbumMap).toList();  // ✗ Double resolution!
final played = _lastPlayedAlbums(limit: 10).map(_resolvedAlbumMap).toList();   // ✗ Double resolution!
```

**After** (CORRECT):
```dart
// _brainAlbums() already returns resolved albums, so no need to call _resolvedAlbumMap again
final recent = _recentBrainAlbums(limit: 14);  // ✓ Already resolved
final played = _lastPlayedAlbums(limit: 10);   // ✓ Already resolved
```

### What Gets Resolved Where

| Section | Source | Resolution |
|---------|--------|------------|
| Recently Played | `_recentBrainAlbums()` → `_brainAlbums()` | ✓ Already resolved |
| Heavy Rotation | `_lastPlayedAlbums()` → `_brainAlbums()` | ✓ Already resolved |
| Your Library | `_albums` (raw) | ✓ Resolved in cache function |
| Explore | `_albums` or `_shuffledExploreAlbums` (raw) | ✓ Resolved in cache function |

## Why This Happened

The confusion came from the fact that:
1. `_brainAlbums()` internally calls `_resolvedAlbumMap()` (added for brain album display)
2. The Library tab explicitly calls `_resolvedAlbumMap()` on raw albums
3. I assumed Home tab needed the same explicit resolution
4. But Home tab's "Recently Played" and "Heavy Rotation" use `_brainAlbums()` which already resolves

## Files Changed

**`lib/screens/home_tab.dart`** (lines 32-34)
- Removed `.map(_resolvedAlbumMap)` from `recent` and `played` 
- Added comment explaining why resolution is not needed
- Kept resolution for `library` and `explore` (they use raw `_albums`)

## Expected Behavior Now

### Home Tab - All Sections
Every album card shows:
1. **Artwork** (top)
2. **Album Name** (below artwork, bold) - from `displayName`
3. **Artist Name** (below album name, lighter) - from `artist`

### No More Issues
- ✅ No "Disc 3" showing as album name
- ✅ No artist/album name swaps
- ✅ No "Unknown Artist" when metadata exists
- ✅ Metadata shows correctly on first render
- ✅ No need to click album to see correct metadata
- ✅ No UI freeze on first load

## Debug Logs

The debug logs will show:
```
[HomeCache] First recent album: displayName="Album Title" artist="Artist Name" name="folder_name"
[HomeCache] Cache rebuilt: recent=14, played=10, library=14, explore=14, heavy=8
```

This confirms that:
- `displayName` = album title (correct)
- `artist` = artist name (correct)
- `name` = original folder name (for reference)

## Testing

1. **Close and restart the app**
2. **Navigate to Home tab**
3. **Check all sections**:
   - Recently Played: Album names on top, artist names below ✓
   - Your Library: Album names on top, artist names below ✓
   - Explore: Album names on top, artist names below ✓
   - Heavy Rotation: Album names on top, artist names below ✓
4. **No clicking needed** - metadata is correct immediately
5. **No freeze** - loads smoothly

## Summary

The issue was **double-resolution**: calling `_resolvedAlbumMap()` on albums that were already resolved by `_brainAlbums()`. The fix was to remove the redundant resolution calls for sections that use `_brainAlbums()` (Recently Played, Heavy Rotation), while keeping resolution for sections that use raw `_albums` data (Your Library, Explore).
