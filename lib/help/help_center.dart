import 'package:flutter/material.dart';

class HelpCenterPage extends StatelessWidget {
  final int initialIndex;
  const HelpCenterPage({super.key, this.initialIndex = 0});

  static const _sections = <_HelpSection>[
    _HelpSection(
      title: 'Dashboard',
      icon: Icons.space_dashboard_rounded,
      heroAsset: 'assets/images/help/dashboard_1.png',
      items: [
        _HelpItem(
          text: 'Tap the + icon to create a new group for your classes.',
          imageAsset: 'assets/images/help/dashboard_step1.png',
        ),
        _HelpItem(
          text: 'Tap a group to expand it to add a new schedule time inside each group.',
          imageAsset: 'assets/images/help/dashboard_step2.png',
        ),
        _HelpItem(
          text: 'Tap the person icon to assign enrolled students to a class. Students must be registered via the Enrollment page first.',
          imageAsset: 'assets/images/help/dashboard_step3.png',
        ),
        _HelpItem(
          text: 'Tap a schedule time to open the attendance list.',
          imageAsset: 'assets/images/help/dashboard_step4.png',
        ),
        _HelpItem(
          text: 'Swipe a group to the right or tap the edit icon to edit it.',
          imageAsset: 'assets/images/help/dashboard_step5.png',
        ),
        _HelpItem(
          text: 'Swipe a group to the left or tap the delete icon to delete it.',
          imageAsset: 'assets/images/help/dashboard_step6.png',
        ),
      ],
    ),
    _HelpSection(
      title: 'Scan Attendance',
      icon: Icons.camera_alt_rounded,
      heroAsset: 'assets/images/help/scan_1.png',
      items: [
        _HelpItem(
          text: 'Tap the "Take Attendance" button to open the camera.',
          imageAsset: 'assets/images/help/scanattendance_step1.png',
        ),
        _HelpItem(
          text:
              'Capture / upload one or more group photos, then tap the confirm icon to recognize students.',
          imageAsset: 'assets/images/help/scanattendance_step2.png',
        ),
        _HelpItem(
          text: 'Use the flashlight or turn on the grid / sound from the top-right menu when needed.',
          imageAsset: 'assets/images/help/scanattendance_step3.png',
        ),
      ],
    ),
    _HelpSection(
      title: 'Enrollment',
      icon: Icons.how_to_reg_rounded,
      heroAsset: 'assets/images/help/enroll_1.png',
      items: [
        _HelpItem(
          text: 'Select "Add New Face" to register a new student face image for recognition.',
          imageAsset: 'assets/images/help/enroll_step1.png',
        ),
        _HelpItem(
          text: 'Select "Update Student" to edit student info if details change.',
          imageAsset: 'assets/images/help/enroll_step2.png',
        ),
        _HelpItem(
          text:
              'Use clear, well-lit face photos for best recognition accuracy.',
          imageAsset: 'assets/images/help/enroll_step3.png',
        ),
      ],
    ),
    _HelpSection(
      title: 'Reports',
      icon: Icons.bar_chart_rounded,
      heroAsset: 'assets/images/help/reports_1.png',
      items: [
        _HelpItem(
          text: 'Select a date and group to view attendance performance.',
          imageAsset: 'assets/images/help/reports_step1.png',
        ),
        _HelpItem(
          text: 'Optionally filter by schedule time for deeper detail.',
          imageAsset: 'assets/images/help/reports_step2.png',
        ),
        _HelpItem(
          text: 'Tap the "Export Report" button to export as PDF for record keeping or sharing.',
          imageAsset: 'assets/images/help/reports_step3.png',
        ),
      ],
    ),
    _HelpSection(
      title: 'Settings',
      icon: Icons.settings_rounded,
      heroAsset: 'assets/images/help/settings_1.png',
      items: [
        _HelpItem(
          text: 'Update profile photo, view account info, and change password.',
          imageAsset: 'assets/images/help/settings_step1.png',
        ),
        _HelpItem(
          text: 'Toggle attendance reminders.',
          imageAsset: 'assets/images/help/settings_step2.png',
        ),
        _HelpItem(
          text:
              'Enable or disable Guide mode to show/hide the step-by-step tour.',
          imageAsset: 'assets/images/help/settings_step3.png',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final safeIndex = initialIndex.clamp(0, _sections.length - 1);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Help Center',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x1A000000)),
            ),
            child: const Text(
              "Choose a topic. Each section includes short tips and screenshots as an example.",
              style: TextStyle(color: Color(0x99000000), height: 1.35),
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < _sections.length; i++)
            _HelpSectionCard(
              section: _sections[i],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HelpSectionDetailPage(
                      section: _sections[i],
                      initialScrollToTop: i == safeIndex,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─── Data models ──────────────────────────────────────────────────────────────

class _HelpItem {
  final String text;

  /// Optional path to a screenshot asset shown below this bullet.
  /// If the asset is missing the image area is hidden gracefully.
  final String? imageAsset;

  const _HelpItem({required this.text, this.imageAsset});
}

class _HelpSection {
  final String title;
  final IconData icon;
  final String heroAsset;
  final List<_HelpItem> items;

  const _HelpSection({
    required this.title,
    required this.icon,
    required this.heroAsset,
    required this.items,
  });
}

// ─── Main list card ───────────────────────────────────────────────────────────

class _HelpSectionCard extends StatelessWidget {
  final _HelpSection section;
  final VoidCallback onTap;

  const _HelpSectionCard({
    required this.section,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x1A000000)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 96,
              height: 86,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F7FB),
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                section.heroAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(section.icon, color: const Color(0xFF1565C0)),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      section.items.isEmpty ? '' : section.items.first.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0x99000000),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right_rounded, color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Detail page ──────────────────────────────────────────────────────────────

class HelpSectionDetailPage extends StatelessWidget {
  final _HelpSection section;
  final bool initialScrollToTop;

  const HelpSectionDetailPage({
    super.key,
    required this.section,
    this.initialScrollToTop = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          section.title,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          // ── Hero image at top ──────────────────────────────────────────
          _ScreenshotCard(
            imagePath: section.heroAsset,
            fallbackIcon: section.icon,
          ),
          const SizedBox(height: 16),
          // ── Per-step items ─────────────────────────────────────────────
          for (int i = 0; i < section.items.length; i++) ...[
            _BulletCard(
              number: i + 1,
              text: section.items[i].text,
            ),
            if (section.items[i].imageAsset != null)
              _ScreenshotCard(
                imagePath: section.items[i].imageAsset!,
                fallbackIcon: section.icon,
                topPadding: 8,
              ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

// ─── Shared sub-widgets ───────────────────────────────────────────────────────

/// Bullet card: numbered circle + text.
class _BulletCard extends StatelessWidget {
  final int number;
  final String text;

  const _BulletCard({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1A000000)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFF1565C0),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xCC000000),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Screenshot card: shows an asset image or collapses when the asset is missing.
/// Tap the thumbnail to open a full-screen pinch-to-zoom viewer.
class _ScreenshotCard extends StatefulWidget {
  final String imagePath;
  final IconData fallbackIcon;
  final double topPadding;

  const _ScreenshotCard({
    required this.imagePath,
    required this.fallbackIcon,
    this.topPadding = 0,
  });

  @override
  State<_ScreenshotCard> createState() => _ScreenshotCardState();
}

class _ScreenshotCardState extends State<_ScreenshotCard> {
  bool _hasError = false;

  void _openFullscreen(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black87,
        child: Stack(
          children: [
            // ── Zoomable image ──────────────────────────────────────────
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Image.asset(
                  widget.imagePath,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            // ── Close button ────────────────────────────────────────────
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            // ── Tap-anywhere-to-close hint ──────────────────────────────
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Pinch to zoom  •  Tap ✕ to close',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: widget.topPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320, maxWidth: 220),
          child: GestureDetector(
            onTap: () => _openFullscreen(context),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0x1A000000)),
                      color: const Color(0xFFF5F7FB),
                    ),
                    child: Image.asset(
                      widget.imagePath,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) {
                            if (mounted) setState(() => _hasError = true);
                          },
                        );
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                // Small expand-icon badge in corner
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.open_in_full_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
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