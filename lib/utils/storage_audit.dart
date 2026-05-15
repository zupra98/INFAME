import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Storage audit helper for debugging storage leaks
class StorageAudit {
  static Future<void> auditAppStorage({String tag = 'StorageAudit'}) async {
    try {
      // Get all app storage directories
      final docsDir = await getApplicationDocumentsDirectory();
      final supportDir = await getApplicationSupportDirectory();
      final tempDir = await getTemporaryDirectory();

      // Audit each directory
      await _auditDirectory(docsDir, tag, 'Documents');
      await _auditDirectory(supportDir, tag, 'Support');
      await _auditDirectory(tempDir, tag, 'Temp');

      // Log summary
      debugPrint('$tag === Storage Audit Complete ===');
    } catch (e) {
      debugPrint('$tag Error during audit: $e');
    }
  }

  static Future<void> _auditDirectory(
    Directory dir,
    String tag,
    String label,
  ) async {
    try {
      if (!await dir.exists()) {
        debugPrint('$tag dir=$label path=${dir.path} status=does_not_exist');
        return;
      }

      int totalBytes = 0;
      int fileCount = 0;
      final largeFiles = <_FileInfo>[];

      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;

        try {
          final bytes = await entity.length();
          totalBytes += bytes;
          fileCount++;

          // Track files > 1MB
          if (bytes > 1024 * 1024) {
            largeFiles.add(_FileInfo(
              path: entity.path,
              bytes: bytes,
              modified: await entity.stat().then((s) => s.modified),
            ));
          }
        } catch (_) {}
      }

      final sizeMB = totalBytes / (1024 * 1024);
      debugPrint(
        '$tag dir=$label sizeMB=${sizeMB.toStringAsFixed(2)} files=$fileCount',
      );

      // Log largest files
      largeFiles.sort((a, b) => b.bytes.compareTo(a.bytes));
      for (final file in largeFiles.take(10)) {
        final fileMB = file.bytes / (1024 * 1024);
        debugPrint(
          '$tag largest path=${file.path} sizeMB=${fileMB.toStringAsFixed(2)} modified=${file.modified}',
        );
      }
    } catch (e) {
      debugPrint('$tag Error auditing $label: $e');
    }
  }

  /// Clean up stale temp files from metadata scanning
  static Future<void> cleanupStaleTempFiles({
    String tag = 'StorageAudit',
    int maxAgeHours = 1,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) return;

      final now = DateTime.now();
      int deletedCount = 0;
      int deletedBytes = 0;

      await for (final entity in tempDir.list(followLinks: false)) {
        if (entity is! File) continue;

        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : entity.path;

        // Clean up metadata scan temp files
        if (!name.startsWith('musix_meta_') &&
            !name.startsWith('musix_deep_')) {
          continue;
        }

        try {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);

          if (age.inHours >= maxAgeHours) {
            final bytes = await entity.length();
            await entity.delete();
            deletedCount++;
            deletedBytes += bytes;
            debugPrint('$tag cleaned path=$name bytes=$bytes');
          }
        } catch (_) {}
      }

      if (deletedCount > 0) {
        final deletedMB = deletedBytes / (1024 * 1024);
        debugPrint(
          '$tag cleanup deleted=$deletedCount sizeMB=${deletedMB.toStringAsFixed(2)}',
        );
      }
    } catch (e) {
      debugPrint('$tag Error cleaning temp files: $e');
    }
  }
}

class _FileInfo {
  final String path;
  final int bytes;
  final DateTime modified;

  _FileInfo({
    required this.path,
    required this.bytes,
    required this.modified,
  });
}

void debugPrint(String message) {
  print(message);
}
