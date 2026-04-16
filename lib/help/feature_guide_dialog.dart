import 'package:flutter/material.dart';

class GuideStep {
  final String title;
  final String description;
  final String? assetImagePath;

  const GuideStep({
    required this.title,
    required this.description,
    this.assetImagePath,
  });
}

Future<bool?> showFeatureGuideDialog(
  BuildContext context, {
  required String headline,
  required List<GuideStep> steps,
}) async {
  if (!context.mounted) return null;

  return await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Guide',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, _, __) => _FeatureGuideDialog(
      headline: headline,
      steps: steps,
    ),
  );
}

class _FeatureGuideDialog extends StatefulWidget {
  final String headline;
  final List<GuideStep> steps;

  const _FeatureGuideDialog({
    required this.headline,
    required this.steps,
  });

  @override
  State<_FeatureGuideDialog> createState() => _FeatureGuideDialogState();
}

class _FeatureGuideDialogState extends State<_FeatureGuideDialog> {
  final PageController _controller = PageController();
  int _index = 0;
  bool dontShowAgain = true;

  bool get _isLast => _index == widget.steps.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      Navigator.of(context).pop(dontShowAgain);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];

    return SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 340,
            margin: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.headline,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(dontShowAgain),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.black54,
                        splashRadius: 18,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),

                // Image / preview
                Container(
                  height: 180,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x1A000000)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: widget.steps.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) {
                      final s = widget.steps[i];
                      final path = s.assetImagePath;
                      if (path == null || path.isEmpty) {
                        return const Center(
                          child: Icon(
                            Icons.image_outlined,
                            size: 56,
                            color: Color(0xFFBDBDBD),
                          ),
                        );
                      }
                      return Image.asset(
                        path,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 56,
                            color: Color(0xFFBDBDBD),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 12),

                // Title + text
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        step.description,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: Color(0x99000000),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.steps.length, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF1565C0)
                            : const Color(0x331565C0),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),

                // Don't show again
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                  child: CheckboxListTile(
                    value: dontShowAgain,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: const Color(0xFF1565C0),
                    title: const Text(
                      "Don't show again",
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => setState(() => dontShowAgain = v ?? true),
                  ),
                ),

                // Actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _index == 0 ? null : _back,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1565C0),
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Color(0x1A000000)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Back',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            _isLast ? 'Done' : 'Next',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
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