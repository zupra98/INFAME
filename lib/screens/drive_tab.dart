part of '../main.dart';

extension BuildDriveTabExtension on _MainScreenState {
  Widget buildDriveTab() {
    _verboseUiLog(
        'DriveSettings render folder count = ${_exploreItems.length}');
    final folders = _exploreItems.where((f) => DriveUtils.isFolder(f)).toList();
    final tracks = _exploreItems.where((f) => DriveUtils.isAudio(f)).toList();
    _verboseUiLog(
        'DriveSettings using loaded folder list count = ${folders.length}');
    final colors = _safeColors(_currentDynamicColors);
    final bgColor = _isDarkMode ? _darkBg : _lightBg;
    final glowColor = _isDarkMode ? _neonPurple : _neonMagenta;
    final textColor = _isDarkMode ? _darkTextPri : _lightTextPri;
    final subTextColor = _isDarkMode ? _darkTextSub : _lightTextSub;
    final hasLoadedRootFolders =
        _exploreFolder == null && _exploreItems.isNotEmpty;

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
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: textColor),
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
                    onTap: _isScanning
                        ? null
                        : () => _scanFolderToLibrary(_exploreFolder!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isScanning
                              ? [_glassWhite, _glassWhite]
                              : [glowColor, glowColor.withOpacity(0.7)],
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
            child: _user == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_sync_rounded,
                              color: glowColor, size: 46),
                          const SizedBox(height: 14),
                          Text(
                            'Sign in to browse your Drive folders.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your selected folders and scan state stay saved once you connect.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: subTextColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 18),
                          ElevatedButton(
                            onPressed: _signingIn ? null : _signIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: glowColor,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            child: Text(
                              _signingIn ? 'Signing in...' : 'Sign in',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _loadingExplore
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: glowColor),
                            const SizedBox(height: 14),
                            Text(
                              'Loading your Drive folders...',
                              style: GoogleFonts.inter(
                                color: subTextColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      )
                    : CustomScrollView(
                        key: const PageStorageKey('drive_tab_scroll'),
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                          if (_driveExplorerLoadError != null &&
                              !hasLoadedRootFolders &&
                              _exploreFolder == null)
                            SliverFillRemaining(
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 36),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.error_outline_rounded,
                                          color: glowColor, size: 42),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Drive folders could not be loaded.',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          color: textColor,
                                          fontWeight: FontWeight.w900,
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _driveExplorerLoadError!,
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          color: subTextColor,
                                          fontSize: 12,
                                          height: 1.45,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      TextButton(
                                        onPressed: _ensureDriveExplorerLoaded,
                                        child: Text(
                                          'Try again',
                                          style: GoogleFonts.inter(
                                            color: glowColor,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else if (folders.isEmpty && tracks.isEmpty)
                            SliverFillRemaining(
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 36),
                                  child: Text(
                                    _exploreFolder == null
                                        ? 'No Drive folders found yet.'
                                        : 'Nothing playable in this folder.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                        color: subTextColor, height: 1.5),
                                  ),
                                ),
                              ),
                            )
                          else ...[
                            SliverPadding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate((ctx, i) {
                                  final f = folders[i];
                                  return GestureDetector(
                                    key: ValueKey(DriveUtils.effectiveId(f)),
                                    onTap: () {
                                      debugPrint(
                                          'DriveSettings folder tapped: ${f.name} / ${DriveUtils.effectiveId(f)}');
                                      _openExploreFolder(f);
                                    },
                                    behavior: HitTestBehavior.opaque,
                                    child: GlassyContainer(
                                      margin: const EdgeInsets.only(bottom: 9),
                                      padding: const EdgeInsets.all(15),
                                      radius: 18,
                                      child: Row(
                                        children: [
                                          Icon(Icons.folder_rounded,
                                              color: glowColor, size: 26),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Text(
                                              f.name ?? 'Folder',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w600,
                                                  color: textColor),
                                            ),
                                          ),
                                          Icon(Icons.chevron_right_rounded,
                                              color: subTextColor),
                                        ],
                                      ),
                                    ),
                                  );
                                }, childCount: folders.length),
                              ),
                            ),
                            SliverPadding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 218),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate((ctx, i) {
                                  return _TrackGlassTile(
                                    key: ValueKey(
                                        DriveUtils.effectiveId(tracks[i])),
                                    track: tracks[i],
                                    queue: tracks,
                                    index: i,
                                    isLiked: _isTrackLiked(tracks[i]),
                                    onTap: () => _playSong(
                                      tracks[i],
                                      queue: tracks,
                                      idx: i,
                                      coverUrl: null,
                                      colors: colors,
                                    ),
                                    onToggleLiked: () =>
                                        _toggleLikedTrack(tracks[i]),
                                    onPlayNext: () =>
                                        _addTracksPlayNext([tracks[i]]),
                                    onAddToQueue: () =>
                                        _addTracksToQueueEnd([tracks[i]]),
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
