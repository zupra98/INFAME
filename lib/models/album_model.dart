class AlbumModel {
  const AlbumModel({
    required this.id,
    required this.title,
    this.artist = '',
    this.coverUrl = '',
    this.source = '',
  });
  final String id;
  final String title;
  final String artist;
  final String coverUrl;
  final String source;
}
