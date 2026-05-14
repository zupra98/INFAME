part of '../main.dart';

extension _SettingsWidgetsExtension on _MainScreenState {
  void _openSettingsSheetFromPart() {
    final colors = _safeColors(_currentDynamicColors);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.70),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            _settingsSheetSetState = setSheetState;
            final accent = _appAccent;
            final accountName = (_user?.displayName ?? '').trim();
            final accountEmail = (_user?.email ?? '').trim();
            final driveAccountLabel = accountName.isNotEmpty
                ? accountName
                : (accountEmail.isNotEmpty ? accountEmail : 'Not connected');
            final driveFolderLabel =
                _exploreFolder?.name?.trim().isNotEmpty == true
                    ? _exploreFolder!.name!.trim()
                    : (_albums.isNotEmpty
                        ? (_albums.first['name'] ?? 'Not selected')
                        : 'Not selected');
            final driveStatusLabel = _loadingExplore
                ? 'Loading folders...'
                : (_driveExplorerLoadError?.trim().isNotEmpty == true
                    ? 'Error loading folders'
                    : '${_exploreItems.length} items loaded');

            final progress = _metadataTotal > 0
                ? (_metadataDone / _metadataTotal).clamp(0.0, 1.0)
                : null;

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
              child: Container(
                height: MediaQuery.of(sheetContext).size.height * 0.88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.zero,
                  border: Border(
                      top: BorderSide(
                          color: _isDarkMode
                              ? Colors.white.withOpacity(0.12)
                              : Colors.black.withOpacity(0.08))),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _isDarkMode
                        ? [
                            colors[0].withOpacity(0.22),
                            _bg.withOpacity(0.98),
                            Colors.black,
                          ]
                        : [
                            _lightGlassBase.withOpacity(0.92),
                            _lightBg.withOpacity(0.98),
                            _lightBg,
                          ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 34),
                            ),
                            const Spacer(),
                            Text(
                              'Settings',
                              style: GoogleFonts.inter(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: _isDarkMode ? _textPri : _lightText,
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
                          children: [
                            Text(
                              'Settings',
                              style: GoogleFonts.inter(
                                color: _isDarkMode ? _textPri : _lightTextPri,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Appearance, music library, performance and Drive controls.',
                              style: GoogleFonts.inter(
                                color: _isDarkMode ? _textSub : _lightSubtext,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 22),
                            GlassyContainer(
                              radius: 24,
                              padding: const EdgeInsets.all(16),
                              customColor: _isDarkMode
                                  ? Colors.white.withOpacity(0.075)
                                  : _lightGlassBase.withOpacity(0.78),
                              customBorder: _isDarkMode
                                  ? accent.withOpacity(0.22)
                                  : Colors.black.withOpacity(0.08),
                              child: Row(
                                children: [
                                  Icon(
                                    _isDarkMode
                                        ? Icons.dark_mode_rounded
                                        : Icons.light_mode_rounded,
                                    color: accent,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _isDarkMode ? 'Dark Mode' : 'Light Mode',
                                      style: GoogleFonts.inter(
                                        color:
                                            _isDarkMode ? _textPri : _lightText,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: _isDarkMode,
                                    onChanged: (value) {
                                      _settingsSetState(
                                        () => _isDarkMode = value,
                                      );
                                      setSheetState(() {});
                                      _saveUiPreferences();
                                    },
                                    activeColor: accent,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            GlassyContainer(
                              radius: 24,
                              padding: const EdgeInsets.all(16),
                              customColor: _isDarkMode
                                  ? Colors.white.withOpacity(0.075)
                                  : _lightGlassBase.withOpacity(0.78),
                              customBorder: _isDarkMode
                                  ? accent.withOpacity(0.22)
                                  : Colors.black.withOpacity(0.08),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _loadingMetadata
                                            ? Icons.sync_rounded
                                            : Icons.library_music_rounded,
                                        color: accent,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _metadataStatusLabel(),
                                          style: GoogleFonts.inter(
                                            color: _isDarkMode
                                                ? _textPri
                                                : _lightText,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 6,
                                      backgroundColor: _isDarkMode
                                          ? Colors.white.withOpacity(0.14)
                                          : Colors.black.withOpacity(0.08),
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(accent),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      _MetadataStat(
                                          label: 'Fast', value: _metadataFast),
                                      _MetadataStat(
                                          label: 'Deep',
                                          value: _metadataDeep,
                                          isDarkMode: _isDarkMode),
                                      _MetadataStat(
                                          label: 'Failed',
                                          value: _metadataFailed,
                                          isDarkMode: _isDarkMode),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            _SettingsPrimaryButton(
                              label: _loadingMetadata
                                  ? 'Cancel metadata scan'
                                  : 'Scan metadata',
                              icon: _loadingMetadata
                                  ? Icons.stop_rounded
                                  : Icons.sync_rounded,
                              accent: accent,
                              destructive: _loadingMetadata,
                              isDarkMode: _isDarkMode,
                              onTap: () {
                                if (_loadingMetadata) {
                                  _cancelForegroundMetadataScan();
                                } else {
                                  _startForegroundLibraryMetadataScan();
                                }
                                setSheetState(() {});
                              },
                            ),
                            const SizedBox(height: 24),
                            _SettingsSectionTitle(
                                title: 'Account / Google Drive',
                                isDarkMode: _isDarkMode),
                            _SettingsInfoCard(
                              icon: Icons.account_circle_rounded,
                              title: driveAccountLabel,
                              subtitle:
                                  'Folder: $driveFolderLabel • $driveStatusLabel',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                            ),
                            const SizedBox(height: 10),
                            _SettingsActionRow(
                              icon: Icons.storage_rounded,
                              title: 'Change Drive folder',
                              subtitle:
                                  'Open Drive folders and choose your music source.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: () {
                                Navigator.pop(sheetContext);
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted) _openDriveSourcePage();
                                });
                              },
                            ),
                            _SettingsActionRow(
                              icon: Icons.refresh_rounded,
                              title: 'Rescan library',
                              subtitle: _exploreFolder == null
                                  ? 'Select a Drive folder, then scan it into your library.'
                                  : 'Scan "$driveFolderLabel" into your library.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: _exploreFolder == null || _isScanning
                                  ? null
                                  : () => _scanFolderToLibrary(_exploreFolder!),
                            ),
                            const SizedBox(height: 18),
                            _SettingsSectionTitle(
                                title: 'Library', isDarkMode: _isDarkMode),
                            _SettingsInfoCard(
                              icon: Icons.album_rounded,
                              title: '${_albums.length} albums saved',
                              subtitle:
                                  '${_metaStore.count} cached song metadata entries',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                            ),
                            _SettingsActionRow(
                              icon: Icons.restore_rounded,
                              title: 'Restore previous library',
                              subtitle:
                                  'Recover the backup saved before clearing the app library.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: _restoreLibraryBackup,
                            ),
                            _SettingsActionRow(
                              icon: Icons.tag_rounded,
                              title: 'Clear metadata cache',
                              subtitle:
                                  'Forces titles, artists and albums to be scanned again.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: _clearMetadataCacheSafely,
                            ),
                            _SettingsActionRow(
                              icon: Icons.image_not_supported_rounded,
                              title: 'Clear cached covers',
                              subtitle:
                                  'Removes local cover images saved by metadata scans.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: _clearCoverCacheSafely,
                            ),
                            _SettingsActionRow(
                              icon: Icons.image_search_rounded,
                              title: 'Find covers for all albums',
                              subtitle:
                                  'Searches embedded art and online sources for albums without covers.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: _findCoversForAllAlbums,
                            ),
                            const SizedBox(height: 18),
                            _SettingsSectionTitle(
                                title: 'Appearance', isDarkMode: _isDarkMode),
                            _SettingsActionRow(
                              icon: Icons.palette_rounded,
                              title:
                                  'Accent color: ${_accentModeLabelForMode(_accentMode)}',
                              subtitle:
                                  'Cycles White, Champagne, Soft Blue and Pink.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: () => _cycleAccentMode(setSheetState),
                            ),
                            _SettingsActionRow(
                              icon: Icons.auto_awesome_rounded,
                              title: 'Rebuild Smart Home index',
                              subtitle:
                                  'Refreshes Home sections from cached metadata and opened albums.',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: _rebuildSmartHomeIndex,
                            ),
                            _SettingsSwitchRow(
                              icon: Icons.history_rounded,
                              title: 'Continue listening',
                              subtitle:
                                  'Show recent albums and recent tracks on Home.',
                              value: _homeShowContinue,
                              accent: colors[1],
                              isDarkMode: _isDarkMode,
                              onChanged: (value) {
                                _settingsSetState(
                                  () => _homeShowContinue = value,
                                );
                                setSheetState(() {});
                                _saveUiPreferences();
                              },
                            ),
                            // Hidden until genre section exists
                            // _SettingsSwitchRow(
                            //   icon: Icons.category_rounded,
                            //   title: 'Genre shelves',
                            //   subtitle: 'Show Hip-Hop, Soul, Jazz and other shelves when tags exist.',
                            //   value: _homeShowGenres,
                            //   accent: colors[1],
                            //   onChanged: (value) {
                            //     setState(() => _homeShowGenres = value);
                            //     setSheetState(() {});
                            //     _saveUiPreferences();
                            //   },
                            // ),
                            // Hidden until decade section exists
                            // _SettingsSwitchRow(
                            //   icon: Icons.calendar_month_rounded,
                            //   title: 'Decade shelves',
                            //   subtitle: 'Show 90s, 2000s and other year-based rows when metadata exists.',
                            //   value: _homeShowDecades,
                            //   accent: colors[1],
                            //   onChanged: (value) {
                            //     setState(() => _homeShowDecades = value);
                            //     setSheetState(() {});
                            //     _saveUiPreferences();
                            //   },
                            // ),
                            _SettingsSwitchRow(
                              icon: Icons.person_rounded,
                              title: 'Your Library',
                              subtitle: 'Show your library albums on home.',
                              value: _homeShowArtists,
                              accent: colors[1],
                              isDarkMode: _isDarkMode,
                              onChanged: (value) {
                                _settingsSetState(
                                  () => _homeShowArtists = value,
                                );
                                setSheetState(() {});
                                _saveUiPreferences();
                              },
                            ),
                            _SettingsSwitchRow(
                              icon: Icons.casino_rounded,
                              title: 'Discovery card',
                              subtitle: 'Show the random-library pick card.',
                              value: _homeShowDiscovery,
                              accent: colors[1],
                              isDarkMode: _isDarkMode,
                              onChanged: (value) {
                                _settingsSetState(
                                  () => _homeShowDiscovery = value,
                                );
                                setSheetState(() {});
                                _saveUiPreferences();
                              },
                            ),
                            const SizedBox(height: 18),
                            _SettingsSectionTitle(
                                title: 'Performance', isDarkMode: _isDarkMode),
                            _SettingsActionRow(
                              icon: Icons.tune_rounded,
                              title: 'Performance mode',
                              subtitle:
                                  'Reduces expensive visuals and background work. Current: ${_glassModeLabel(_glassMode)}',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onTap: () => _cycleGlassMode(setSheetState),
                            ),
                            _SettingsSwitchRow(
                              icon: Icons.gradient_rounded,
                              title: 'Background glow',
                              subtitle:
                                  'Soft mesh glow without list blur. Turn off only if page swipes still feel heavy.',
                              value: _showBackgroundGlow,
                              accent: accent,
                              isDarkMode: _isDarkMode,
                              onChanged: (value) {
                                _settingsSetState(
                                  () => _showBackgroundGlow = value,
                                );
                                setSheetState(() {});
                                _saveUiPreferences();
                              },
                            ),
                            _SettingsInfoCard(
                              icon: Icons.speed_rounded,
                              title: 'Performance profile',
                              subtitle: _glassModeDescription(_glassMode),
                              accent: accent,
                              isDarkMode: _isDarkMode,
                            ),
                            const SizedBox(height: 18),
                            _SettingsSectionTitle(
                                title: 'About / Debug',
                                isDarkMode: _isDarkMode),
                            _SettingsInfoCard(
                              icon: Icons.info_outline_rounded,
                              title: 'Scan stats',
                              subtitle:
                                  'Fast: $_metadataFast • Deep: $_metadataDeep • Failed: $_metadataFailed',
                              accent: accent,
                              isDarkMode: _isDarkMode,
                            ),
                            _SettingsActionRow(
                              icon: Icons.delete_outline_rounded,
                              title: 'Clear app library cache',
                              subtitle:
                                  'Does not touch Google Drive files. Requires typing CLEAR.',
                              accent: Colors.redAccent,
                              destructive: true,
                              isDarkMode: _isDarkMode,
                              onTap: _clearLibraryCacheSafely,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _settingsSheetSetState = null;
    });
  }
}
