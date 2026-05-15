# main.dart Split Audit Report

**File**: `lib/main.dart`
**Total Lines**: ~9,715 lines
**Status**: ⚠️ CRITICAL - File is too large for maintainability

---

## 📊 Candidate Sections for Extraction

| Section Name | Line Range | Est. Lines | Target File | Uses Private State | Part File Safe | Risk | Dependencies |
|-------------|------------|------------|-------------|-------------------|----------------|------|--------------|
| **Settings UI** | 3876-4450 | ~575 | `widgets/settings_widgets.dart` | ✅ Yes | ✅ Yes | 🟢 LOW | None - pure UI |
| **Album Detail View** | 8626-9025 | ~400 | `widgets/album_detail_widgets.dart` | ✅ Yes | ✅ Yes | 🟢 LOW | None - pure UI |
| **Search Tab UI** | 9098-9611 | ~513 | `widgets/search_widgets.dart` | ✅ Yes | ✅ Yes | 🟢 LOW | None - pure UI |
| **Metadata Resolution** | 2131-2600 | ~470 | `utils/metadata_resolvers.dart` | ✅ Yes | ✅ Yes | 🟡 MEDIUM | Core logic |
| **Album/Artist Helpers** | 2972-3430 | ~458 | `utils/album_helpers.dart` | ✅ Yes | ✅ Yes | 🟡 MEDIUM | Core logic |
| **Neon Blob System** | 135-453 | ~318 | `utils/neon_blob_theme.dart` | ❌ No | ✅ Yes | 🟢 LOW | Theme only |
| **Color/Gradient Utils** | 540-770 | ~230 | `utils/color_helpers.dart` | ❌ No | ✅ Yes | 🟢 LOW | Pure functions |
| **Cover Image Utils** | 771-869 | ~98 | `utils/cover_helpers.dart` | ⚠️ Partial | ⚠️ Maybe | 🟡 MEDIUM | State access |
| **Background Widgets** | 9614-9700 | ~86 | `widgets/background_widgets.dart` | ✅ Yes | ✅ Yes | 🟢 LOW | Pure UI |

**Total Extractable**: ~3,148 lines (32% of file)
**Safe First Wave**: ~2,080 lines (Settings + Album Detail + Search + Neon Blob + Color Utils + Background)

---

## 🎯 Extraction Priority (Safest First)

### **Wave 1: Pure UI Widgets** (Low Risk, ~1,174 lines)
These widgets only read state, don't modify it, and are pure UI.

1. **Settings UI** (575 lines) - `widgets/settings_widgets.dart`
   - Lines: 3876-4450
   - Risk: 🟢 LOW
   - Reason: Pure UI, reads state but doesn't modify
   - Contains: `_openSettingsSheet()` and all Settings UI widgets

2. **Album Detail View** (400 lines) - `widgets/album_detail_widgets.dart`
   - Lines: 8626-9025
   - Risk: 🟢 LOW
   - Reason: Pure UI, displays album tracks
   - Contains: `_buildAlbumView()` widget

3. **Background Widgets** (86 lines) - `widgets/background_widgets.dart`
   - Lines: 9614-9700
   - Risk: 🟢 LOW
   - Reason: Pure UI, simple blob rendering
   - Contains: `_buildAppBackground()`, `_buildBlob()`, `_buildGradientText()`

4. **Search Tab UI** (513 lines) - `widgets/search_widgets.dart`
   - Lines: 9098-9611
   - Risk: 🟢 LOW
   - Reason: Pure UI, complex but isolated
   - Contains: `_buildSearchTab()` widget

---

### **Wave 2: Pure Utility Functions** (Low Risk, ~548 lines)
These are stateless helper functions with no dependencies.

5. **Neon Blob Theme** (318 lines) - `utils/neon_blob_theme.dart`
   - Lines: 135-453
   - Risk: 🟢 LOW
   - Reason: Pure theme/color calculations
   - Contains: `NeonBlobColorScheme`, `_NeonBlobBackground`, `_BlurredBlob`

6. **Color/Gradient Utils** (230 lines) - `utils/color_helpers.dart`
   - Lines: 540-770
   - Risk: 🟢 LOW
   - Reason: Pure functions, no state
   - Contains: `getAlbumGradient()`, `_parseColorFromString()`, `_ArtworkCandidate`

---

### **Wave 3: Business Logic** (Medium Risk, ~928 lines)
These contain core business logic but can be extracted with `part of`.

7. **Metadata Resolution** (470 lines) - `utils/metadata_resolvers.dart`
   - Lines: 2131-2600
   - Risk: 🟡 MEDIUM
   - Reason: Core metadata logic, heavily uses state
   - Contains: `_resolvedAlbumTitle()`, `_resolvedAlbumArtist()`, `_resolvedAlbumMap()`

