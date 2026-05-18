class LibraryStateSnapshot {
  const LibraryStateSnapshot({
    required this.albumCount,
    required this.trackCount,
    required this.isScanning,
  });
  final int albumCount;
  final int trackCount;
  final bool isScanning;
}
