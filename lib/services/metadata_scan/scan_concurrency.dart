part of '../../main.dart';

class _ScanConcurrencyController {
  _ScanConcurrencyController({
    required int initialConcurrency,
    required this.maxConcurrency,
    this.minConcurrency = 3,
  }) : _currentConcurrency =
            initialConcurrency.clamp(minConcurrency, maxConcurrency).toInt();

  final int maxConcurrency;
  final int minConcurrency;
  int _currentConcurrency;

  int get currentConcurrency => _currentConcurrency;

  void increase({String reason = '', int step = 2}) {
    final next = (_currentConcurrency + step)
        .clamp(minConcurrency, maxConcurrency)
        .toInt();
    if (next == _currentConcurrency) return;
    _currentConcurrency = next;
    debugPrint(
      'MetadataScan concurrency increased to $_currentConcurrency reason=$reason',
    );
  }

  void reduce({String reason = '', int step = 2}) {
    final next = (_currentConcurrency - step)
        .clamp(minConcurrency, maxConcurrency)
        .toInt();
    if (next == _currentConcurrency) return;
    _currentConcurrency = next;
    debugPrint(
      'MetadataScan concurrency reduced to $_currentConcurrency reason=$reason',
    );
  }
}

bool _looksLikeRateLimitScanError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('429') ||
      text.contains('403') ||
      text.contains('rate limit') ||
      text.contains('rate-limit') ||
      text.contains('too many requests') ||
      text.contains('timeout') ||
      text.contains('socketexception') ||
      text.contains('503') ||
      text.contains('502');
}

Future<void> _runWithConcurrency<T>(
  List<T> items,
  _ScanConcurrencyController controller,
  Future<void> Function(T item, int index) worker,
) async {
  if (items.isEmpty) return;

  var nextIndex = 0;
  var active = 0;
  var completed = 0;
  final completer = Completer<void>();

  void pump() {
    if (completer.isCompleted) return;

    while (active < controller.currentConcurrency && nextIndex < items.length) {
      final item = items[nextIndex];
      final index = nextIndex;
      nextIndex++;
      active++;

      () async {
        Object? error;
        try {
          await worker(item, index);
        } catch (e) {
          error = e;
        } finally {
          active--;
          completed++;

          if (error != null) {
            if (_looksLikeRateLimitScanError(error)) {
              controller.reduce(reason: error.toString());
            } else if (completed % 25 == 0) {
              controller.reduce(reason: 'errors');
            }
          } else if (completed % 100 == 0) {
            controller.increase(reason: 'stable');
          }

          if (completed >= items.length && active == 0) {
            if (!completer.isCompleted) completer.complete();
          } else {
            pump();
          }
        }
      }();
    }
  }

  pump();
  await completer.future;
}

void _saveMetadataProgressSnapshot(Map<String, dynamic> payload) {
  final encoded = json.encode(payload);

  // Store progress in both places. sendDataToMain is not always delivered while
  // Android is busy or when the UI is rebuilding, so the app also polls this.
  FlutterForegroundTask.saveData(
    key: _metadataProgressPrefsKey,
    value: encoded,
  );

  SharedPreferences.getInstance().then((prefs) {
    prefs.setString(_metadataProgressPrefsKey, encoded);
  });
}

@pragma('vm:entry-point')
void metadataScanStartCallback() {
  FlutterForegroundTask.setTaskHandler(MetadataScanTaskHandler());
}
