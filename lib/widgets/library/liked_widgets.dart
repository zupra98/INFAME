part of '../../main.dart';

extension _LikedWidgetsExtension on _MainScreenState {
  Widget _buildLikedViewFromPart(
    List<Color> colors,
    String query,
    Color bgColor,
  ) {
    return _buildSongsView(
      colors,
      query,
      bgColor,
      likedOnly: true,
      title: 'Liked',
      subtitle: 'Songs you have liked.',
      scrollKey: 'library_liked_scroll',
    );
  }
}
