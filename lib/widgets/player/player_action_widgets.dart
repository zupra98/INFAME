part of '../../main.dart';

class _PremiumActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final List<Color> colors;
  final bool isDarkMode;

  const _PremiumActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.10)
                  : _lightSurface.withOpacity(0.60),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.08)
                    : _lightAccentPink.withOpacity(0.20),
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isDarkMode
                      ? Colors.white.withOpacity(0.92)
                      : _lightAccentPink,
                  size: 21,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: isDarkMode
                        ? Colors.white.withOpacity(0.70)
                        : _lightText,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
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

class _AudioQualityBadge extends StatelessWidget {
  final drive.File track;
  final Duration? duration;
  final Color accent;

  const _AudioQualityBadge({
    required this.track,
    required this.duration,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final label = DriveUtils.audioQualityLabel(
      track,
      duration,
    ).replaceAll(' â€¢ ', '  â€¢  ').toUpperCase();

    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        color: Colors.white.withOpacity(0.58),
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }
}

// â”€â”€â”€ System Volume Slider â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SystemVolumeSlider extends StatefulWidget {
  final bool isDarkMode;
  const _SystemVolumeSlider({this.isDarkMode = true});

  @override
  State<_SystemVolumeSlider> createState() => _SystemVolumeSliderState();
}

class _SystemVolumeSliderState extends State<_SystemVolumeSlider> {
  double _volume = 0.5;

  @override
  void initState() {
    super.initState();
    VolumeController.instance.showSystemUI = false;
    VolumeController.instance.getVolume().then((vol) {
      if (mounted) setState(() => _volume = vol);
    });
    VolumeController.instance.addListener((vol) {
      if (mounted) setState(() => _volume = vol);
    }, fetchInitialVolume: true);
  }

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2.6,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
      ),
      child: Slider(
        value: _volume,
        activeColor: widget.isDarkMode
            ? Colors.white.withOpacity(0.60)
            : _lightAccentPink,
        inactiveColor: widget.isDarkMode
            ? Colors.white.withOpacity(0.10)
            : _lightAccentPink.withOpacity(0.14),
        onChanged: (v) {
          VolumeController.instance.setVolume(v);
          setState(() => _volume = v);
        },
      ),
    );
  }
}