8. **Album/Artist Helpers** (458 lines) - `utils/album_helpers.dart`
   - Lines: 2972-3430
   - Risk: 🟡 MEDIUM
   - Reason: Core album logic, uses state
   - Contains: `_artistAlbumFromFolder()`, `_brainAlbums()`, `_recentBrainAlbums()`

---

### **Wave 4: Risky/Keep in Main** (High Risk)
These should NOT be moved yet.

9. **Cover Image Utils** (98 lines) - Keep for now
   - Lines: 771-869
   - Risk: 🟡 MEDIUM
   - Reason: Uses mutable state `_failedCoverSources`
   - Action: Extract in Wave 3 after refactoring state

10. **State Fields** (169 lines) - Keep in main
    - Lines: 931-1100
    - Risk: 🔴 HIGH
    - Reason: Core state, cannot move
    - Action: Never move

11. **Lifecycle Methods** (105 lines) - Keep in main
    - Lines: 1115-1220
    - Risk: 🔴 HIGH
    - Reason: initState, dispose, etc.
    - Action: Never move

---

## 🚀 Recommended First Extraction

### **Start with Settings UI** (575 lines, safest)

**Why Settings first?**
- ✅ Largest single extractable section
- ✅ Pure UI, no business logic
- ✅ Self-contained, minimal dependencies
- ✅ Easy to test after extraction
- ✅ If it breaks, easy to revert

**Extraction Steps**:

1. Create `lib/widgets/settings_widgets.dart`
2. Add header: `part of '../main.dart';`
3. Copy lines 3876-4450 (entire `_openSettingsSheet()` method)
4. Add to main.dart: `part 'widgets/settings_widgets.dart';`
5. Delete original lines from main.dart
6. Test: Open settings, verify all buttons work

**Expected Result**:
- main.dart: 9,715 → 9,140 lines (575 lines removed)
- New file: settings_widgets.dart (575 lines)
- Zero code changes, just file movement

---

## 📋 Complete Extraction Order

```
Wave 1 (Pure UI - 1,174 lines):
1. Settings UI          → widgets/settings_widgets.dart       (575 lines)
2. Album Detail View    → widgets/album_detail_widgets.dart   (400 lines)
3. Background Widgets   → widgets/background_widgets.dart     (86 lines)
4. Search Tab UI        → widgets/search_widgets.dart         (513 lines)

Wave 2 (Pure Utils - 548 lines):
5. Neon Blob Theme      → utils/neon_blob_theme.dart          (318 lines)
6. Color/Gradient Utils → utils/color_helpers.dart            (230 lines)

Wave 3 (Business Logic - 928 lines):
7. Metadata Resolution  → utils/metadata_resolvers.dart       (470 lines)
8. Album/Artist Helpers → utils/album_helpers.dart            (458 lines)

Total Reduction: 2,650 lines (27% of file)
Final Size: ~7,065 lines (still large, but manageable)
```

---

## ⚠️ Sections That Should NOT Be Moved

### **Core State Management** (Keep in main.dart)
- State field declarations (lines 931-1100)
- initState/dispose methods (lines 1115-1220)
- State update methods (_invalidateCache, setState calls)
- Navigation controller logic
- Audio player lifecycle

### **Why Keep These?**
- They define the core state structure
- Moving them requires full state management refactor
- High risk of breaking everything
- Better to keep centralized for now

---

## 🔍 Detailed Section Analysis

### 1. Settings UI (Lines 3876-4450, 575 lines)

**Contains**:
```dart
void _openSettingsSheet() {
  // Full settings modal bottom sheet
  // - Account info
  // - Drive folder management
  // - Library actions
  // - Appearance settings
  // - Glass mode toggle
  // - Sign out
}
```

**State Access** (Read-only):
- `_user` - Google account
- `_albums` - Album count
- `_loadingMetadata` - Scan status
- `_isDarkMode` - Theme
- `_accentMode` - Accent color
- `_glassMode` - Glass effect mode

**State Mutations** (Via callbacks):
- Calls `_scanMetadata()`, `_signOut()`, etc.
- All mutations go through main state methods

**Risk**: 🟢 LOW
- Pure UI presentation
- No direct state mutations
- Easy to test
- Easy to revert

---

### 2. Album Detail View (Lines 8626-9025, 400 lines)

**Contains**:
```dart
Widget _buildAlbumView() {
  // Full album detail screen
  // - Album header with cover
  // - Track list
  // - Play/shuffle buttons
  // - Album actions menu
}
```

