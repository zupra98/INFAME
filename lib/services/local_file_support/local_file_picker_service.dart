part of '../../main.dart';

extension _LocalFilePickerServiceExtension on _MainScreenState {
  Future<void> _loadSelectedLocalFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs
              .getStringList(_localFoldersPrefsKey)
              ?.map((path) => path.trim())
              .where((path) => path.isNotEmpty)
              .toSet()
              .toList() ??
          <String>[];
      saved.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) {
        _selectedLocalFolders = saved;
        return;
      }
      setState(() => _selectedLocalFolders = saved);
    } catch (_) {
      return;
    }
  }

  Future<void> _saveSelectedLocalFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final folders = _selectedLocalFolders
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    await prefs.setStringList(_localFoldersPrefsKey, folders);
  }

  Future<Map<String, dynamic>?> _pickLocalMusicFolderAndroid() async {
    try {
      final result = await _localMusicChannel.invokeMapMethod<String, dynamic>(
        'pickLocalMusicFolder',
      );
      return result;
    } catch (e) {
      _showError('Local folder picker failed: $e');
      return null;
    }
  }

  Future<void> _showLocalImportChooser() async {
    if (_isScanning || _loadingMetadata) {
      _showError('Wait for the current scan to finish first.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.72),
      builder: (sheetContext) {
        final colors = _safeColors(_currentDynamicColors);
        final accent = colors[1];
        final bgColor = _isDarkMode ? _darkBg : _lightBg;
        final textColor = _isDarkMode ? _textPri : _lightText;
        final subColor = _isDarkMode ? _textSub : _lightSubtext;

        Widget buildAction({
          required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap,
        }) {
          return GestureDetector(
            onTap: onTap,
            child: GlassyContainer(
              radius: 24,
              padding: const EdgeInsets.all(16),
              customBorder: accent.withOpacity(0.24),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withOpacity(0.12),
                    ),
                    child: Icon(icon, color: accent, size: 25),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            color: subColor,
                            fontSize: 13,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            margin: const EdgeInsets.only(top: 110),
            decoration: BoxDecoration(
              color: bgColor.withOpacity(0.98),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              border: Border(
                top: BorderSide(
                  color: (_isDarkMode ? Colors.white : Colors.black)
                      .withOpacity(0.08),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Spacer(),
                        Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: subColor.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Add local music',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pick individual files or scan a whole folder.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: subColor,
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    buildAction(
                      icon: Icons.audio_file_rounded,
                      title: 'Choose music files',
                      subtitle: 'Select FLAC, MP3, WAV, OGG, OPUS and more.',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _importLocalAudioFiles();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    buildAction(
                      icon: Icons.folder_open_rounded,
                      title: 'Choose folder',
                      subtitle:
                          'Scan album folders recursively for supported audio files.',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _pickLocalMusicFolder();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _scanLocalAudioFolderAndroid(
    String folderUri,
  ) async {
    try {
      final result = await _localMusicChannel.invokeMapMethod<String, dynamic>(
            'scanLocalMusicFolder',
            <String, dynamic>{'folderUri': folderUri},
          ) ??
          <String, dynamic>{};
      return result;
    } catch (e) {
      debugPrint('LocalScan error=android_scan folder=$folderUri error=$e');
      return <String, dynamic>{
        'folderUri': folderUri,
        'pickerType': 'saf',
        'usingSaf': true,
        'childCount': 0,
        'entityCount': 0,
        'supportedCount': 0,
        'firstChild': '',
        'firstSupported': '',
        'files': <Map<String, dynamic>>[],
        'error': e.toString(),
      };
    }
  }

  List<_LocalAudioEntry> _localAudioEntriesFromScanResult(
    List<dynamic> rawFiles, {
    required String importRootKey,
    required String importRootTitle,
  }) {
    return rawFiles.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final uri = (map['uri'] ?? map['path'] ?? '').toString().trim();
      final name = (map['name'] ?? '').toString().trim();
      final relPath = (map['relativePath'] ?? '').toString().trim();
      final mimeType = (map['mimeType'] ?? '').toString().trim();
      final size = int.tryParse((map['size'] ?? '').toString());
      final modifiedTimeMs = int.tryParse(
        (map['modifiedTimeMs'] ?? '').toString(),
      );
      final isContentUri = DriveUtils.isContentUriString(uri);
      final groupRelative =
          relPath.trim().isNotEmpty ? _localDirname(relPath) : '';
      final importGroupKey = groupRelative.isNotEmpty
          ? '$importRootKey::$groupRelative'
          : importRootKey;
      final importGroupTitle = groupRelative.isNotEmpty
          ? _localBasename(groupRelative)
          : importRootTitle;
      return _LocalAudioEntry(
        sourceRef: uri,
        displayName: name.isNotEmpty ? name : _localBasename(uri),
        importBatchId: importRootKey,
        relativePath: relPath,
        importGroupKey: importGroupKey,
        importGroupTitle: importGroupTitle,
        parentFolderRef: importRootKey,
        size: size,
        modifiedTimeMs: modifiedTimeMs,
        mimeType: mimeType,
        isContentUri: isContentUri,
      );
    }).toList();
  }

  Future<List<_LocalAudioEntry>> _scanLocalAudioEntriesForFolder(
    String folder,
  ) async {
    if (_isAndroidSafFolderRef(folder)) {
      debugPrint('LocalScan start uri=$folder');
      final result = await _scanLocalAudioFolderAndroid(folder);
      final childCount =
          int.tryParse(result['childCount']?.toString() ?? '') ?? 0;
      final entityCount =
          int.tryParse(result['entityCount']?.toString() ?? '') ?? 0;
      final supportedCount =
          int.tryParse(result['supportedCount']?.toString() ?? '') ?? 0;
      final firstChild = (result['firstChild'] ?? '').toString();
      final firstSupported = (result['firstSupported'] ?? '').toString();
      final permissionStatus = (result['permissionStatus'] ?? '').toString();
      final selectedPath = (result['selectedPath'] ?? '').toString();
      final selectedUri = (result['selectedUri'] ?? '').toString();
      final selectedName = (result['selectedName'] ?? '').toString();
      final pickerType = (result['pickerType'] ?? 'saf').toString();
      final usingSaf = result['usingSaf'] == true;
      final files = (result['files'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .toList();
      final rootKey = selectedUri.isNotEmpty ? selectedUri : selectedPath;
      final rootTitle = selectedName.trim().isNotEmpty
          ? selectedName.trim()
          : _localBasename(rootKey);

      debugPrint('LocalScan pickerType=$pickerType');
      debugPrint('LocalScan androidSdk=${result['androidSdk'] ?? ''}');
      debugPrint('LocalScan permissionStatus=$permissionStatus');
      debugPrint('LocalScan selectedPath=$selectedPath');
      debugPrint('LocalScan selectedUri=$selectedUri');
      debugPrint('LocalScan selectedName=$selectedName');
      debugPrint('LocalScan usingSaf=$usingSaf');
      debugPrint('LocalScan childCount=$childCount entityCount=$entityCount');
      debugPrint('LocalScan supportedCount=$supportedCount');
      debugPrint('LocalScan firstChild=$firstChild');
      debugPrint('LocalScan firstSupported=$firstSupported');
      final sampleSupported = files
          .take(5)
          .map((item) => (item['name'] ?? '').toString().trim())
          .where((name) => name.isNotEmpty)
          .toList();
      debugPrint('LocalScan sampleSupported=${sampleSupported.join(' | ')}');
      debugPrint('LocalScan sampleUnsupported=');
      return _localAudioEntriesFromScanResult(
        files,
        importRootKey: rootKey.isNotEmpty ? rootKey : selectedUri,
        importRootTitle: rootTitle.isNotEmpty ? rootTitle : 'Local Files',
      );
    }

    final dir = Directory(folder);
    final exists = await dir.exists();
    debugPrint('LocalScan pickerType=filesystem');
    debugPrint(
      'LocalScan androidSdk=${Platform.isAndroid ? Platform.operatingSystemVersion : 'desktop'}',
    );
    debugPrint('LocalScan permissionStatus=filesystem');
    debugPrint('LocalScan selectedPath=$folder');
    debugPrint('LocalScan selectedUri=');
    debugPrint('LocalScan usingSaf=false');
    debugPrint('LocalScan exists=$exists');

    if (!exists) {
      throw FileSystemException('Folder does not exist', folder);
    }

    final entries = <_LocalAudioEntry>[];
    var childCount = 0;
    var entityCount = 0;
    var supportedCount = 0;
    var skippedUnsupported = 0;
    final sampleSupported = <String>[];
    final sampleUnsupported = <String>[];
    String firstChild = '';

    try {
      final rootPath =
          dir.path.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '');
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        entityCount++;
        final path = entity.path.trim();
        if (path.isEmpty) continue;
        final normalizedPath = path.replaceAll('\\', '/');
        final relativePath = normalizedPath.startsWith('$rootPath/')
            ? normalizedPath.substring(rootPath.length + 1)
            : '';
        if (relativePath.isEmpty || !relativePath.contains('/')) {
          childCount++;
        }
        if (entity is! File) continue;
        if (firstChild.isEmpty) firstChild = _localBasename(path);

        if (_isIgnoredLocalPath(path)) {
          skippedUnsupported++;
          if (sampleUnsupported.length < 5)
            sampleUnsupported.add(_localBasename(path));
          continue;
        }

        if (!_isSupportedLocalAudioPath(path)) {
          skippedUnsupported++;
          if (sampleUnsupported.length < 5)
            sampleUnsupported.add(_localBasename(path));
          continue;
        }

        supportedCount++;
        if (sampleSupported.length < 5)
          sampleSupported.add(_localBasename(path));
        entries.add(
          _LocalAudioEntry(
            sourceRef: path.replaceAll('\\', '/'),
            displayName: _localBasename(path),
            importBatchId: folder,
            relativePath: path.replaceAll('\\', '/'),
            importGroupKey: _localGroupKeyFromPath(path),
            importGroupTitle: _localGroupTitleFromPath(path),
            parentFolderRef: _localGroupKeyFromPath(path),
          ),
        );
      }
    } catch (e) {
      debugPrint('LocalScan error=scan folder=$folder error=$e');
    }

    _logLocalScanSummary(
      folder: folder,
      exists: exists,
      entityCount: entityCount,
      supportedCount: supportedCount,
      skippedUnsupported: skippedUnsupported,
      sampleSupported: sampleSupported,
      sampleUnsupported: sampleUnsupported,
    );

    debugPrint('LocalScan childCount=$childCount entityCount=$entityCount');
    debugPrint('LocalScan firstChild=$firstChild');
    debugPrint(
      'LocalScan firstSupported=${sampleSupported.isNotEmpty ? sampleSupported.first : ''}',
    );

    return entries;
  }

  Future<void> _pickLocalMusicFolder() async {
    if (_isScanning || _loadingMetadata) {
      _showError('Wait for the current scan to finish first.');
      return;
    }

    debugPrint('LocalImport source=folder');

    if (Platform.isAndroid) {
      final pickerResult = await _pickLocalMusicFolderAndroid();
      if (pickerResult == null) return;

      final selectedUri = (pickerResult['selectedUri'] ?? '').toString().trim();
      final selectedPath =
          (pickerResult['selectedPath'] ?? '').toString().trim();
      final usingSaf = pickerResult['usingSaf'] == true;
      final permissionStatus =
          (pickerResult['permissionStatus'] ?? 'unknown').toString();
      final permissionPersisted = permissionStatus == 'granted';
      final pickerType = (pickerResult['pickerType'] ?? 'saf').toString();
      final androidSdk =
          int.tryParse((pickerResult['androidSdk'] ?? '').toString()) ?? 0;

      debugPrint('LocalImport pickerResult path=$selectedPath');
      debugPrint('LocalImport pickerResult uri=$selectedUri');
      debugPrint('LocalImport usingSaf=$usingSaf');
      debugPrint('LocalImport permissionPersisted=$permissionPersisted');
      debugPrint('LocalScan pickerType=$pickerType');
      debugPrint('LocalScan androidSdk=$androidSdk');
      debugPrint('LocalScan permissionStatus=$permissionStatus');
      debugPrint('LocalScan selectedPath=$selectedPath');
      debugPrint('LocalScan selectedUri=$selectedUri');
      debugPrint('LocalScan usingSaf=$usingSaf');

      final folderRef = selectedUri.isNotEmpty ? selectedUri : selectedPath;
      if (folderRef.isEmpty) return;

      if (!_selectedLocalFolders.contains(folderRef)) {
        setState(
          () => _selectedLocalFolders = [..._selectedLocalFolders, folderRef]
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
        );
        await _saveSelectedLocalFolders();
      }

      await _rescanLocalMusicFolders(pathsOverride: <String>[folderRef]);
      return;
    }

    String? folderPath;
    try {
      folderPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose a local music folder',
      );
    } catch (e) {
      _showError('Local folder picker failed: $e');
      return;
    }

    final folder = folderPath?.trim() ?? '';
    if (folder.isEmpty) return;

    final normalized = folder.replaceAll('\\', '/');
    if (_isUnsupportedLocalFolderUriPath(normalized)) {
      debugPrint('LocalScan unsupported folder URI/path path=$normalized');
      _showError(
        'Could not read this folder. Try choosing another folder or granting file access.',
      );
      return;
    }

    if (!_selectedLocalFolders.contains(normalized)) {
      setState(
        () => _selectedLocalFolders = [..._selectedLocalFolders, normalized]
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
      );
      await _saveSelectedLocalFolders();
    }

    await _rescanLocalMusicFolders(pathsOverride: <String>[normalized]);
  }
}
