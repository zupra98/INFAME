part of '../main.dart';

extension BuildLibraryTabExtension on _MainScreenState {
  String _libraryAlbumTitle(Map<String, String> album) {
    return _resolvedAlbumTitle(album);
  }

  String _libraryAlbumArtist(Map<String, String> album) {
    return _resolvedAlbumArtist(album);
  }

  String _libraryAlbumSearchCacheKey(Map<String, String> album) {
    final id = album['id'] ?? '';
    if (id.isNotEmpty) return id;

    final title = album['name'] ?? album['displayName'] ?? '';
    final artist = album['artist'] ?? '';

    return '$title|$artist';
  }

  String _cachedLibraryAlbumSearchText(Map<String, String> album) {
    final key = _libraryAlbumSearchCacheKey(album);

    final cached = _librarySearchTextCache[key];
    if (cached != null) return cached;

    final text = _libraryAlbumSearchText(album);
    _librarySearchTextCache[key] = text;
    return text;
  }

  String _libraryAlbumSearchText(Map<String, String> album) {
    final brain = _libraryBrain[album['id'] ?? ''] ?? const <String, String>{};
    final tracks = _albumTracksCache[album['id'] ?? ''] ?? const <drive.File>[];
    final trackText = <String>[];

    for (final track in tracks) {
      final cached = _metaStore.peekFresh(track) ?? _metaStore.peek(track);
      trackText.add(track.name ?? '');
      if (cached != null) {
        trackText.addAll([
          cached.title,
          cached.artist,
          cached.album ?? '',
          cached.year ?? '',
          cached.genre ?? '',
        ]);
      }
    }

    return [
      album['name'] ?? '',
      album['displayName'] ?? '',
      album['artist'] ?? '',
      album['genre'] ?? '',
      album['year'] ?? '',
      brain['displayName'] ?? '',
      brain['artist'] ?? '',
      brain['genre'] ?? '',
      brain['year'] ?? '',
      _artistAlbumFromFolder(album['name'] ?? '')['artist'] ?? '',
      _artistAlbumFromFolder(album['name'] ?? '')['album'] ?? '',
      ...trackText,
    ].join(' ').toLowerCase();
  }

  bool _libraryAlbumMatches(Map<String, String> album, String query) {
    if (query.isEmpty) return true;
    final words = query.split(RegExp(r'\s+')).where((w) => w.trim().isNotEmpty);
    final haystack = _cachedLibraryAlbumSearchText(album);
    return words.every((word) => haystack.contains(word));
  }

  String _librarySongSearchText(Map<String, String> record) {
    return [
      record['title'] ?? '',
      record['artist'] ?? '',
      record['albumName'] ?? '',
      record['name'] ?? '',
      record['year'] ?? '',
      record['genre'] ?? '',
    ].join(' ').toLowerCase();
  }

  Widget _buildLibrarySearchBar(List<Color> colors,
          {required String hintText,
          TextEditingController? controller,
          ValueChanged<String>? onChanged,
          String? query}) =>
      _buildLibrarySearchBarFromPart(
        colors,
        hintText: hintText,
        controller: controller,
        onChanged: onChanged,
        query: query,
      );

  int _visibleArtistCount() {
    return _canonicalArtistNamesFromLibrary().length;
  }

  List<Map<String, String>> _cachedVisibleAlbumsForQuery(String query) {
    final cacheKey = [
      query,
      _librarySortMode,
      _libraryGridMode,
      _libraryViewMode,
      _albums.length,
      _libraryTrackIndex.length,
      _homeBrowseCacheVersion,
      _libraryBrowseCacheVersion,
    ].join('|');
    if (_cachedLibraryAlbumsKey == cacheKey) return _cachedVisibleLibraryAlbums;

    final visibleAlbums =
        _albums.where((album) => _libraryAlbumMatches(album, query)).toList();

    visibleAlbums.sort((a, b) {
      final an = _libraryAlbumTitle(a).toLowerCase();
      final bn = _libraryAlbumTitle(b).toLowerCase();
      if (_librarySortMode == 'artist') {
        final aa = _libraryAlbumArtist(a).toLowerCase();
        final ba = _libraryAlbumArtist(b).toLowerCase();
        final byArtist = aa.compareTo(ba);
        if (byArtist != 0) return byArtist;
      }
      if (_librarySortMode == 'za') return bn.compareTo(an);
      return an.compareTo(bn);
    });

    _cachedLibraryAlbumsKey = cacheKey;
    _cachedVisibleLibraryAlbums = visibleAlbums;
    return visibleAlbums;
  }

