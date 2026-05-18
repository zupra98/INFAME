part of '../../main.dart';

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDarkMode;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isDarkMode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Semantics(
        label: label,
        selected: isSelected,
        button: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.linear,
          width: double.infinity,
          height: 34,
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.10), width: 1),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isDarkMode
                      ? (isSelected
                          ? Colors.white
                          : Colors.white.withOpacity(0.72))
                      : (isSelected
                          ? _lightNavIconPink
                          : _lightNavIconPink.withOpacity(0.70)),
                  size: 17,
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 8.0,
                    fontWeight: FontWeight.w800,
                    color: isDarkMode
                        ? (isSelected
                            ? Colors.white
                            : Colors.white.withOpacity(0.72))
                        : (isSelected
                            ? _lightNavIconPink
                            : _lightNavIconPink.withOpacity(0.70)),
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

class _SearchModePill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDarkMode;
  final VoidCallback onTap;

  const _SearchModePill({
    required this.label,
    required this.isSelected,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isDarkMode
              ? (isSelected
                  ? Colors.white.withOpacity(0.12)
                  : Colors.white.withOpacity(0.03))
              : (isSelected
                  ? _lightAccentPink.withOpacity(0.12)
                  : Colors.black.withOpacity(0.03)),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isDarkMode
                ? (isSelected
                    ? Colors.white.withOpacity(0.24)
                    : Colors.white.withOpacity(0.12))
                : (isSelected
                    ? _lightAccentPink.withOpacity(0.28)
                    : Colors.black.withOpacity(0.10)),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: isDarkMode
                ? (isSelected ? Colors.white : Colors.white.withOpacity(0.72))
                : (isSelected
                    ? _lightAccentPink
                    : Colors.black.withOpacity(0.60)),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

extension _LibrarySharedWidgetsExtension on _MainScreenState {
  Widget _buildLibrarySearchBarFromPart(
    List<Color> colors, {
    required String hintText,
    TextEditingController? controller,
    ValueChanged<String>? onChanged,
    String? query,
  }) {
    final activeController = controller ?? _librarySearchController;
    final activeQuery = query ?? _libraryQuery;
    final bgColor = _isDarkMode
        ? Colors.white.withOpacity(0.06)
        : Colors.black.withOpacity(0.025);
    final borderColor = _isDarkMode
        ? Colors.white.withOpacity(0.14)
        : Colors.black.withOpacity(0.10);

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: _isDarkMode ? 14 : 8,
          sigmaY: _isDarkMode ? 14 : 8,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: TextField(
            controller: activeController,
            onChanged: onChanged ??
                (value) => _librarySetState(() => _libraryQuery = value),
            style: GoogleFonts.inter(
              color: _isDarkMode ? _textPri : _lightText,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              icon: Icon(Icons.manage_search_rounded, color: colors[1]),
              suffixIcon: activeQuery.trim().isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: _isDarkMode ? _textSub : _lightSubtext,
                      ),
                      onPressed: () {
                        activeController.clear();
                        if (onChanged == null) {
                          _librarySetState(() => _libraryQuery = '');
                        } else {
                          onChanged('');
                        }
                      },
                    )
                  : null,
              hintText: hintText,
              hintStyle: GoogleFonts.inter(
                color: _isDarkMode ? _textSub : _lightSubtext,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension _LibraryModeWidgetsExtension on _MainScreenState {
  Widget _buildLibraryModeRowFromPart() {
    final items = <({String label, String mode})>[
      (label: 'Albums', mode: 'albums'),
      (label: 'Songs', mode: 'songs'),
      (label: 'Artists', mode: 'artists'),
      (label: 'Liked', mode: 'liked'),
    ];

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: _LibraryModePill(
              label: items[i].label,
              isSelected: _libraryViewMode == items[i].mode,
              isDarkMode: _isDarkMode,
              onTap: () {
                _librarySetState(() => _libraryViewMode = items[i].mode);
                _saveUiPreferences();
              },
            ),
          ),
          if (i != items.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _LibraryInfoChip extends StatelessWidget {
  final String label;
  final Color accent;

  const _LibraryInfoChip({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: Colors.white.withOpacity(0.88),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LibraryModePill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDarkMode;
  final VoidCallback onTap;

  const _LibraryModePill({
    required this.label,
    required this.isSelected,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isDarkMode
              ? (isSelected
                  ? Colors.white.withOpacity(0.12)
                  : Colors.white.withOpacity(0.03))
              : (isSelected
                  ? _lightAccentPink.withOpacity(0.12)
                  : Colors.black.withOpacity(0.03)),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isDarkMode
                ? (isSelected
                    ? Colors.white.withOpacity(0.24)
                    : Colors.white.withOpacity(0.12))
                : (isSelected
                    ? _lightAccentPink.withOpacity(0.28)
                    : Colors.black.withOpacity(0.10)),
          ),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: isDarkMode
                  ? (isSelected ? Colors.white : Colors.white.withOpacity(0.68))
                  : (isSelected
                      ? _lightAccentPink
                      : Colors.black.withOpacity(0.58)),
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
