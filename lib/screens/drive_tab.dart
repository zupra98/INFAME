part of '../main.dart';

extension BuildDriveTabExtension on _MainScreenState {
Widget buildDriveTab() {
    final folders = _exploreItems.where((f) => DriveUtils.isFolder(f)).toList();
    final tracks = _exploreItems.where((f) => DriveUtils.isAudio(f)).toList();
    final colors = _safeColors(_currentDynamicColors);
    final bgColor = _isDarkMode ? _darkBg : _lightBg;
    final glowColor = _isDarkMode ? _neonPurple : _neonMagenta;
    final textColor = _isDarkMode ? _darkTextPri : _lightTextPri;
    final subTextColor = _isDarkMode ? _darkTextSub : _lightTextSub;

    return Container(
      color: bgColor,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 12),
            child: Row(
              children: [
                if (_exploreFolder != null || _navStack.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor),
                    onPressed: _exploreGoBack,
                  ),
                Expanded(
                  child: Text(
                    _exploreFolder?.name ?? 'My Drive',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                    ),
                  ),
                ),
                if (_exploreFolder != null)
                  GestureDetector(
                    onTap: _isScanning ? null : () => _scanFolderToLibrary(_exploreFolder!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isScanning ? [_glassWhite, _glassWhite] : [glowColor, glowColor.withOpacity(0.7)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: glowColor.withOpacity(0.22),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: Text(
                        _isScanning ? 'Scanning...' : 'Scan',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loadingExplore
                ? Center(child: CircularProgressIndicator(color: glowColor))
                : CustomScrollView(
                    key: const PageStorageKey('search_tab_scroll'),
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      if (folders.isEmpty && tracks.isEmpty)
                        SliverFillRemaining(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 36),
                              child: Text(
                                _exploreFolder == null
                                    ? 'Open Search to load your Drive folders.'
                                    : 'Nothing playable in this folder.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(color: subTextColor, height: 1.5),
                              ),
                            ),
                          ),
                        )
                      else ...[
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate((ctx, i) {
                              final f = folders[i];
                              return GestureDetector(
                                key: ValueKey(DriveUtils.effectiveId(f)),
                                onTap: () => _openExploreFolder(f),
                                behavior: HitTestBehavior.opaque,
                                child: GlassyContainer(
                                  margin: const EdgeInsets.only(bottom: 9),
                                  padding: const EdgeInsets.all(15),
                                  radius: 18,
                                  child: Row(
                                    children: [
                                      Icon(Icons.folder_rounded, color: glowColor, size: 26),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(
                                          f.name ?? 'Folder',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textColor),
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded, color: subTextColor),
                                    ],
                                  ),
                                ),
                              );
                            }, childCount: folders.length),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 218),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate((ctx, i) {
                              return _TrackGlassTile(
                                key: ValueKey(DriveUtils.effectiveId(tracks[i])),
                                track: tracks[i],
                                queue: tracks,
                                index: i,
                                onTap: () => _playSong(
                                  tracks[i],
                                  queue: tracks,
                                  idx: i,
                                  coverUrl: null,
                                  colors: colors,
                                ),
                                isDarkMode: _isDarkMode,
                              );
                            }, childCount: tracks.length),
                          ),
                        ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 170),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

}
