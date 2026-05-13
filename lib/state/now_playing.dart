import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;

const List<Color> defaultDynamicColors = [
  Color(0xFF2A2430),
  Color(0xFFE6C8A0),
  Color(0xFF243447),
  Color(0xFF15151B),
];

class NowPlaying extends ChangeNotifier {
  static final NowPlaying _instance = NowPlaying._();
  factory NowPlaying() => _instance;
  NowPlaying._();

  drive.File? track;
  List<drive.File> queue = [];
  int queueIndex = -1;
  String? currentCoverUrl;
  List<Color> dynamicColors = List<Color>.from(defaultDynamicColors);
  bool shuffleEnabled = false;
  bool repeatOne = false;

  void toggleShuffle() {
    shuffleEnabled = !shuffleEnabled;
    notifyListeners();
  }

  void toggleRepeatOne() {
    repeatOne = !repeatOne;
    notifyListeners();
  }

  void refresh() {
    notifyListeners();
  }

  void setTrack(
    drive.File t,
    List<drive.File> q,
    int idx, {
    String? coverUrl,
    List<Color>? colors,
  }) {
    track = t;
    queue = q;
    queueIndex = idx;
    currentCoverUrl = coverUrl;
    dynamicColors = List<Color>.from(colors ?? defaultDynamicColors);
    notifyListeners();
  }

  drive.File? get nextTrack {
    if (queueIndex >= 0 && queueIndex + 1 < queue.length) {
      return queue[queueIndex + 1];
    }
    return null;
  }

  drive.File? get prevTrack {
    if (queueIndex > 0 && queueIndex <= queue.length) {
      return queue[queueIndex - 1];
    }
    return null;
  }
}