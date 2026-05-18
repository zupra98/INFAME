part of '../../main.dart';

extension _HomeWidgetsExtension on _MainScreenState {
  List<Widget> _homeAlbumShelfSliversFromPart({
    required String title,
    required String subtitle,
    required List<Map<String, String>> items,
    double bottomPadding = 22,
  }) {
    if (items.isEmpty) return const <Widget>[];

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        sliver: SliverToBoxAdapter(
          child: _HomeSectionHeader(title: title, subtitle: subtitle),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding),
        sliver: SliverToBoxAdapter(
          child: SizedBox(
            height: 214,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final info = items[i];
                return _HomeAlbumCard(
                  info: info,
                  onTap: () => _openAlbumByBrain(info),
                  isDarkMode: _isDarkMode,
                );
              },
            ),
          ),
        ),
      ),
    ];
  }
}
