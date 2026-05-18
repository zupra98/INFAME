part of '../../main.dart';

class _MetadataStat extends StatelessWidget {
  final String label;
  final int value;
  final bool isDarkMode;

  const _MetadataStat({
    required this.label,
    required this.value,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final darkMode = isDarkMode;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.toString(),
            style: GoogleFonts.inter(
              color: darkMode ? _textPri : _lightText,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              color: darkMode ? _textSub : _lightSubtext,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  final String title;
  final bool isDarkMode;

  const _SettingsSectionTitle({required this.title, this.isDarkMode = true});

  @override
  Widget build(BuildContext context) {
    final darkMode = isDarkMode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: GoogleFonts.inter(
          color: darkMode ? _textPri : _lightText,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

class _SettingsPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final bool destructive;
  final VoidCallback onTap;
  final bool isDarkMode;

  const _SettingsPrimaryButton({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.destructive = false,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final darkMode = isDarkMode;
    final background = destructive
        ? (darkMode
            ? Colors.white.withOpacity(0.12)
            : Colors.black.withOpacity(0.05))
        : accent;
    final foreground =
        destructive ? (darkMode ? _textPri : _lightText) : Colors.black;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: destructive
                ? Colors.white.withOpacity(0.15)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: GoogleFonts.inter(
                  color: foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool isDarkMode;

  const _SettingsInfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final darkMode = isDarkMode;
    return GlassyContainer(
      radius: 22,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      customColor: darkMode
          ? Colors.white.withOpacity(0.070)
          : _lightGlassBase.withOpacity(0.72),
      customBorder: darkMode
          ? Colors.white.withOpacity(0.12)
          : Colors.black.withOpacity(0.08),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.16),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: darkMode ? _textPri : _lightText,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: darkMode ? _textSub : _lightSubtext,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final Color accent;
  final ValueChanged<bool> onChanged;
  final bool isDarkMode;

  const _SettingsSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.accent,
    required this.onChanged,
    this.enabled = true,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final darkMode = isDarkMode;
    final effectiveAccent = enabled ? accent : _textSub;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassyContainer(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        customColor: darkMode
            ? Colors.white.withOpacity(0.065)
            : _lightGlassBase.withOpacity(0.72),
        customBorder: darkMode
            ? Colors.white.withOpacity(0.10)
            : Colors.black.withOpacity(0.08),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: effectiveAccent.withOpacity(0.14),
              ),
              child: Icon(icon, color: effectiveAccent, size: 21),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: enabled
                          ? (darkMode ? _textPri : _lightText)
                          : (darkMode ? _textSub : _lightSubtext),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: darkMode ? _textSub : _lightSubtext,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeColor: accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback? onTap;
  final bool destructive;
  final bool isDarkMode;

  const _SettingsActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.destructive = false,
    this.isDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final darkMode = isDarkMode;
    final enabled = onTap != null;
    final effectiveAccent = destructive ? Colors.redAccent : accent;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1.0 : 0.45,
        child: GlassyContainer(
          radius: 20,
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 10),
          customColor: darkMode
              ? Colors.white.withOpacity(0.065)
              : _lightGlassBase.withOpacity(0.72),
          customBorder: destructive
              ? Colors.redAccent.withOpacity(0.30)
              : (darkMode
                  ? Colors.white.withOpacity(0.11)
                  : Colors.black.withOpacity(0.08)),
          child: Row(
            children: [
              Icon(icon, color: effectiveAccent, size: 22),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: darkMode ? _textPri : _lightText,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: darkMode ? _textSub : _lightSubtext,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: (darkMode ? _textSub : _lightSubtext).withOpacity(0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