  ({List<Map<String, String>> records, List<drive.File> files})
      _cachedVisibleSongsForQuery(String query, {bool likedOnly = false}) {
    final cacheKey = [
      query,
      _libraryViewMode,
      _libraryTrackIndex.length,
      _albums.length,
      _likedTracksVersion,
      likedOnly,
      _libraryBrowseCacheVersion,
    ].join('|');
    if (_cachedLibrarySongsKey == cacheKey) {
      return (
        records: _cachedVisibleLibrarySongs,
        files: _cachedVisibleLibrarySongFiles,
      );
    }

    final visibleSongs = <Map<String, String>>[];
    for (final record in _libraryTrackIndex.values) {
      final recordKey = record['id'] ?? '';
      if (likedOnly && !(_likedTrackKeys.contains(recordKey))) continue;

      final searchText = _librarySongSearchText(record);
      if (query.isEmpty || searchText.contains(query)) {
        visibleSongs.add(record);
      }
    }

    visibleSongs.sort((a, b) {
      final at = a['title'] ?? a['name'] ?? '';
      final bt = b['title'] ?? b['name'] ?? '';
      return at.toLowerCase().compareTo(bt.toLowerCase());
    });

    final visibleSongFiles =
        visibleSongs.map((r) => _fileFromTrackIndexRecord(r)).toList();

    _cachedLibrarySongsKey = cacheKey;
    _cachedVisibleLibrarySongs = visibleSongs;
    _cachedVisibleLibrarySongFiles = visibleSongFiles;
    return (records: visibleSongs, files: visibleSongFiles);
  }

  Widget _buildSongsView(List<Color> colors, String query, Color bgColor,
          {bool likedOnly = false,
          String title = 'Songs',
          String subtitle = 'Search songs across all albums.',
          String scrollKey = 'library_songs_scroll'}) =>
      _buildSongsViewFromPart(
        colors,
        query,
        bgColor,
        likedOnly: likedOnly,
        title: title,
        subtitle: subtitle,
        scrollKey: scrollKey,
      );

  ({Map<String, List<Map<String, String>>> grouped, List<String> names})
      _cachedVisibleArtistsForQuery(String query) {
    final cacheKey = [
      query,
      _libraryViewMode,
      _libraryTrackIndex.length,
      _libraryBrowseCacheVersion,
    ].join('|');
    if (_cachedLibraryArtistsKey == cacheKey) {
      return (
        grouped: _cachedLibraryArtists,
        names: _cachedVisibleLibraryArtists
      );
    }

    final artists = <String, List<Map<String, String>>>{};
    for (final record in _libraryTrackIndex.values) {
      final albumId = record['albumId'] ?? '';
      final brain = albumId.isNotEmpty ? _libraryBrain[albumId] : null;
      final artist = _canonicalArtistName(
        albumArtist: record['albumArtist'] ?? brain?['artist'] ?? '',
        trackArtist: record['artist'] ?? '',
        albumName: record['albumName'] ?? brain?['displayName'] ?? '',
      );
      if (artist.isEmpty) continue;
      artists.putIfAbsent(artist, () => []);
      artists[artist]!.add(record);
    }

    final artistNames = artists.keys.toList();
    final visibleArtists = artistNames
        .where((artist) =>
            query.isEmpty ||
            artist.toLowerCase().contains(query) ||
            (artists[artist] ?? const <Map<String, String>>[]).any(
                (record) => _artistSearchTextForRecord(record).contains(query)))
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    _cachedLibraryArtistsKey = cacheKey;
    _cachedLibraryArtists = artists;
    _cachedVisibleLibraryArtists = visibleArtists;
    return (grouped: artists, names: visibleArtists);
  }

  Widget _buildArtistsView(List<Color> colors, String query, Color bgColor) =>
      _buildArtistsViewFromPart(colors, query, bgColor);

  Widget buildLibraryTab() => buildLibraryTabFromPart();

  Widget _buildLibraryModeRow() => _buildLibraryModeRowFromPart();
}
