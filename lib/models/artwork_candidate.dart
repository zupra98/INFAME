class ArtworkCandidateModel {
  const ArtworkCandidateModel({
    required this.source,
    required this.imageUrl,
    this.thumbnailUrl = '',
    this.title = '',
    this.artist = '',
    this.year = '',
  });
  final String source;
  final String imageUrl;
  final String thumbnailUrl;
  final String title;
  final String artist;
  final String year;
}
