# Folder Name Parsing Fix - Album/Artist Swap

## The Real Problem

The metadata was showing **artist names as album titles** and **album titles as artist names** because:

1. **Folder naming convention**: Your folders are named "Album - Artist" (e.g., "Petestrumentals - Pete Rock", "Donuts - J Dilla")
2. **Parser assumption**: The `_artistAlbumFromFolder()` function assumed "Artist - Album" format
3. **Result**: Metadata was parsed backwards and saved to brain data with swapped values

## Evidence from Logs

```
I/flutter: AlbumDisplay resolved title="J Dilla" artist="Donuts" titleSource=saved
I/flutter: AlbumDisplay resolved title="Pete Rock" artist="Petestrumentals" titleSource=saved
```

These should be:
- Title: "Donuts", Artist: "J Dilla"
- Title: "Petestrumentals", Artist: "Pete Rock"

But they were swapped because the folder names were parsed incorrectly.

## The Fix

### Part 1: Fix Folder Parsing Logic

**File**: `lib/main.dart` lines 2972-2990

**Before** (WRONG - assumed Artist - Album):
```dart
final parts = cleaned.split(RegExp(r'\s+[–—-]\s+'));
if (parts.length < 2) return const <String, String>{};

final artist = _cleanBrainValue(parts.first);  // First part = artist ✗
final album = _cleanBrainValue(parts.sublist(1).join(' - '));  // Second part = album ✗
```

**After** (CORRECT - assumes Album - Artist):
```dart
final parts = cleaned.split(RegExp(r'\s+[–—-]\s+'));
if (parts.length < 2) return const <String, String>{};

// Assume format is "Album - Artist" (not "Artist - Album")
final album = _cleanBrainValue(parts.first);  // First part = album ✓
final artist = _cleanBrainValue(parts.sublist(1).join(' - '));  // Second part = artist ✓
```

### Part 2: Fix Existing Brain Data

**File**: `lib/main.dart` lines 3121-3160

Added `_rebuildBrainWithCorrectParsing()` method that:
1. Checks all saved brain data for swapped metadata
2. Re-parses folder names with correct logic
3. Detects if current displayName looks like an artist and current artist looks like an album
4. Swaps them back to correct values
5. Saves the fixed brain data

**How it works**:
```dart
void _rebuildBrainWithCorrectParsing() {
  // For each album in brain data:
  // 1. Re-parse folder name with CORRECT logic
  // 2. Compare current saved values with new parsed values
  // 3. If they look swapped (displayName contains artist, artist contains album)
  // 4. Swap them back
  // 5. Save fixed brain data
}
```

**Called from**: `_loadLibraryBrainAndHistory()` after brain data is loaded (line 3114)

## Folder Name Format Examples

Your folder naming convention (now correctly supported):
- ✓ "Petestrumentals - Pete Rock" → Album: Petestrumentals, Artist: Pete Rock
- ✓ "Donuts - J Dilla" → Album: Donuts, Artist: J Dilla
- ✓ "Instrumentals - Clams Casino" → Album: Instrumentals, Artist: Clams Casino
- ✓ "Tutankhamen_ Valley of the Kings - 9th Wonder" → Album: Tutankhamen: Valley of the Kings, Artist: 9th Wonder

Old assumption (now fixed):
- ✗ "Pete Rock - Petestrumentals" → Would parse as Album: Petestrumentals, Artist: Pete Rock
- ✗ "J Dilla - Donuts" → Would parse as Album: Donuts, Artist: J Dilla

## What Happens on Next App Start

1. **App loads brain data** from SharedPreferences
2. **`_rebuildBrainWithCorrectParsing()` runs** automatically
3. **Detects swapped metadata**:
   - Finds "Pete Rock" in displayName field, "Petestrumentals" in artist field
   - Re-parses "Petestrumentals - Pete Rock" → Album: Petestrumentals, Artist: Pete Rock
   - Detects swap (displayName contains "Pete Rock", artist contains "Petestrumentals")
   - Swaps them: displayName = "Petestrumentals", artist = "Pete Rock"
4. **Saves fixed brain data**
5. **Home tab displays correct metadata** immediately

## Debug Logs to Watch For

```
[BrainFix] Checking for swapped metadata in 6 albums
[BrainFix] Fixed 1BI-NCNwvY32kCYrZvmnzBrA9a2bi7KRD: "9th Wonder" by "Tutankhamen_ Valley of the Kings" → "Tutankhamen_ Valley of the Kings" by "9th Wonder"
[BrainFix] Fixed 1B5SSrtOIZGf6nzh21dsn05VSJ5T6qpvQ: "Clams Casino" by "Instrumentals" → "Instrumentals" by "Clams Casino"
[BrainFix] Fixed 1xgTrWVYF73GJ9dt6we9xj_267_1PqQwI: "J Dilla" by "Donuts" → "Donuts" by "J Dilla"
[BrainFix] Fixed 1B4XuC3NQkKmy-2JaDjsxW0Gh2yGepWFu: "Pete Rock" by "Petestrumentals" → "Petestrumentals" by "Pete Rock"
[BrainFix] Fixed 4 albums with swapped metadata
```

## Files Changed

1. **`lib/main.dart`** (lines 2981-2983)
   - Swapped `artist` and `album` assignment in `_artistAlbumFromFolder()`
   - Added comment explaining the format assumption

2. **`lib/main.dart`** (lines 3114, 3121-3160)
   - Added `_rebuildBrainWithCorrectParsing()` method
   - Called from `_loadLibraryBrainAndHistory()` to fix existing data

## Expected Result

After restarting the app:
- ✅ "Petestrumentals" shows as album name, "Pete Rock" shows as artist
- ✅ "Donuts" shows as album name, "J Dilla" shows as artist
- ✅ "Instrumentals" shows as album name, "Clams Casino" shows as artist
- ✅ No more swapped metadata
- ✅ No more "Disc 3" showing (that's a different album with no dash in folder name)
- ✅ Metadata is correct on first render, no clicking needed

## Note on "Disc 3" Album

The "Disc 3" album (key: `1Blq5uDWz6TkNIf8Rj4csx_s0UA4AgL0b,1D0A391vorEPBSIu2RkrEl1ONheM9-Uz4,1bK70ncCZGYJheY3EdbGXGI9N_h9uRrIv`) shows:
```
title="Disc 3" artist="" titleSource=folder_fallback
```

This album has no dash in the folder name, so folder parsing returns empty. The metadata resolution falls back to the raw folder name "Disc 3". This will be fixed once you scan metadata from the actual audio files, which will provide the real album title and artist from ID3 tags.