**State Access** (Read-only):
- `_viewingAlbum` - Current album
- `_albumTracks` - Track list
- `_loadingAlbum` - Loading state
- `_likedTrackKeys` - Liked tracks

**State Mutations** (Via callbacks):
- Calls `_playSong()`, `_toggleLike()`, etc.
- All mutations go through main state methods

**Risk**: 🟢 LOW
- Pure UI presentation
- Well-isolated
- Clear boundaries

---

### 3. Search Tab UI (Lines 9098-9611, 513 lines)

**Contains**:
```dart
Widget _buildSearchTab() {
  // Full search interface
  // - Search bar
  // - Category pills (All/Albums/Artists/Songs/Liked)
  // - Filtered results
  // - Empty states
}
```

**State Access** (Read-only):
- `_searchQuery` - Search text
- `_searchViewMode` - Category filter
- `_albums`, `_tracks`, `_likedTrackKeys`

**State Mutations** (Via callbacks):
- Calls `_openAlbum()`, `_playSong()`, etc.
- Updates `_searchQuery`, `_searchViewMode`

**Risk**: 🟢 LOW
- Self-contained UI
- Clear state boundaries
- Easy to test

---

### 4. Metadata Resolution (Lines 2131-2600, 470 lines)

**Contains**:
```dart
String _resolvedAlbumTitle(Map<String, String> album) { ... }
String _resolvedAlbumArtist(Map<String, String> album) { ... }
Map<String, String> _resolvedAlbumMap(Map<String, String> album) { ... }
// + 20+ helper methods
```

**State Access** (Heavy):
- `_libraryBrain` - Saved metadata
- `_albums` - Album list
- `_libraryTrackIndex` - Track index

**Risk**: 🟡 MEDIUM
- Core business logic
- Heavily uses state
- But pure functions (no mutations)
- Can extract with `part of`

---

### 5. Neon Blob Theme (Lines 135-453, 318 lines)

**Contains**:
```dart
class NeonBlobColorScheme { ... }
class _NeonBlobBackground extends StatelessWidget { ... }
class _BlurredBlob extends StatelessWidget { ... }
```

**State Access**: None (pure theme code)

**Risk**: 🟢 LOW
- Pure theme/color calculations
- No state dependencies
- Can be regular import (not part file)

---

## 🎯 First Extraction Prompt

**Ready-to-use prompt for Settings UI extraction**:

```
Extract Settings UI from main.dart to widgets/settings_widgets.dart

Steps:
1. Create lib/widgets/settings_widgets.dart
2. Add header: part of '../main.dart';
3. Copy lines 3876-4450 from main.dart (entire _openSettingsSheet method)
4. Paste into settings_widgets.dart
5. Add to main.dart line 40: part 'widgets/settings_widgets.dart';
6. Delete lines 3876-4450 from main.dart
7. Run dart format on both files
8. Test: Open settings, verify all buttons work

Expected result:
- main.dart: 9,715 → 9,140 lines
- New file: settings_widgets.dart (575 lines)
- Zero functional changes
```

---

## 📊 Impact Summary

### After Wave 1 (Pure UI):
- **Lines removed**: 1,174
- **New size**: 8,541 lines
- **Risk**: 🟢 LOW
- **Time**: 30-45 minutes

### After Wave 2 (Pure Utils):
- **Lines removed**: 1,722 total
- **New size**: 7,993 lines
- **Risk**: 🟢 LOW
- **Time**: +15 minutes

### After Wave 3 (Business Logic):
- **Lines removed**: 2,650 total
- **New size**: 7,065 lines
- **Risk**: 🟡 MEDIUM
- **Time**: +30 minutes

### Final State:
- **Original**: 9,715 lines (unmaintainable)
- **After extraction**: ~7,065 lines (manageable)
- **Reduction**: 27% smaller
- **Files created**: 8 new part files

---

## ✅ Success Criteria

After each extraction:
1. ✅ App builds without errors
2. ✅ All features work as before
3. ✅ No new warnings
4. ✅ `dart format` passes
5. ✅ File size reduced as expected

---

## 🚫 What NOT to Do

❌ **Don't refactor while extracting** - Just move code as-is
❌ **Don't change function signatures** - Keep everything identical
❌ **Don't extract state fields** - Leave them in main.dart
❌ **Don't extract lifecycle methods** - Keep initState/dispose in main
❌ **Don't rush** - Test after each extraction

---

## 💡 Recommendation

**Start with Settings UI extraction today** (575 lines, 30 min, low risk)

This gives you:
- ✅ Immediate 6% size reduction
- ✅ Proof of concept for part file approach
- ✅ Low risk, easy to revert
- ✅ Builds confidence for larger extractions

**Then continue with Wave 1 tomorrow** when credit resets.
