part of '../../main.dart';

class _LyricsResult {
  final String trackName;
  final String artistName;
  final String? plainLyrics;
  final String? syncedLyrics;

  const _LyricsResult({
    required this.trackName,
    required this.artistName,
    this.plainLyrics,
    this.syncedLyrics,
  });

  bool get hasSynced => syncedLyrics != null && syncedLyrics!.trim().isNotEmpty;
  bool get hasPlain => plainLyrics != null && plainLyrics!.trim().isNotEmpty;
}

class _LyricLine {
  final Duration time;
  final String text;

  const _LyricLine({required this.time, required this.text});
}

class _LyricsSheet extends StatefulWidget {
  final AudioPlayer player;
  final Map<String, String> meta;
  final List<Color> colors;

  const _LyricsSheet({
    required this.player,
    required this.meta,
    required this.colors,
  });

  @override
  State<_LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<_LyricsSheet> {
  late final Future<_LyricsResult?> _lyricsFuture;
  final ScrollController _scrollController = ScrollController();
  int _lastActiveLine = -1;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = _fetchLyrics();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<_LyricsResult?> _fetchLyrics() async {
    final title = (widget.meta['title'] ?? '').trim();
    final artist = (widget.meta['artist'] ?? '').trim();

    if (title.isEmpty) return null;

    final params = <String, String>{'track_name': title};

    if (artist.isNotEmpty && artist != 'Unknown Artist') {
      params['artist_name'] = artist;
    }

    Future<List<dynamic>> request(Uri uri) async {
      final res = await http.get(
        uri,
        headers: {'Accept': 'application/json', 'User-Agent': 'InfameApp/1.0'},
      );

      if (res.statusCode != 200) return [];
      final decoded = json.decode(res.body);
      return decoded is List ? decoded : [];
    }

    List<dynamic> results = await request(
      Uri.https('lrclib.net', '/api/search', params),
    );

    if (results.isEmpty) {
      final fallbackQuery = artist.isNotEmpty && artist != 'Unknown Artist'
          ? '$artist $title'
          : title;
      results = await request(
        Uri.https('lrclib.net', '/api/search', {'q': fallbackQuery}),
      );
    }

    if (results.isEmpty) return null;

    Map<String, dynamic>? best;

    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;
      final synced = item['syncedLyrics'];
      if (synced is String && synced.trim().isNotEmpty) {
        best = item;
        break;
      }
      best ??= item;
    }

    if (best == null) return null;

    return _LyricsResult(
      trackName: (best['trackName'] ?? title).toString(),
      artistName: (best['artistName'] ?? artist).toString(),
      plainLyrics: best['plainLyrics']?.toString(),
      syncedLyrics: best['syncedLyrics']?.toString(),
    );
  }

  List<_LyricLine> _parseSyncedLyrics(String raw) {
    final lines = <_LyricLine>[];

    for (final rawLine in raw.split(String.fromCharCode(10))) {
      final line = rawLine.trim();
      if (!line.startsWith('[')) continue;

      final end = line.indexOf(']');
      if (end <= 1) continue;

      final stamp = line.substring(1, end);
      final text = line.substring(end + 1).trim();
      if (text.isEmpty) continue;

      final timeParts = stamp.split(':');
      if (timeParts.length != 2) continue;

      final minutes = int.tryParse(timeParts[0]) ?? 0;
      final secondParts = timeParts[1].split('.');
      final seconds = int.tryParse(secondParts[0]) ?? 0;
      final fraction = secondParts.length > 1 ? secondParts[1] : '0';
      final padded = fraction.padRight(3, '0');
      final millis = int.tryParse(padded.substring(0, 3)) ?? 0;

      lines.add(
        _LyricLine(
          time: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: millis,
          ),
          text: text,
        ),
      );
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  int _activeLineIndex(List<_LyricLine> lines, Duration pos) {
    if (lines.isEmpty) return -1;

    int active = 0;
    for (int i = 0; i < lines.length; i++) {
      if (pos >= lines[i].time) {
        active = i;
      } else {
        break;
      }
    }

    return active;
  }

  void _scrollToActiveLine(int active) {
    if (active == _lastActiveLine || !_scrollController.hasClients) return;
    _lastActiveLine = active;

    final target = (active * 44.0).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _safeColors(widget.colors);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: BoxDecoration(
          color: _bg.withOpacity(0.96),
          borderRadius: BorderRadius.zero,
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors[0].withOpacity(0.34),
              _bg.withOpacity(0.98),
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 34,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Lyrics',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
                Text(
                  '${widget.meta['title'] ?? ''} â€¢ ${widget.meta['artist'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: _textSub,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: FutureBuilder<_LyricsResult?>(
                    future: _lyricsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Center(
                          child: CircularProgressIndicator(color: colors[1]),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Could not load lyrics.',
                            style: GoogleFonts.inter(
                              color: _textSub,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }

                      final result = snapshot.data;
                      if (result == null ||
                          (!result.hasSynced && !result.hasPlain)) {
                        return Center(
                          child: Text(
                            'No lyrics found for this track.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: _textSub,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }

                      if (result.hasSynced) {
                        final lines = _parseSyncedLyrics(result.syncedLyrics!);

                        if (lines.isNotEmpty) {
                          return StreamBuilder<Duration>(
                            stream: widget.player.positionStream,
                            builder: (context, posSnap) {
                              final pos = posSnap.data ?? Duration.zero;
                              final active = _activeLineIndex(lines, pos);

                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _scrollToActiveLine(active);
                              });

                              return ListView.builder(
                                controller: _scrollController,
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.only(
                                  top: 80,
                                  bottom: 160,
                                ),
                                itemCount: lines.length,
                                itemBuilder: (context, i) {
                                  final isActive = i == active;
                                  return AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOutCubic,
                                    style: GoogleFonts.inter(
                                      fontSize: isActive ? 23 : 19,
                                      height: 1.35,
                                      fontWeight: isActive
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                      color: isActive
                                          ? Colors.white
                                          : Colors.white.withOpacity(0.38),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Text(lines[i].text),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        }
                      }

                      final plain =
                          result.plainLyrics ?? result.syncedLyrics ?? '';

                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Text(
                          plain,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            height: 1.55,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withOpacity(0.86),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Lyrics by LRCLIB',
                  style: GoogleFonts.inter(
                    color: _textSub,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€ Queue Sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
