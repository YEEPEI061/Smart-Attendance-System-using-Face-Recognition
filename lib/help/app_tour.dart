import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Public helpers ────────────────────────────────────────────────────────────

class AppTour {
  /// Shows a styled "Don't show again?" dialog matching the app design.
  /// If the user confirms, guide_mode is turned off in SharedPreferences.
  static Future<void> showDontShowAgainDialog(BuildContext context) async {
    if (!context.mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFE3F2FD),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline_rounded,
                    color: Color(0xFF1565C0), size: 28),
              ),
              const SizedBox(height: 14),
              // Title
              const Text(
                'Tour complete!',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87),
              ),
              const SizedBox(height: 8),
              // Message
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                  children: [
                    TextSpan(
                      text: 'Hide this guide on future visits?\nYou can replay it anytime with the ',
                    ),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(
                        Icons.help_outline_rounded,
                        size: 16,
                        color: Color(0xFF9E9E9E),
                      ),
                    ),
                    TextSpan(
                      text: ' icon.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              // Primary button — full width blue "Got it!"
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Got it!',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 10),
              // Secondary — small underlined "Don't show again"
              GestureDetector(
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('guide_mode', false);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    "Don't show again",
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.black38,
                        decoration: TextDecoration.underline),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Legacy stub — auto-start is handled inside [tourWrapper].
  static Future<void> maybeAutoStart(
    BuildContext context, {
    required String pageId,
    required List<GlobalKey> keys,
  }) async {}
}

/// Wraps [child] in a [ShowCaseWidget].
///
/// - [pageId] + [autoStartKeys]: auto-start every visit when guide_mode is ON.
/// - [readyFuture]: auto-start waits for this future before firing.
/// - After the tour finishes, a "Don't show again?" dialog is offered.
Widget tourWrapper({
  String? pageId,
  List<GlobalKey>? autoStartKeys,
  Future<void>? readyFuture,
  VoidCallback? onFinish,
  required Widget child,
}) {
  return _TourWrapper(
    pageId: pageId,
    autoStartKeys: autoStartKeys,
    readyFuture: readyFuture,
    onFinish: onFinish,
    child: child,
  );
}

/// Returns a styled help icon for use in AppBar.actions.
/// Looks like a blue circle with a white ? inside.
Widget tourHelpIcon({required VoidCallback onPressed}) {
  return Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0xFF1565C0),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.question_mark_rounded,
            color: Colors.white, size: 16),
      ),
    ),
  );
}

/// Wraps [child] in a [Showcase] with consistent compact styling.
Widget tourTarget({
  required GlobalKey key,
  required String title,
  required String description,
  ShapeBorder? shapeBorder,
  required Widget child,
}) {
  return Showcase(
    key: key,
    title: title,
    description: description,
    tooltipBackgroundColor: Colors.white,
    textColor: Colors.black87,
    titleTextStyle: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Colors.black87,
    ),
    descTextStyle: const TextStyle(
      fontSize: 12,
      color: Color(0x99000000),
      height: 1.4,
    ),
    tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    targetShapeBorder: shapeBorder ??
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
    child: child,
  );
}

// ─── Internal implementation ───────────────────────────────────────────────────

class _TourWrapper extends StatefulWidget {
  final String? pageId;
  final List<GlobalKey>? autoStartKeys;
  final Future<void>? readyFuture;
  final VoidCallback? onFinish;
  final Widget child;

  const _TourWrapper({
    this.pageId,
    this.autoStartKeys,
    this.readyFuture,
    this.onFinish,
    required this.child,
  });

  @override
  State<_TourWrapper> createState() => _TourWrapperState();
}

class _TourWrapperState extends State<_TourWrapper> {
  bool _autoStartScheduled = false;

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      onFinish: () {
        if (widget.pageId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) AppTour.showDontShowAgainDialog(context);
          });
        }
        widget.onFinish?.call();
      },
      builder: (BuildContext innerCtx) {
        if (!_autoStartScheduled &&
            widget.pageId != null &&
            widget.autoStartKeys != null) {
          _autoStartScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (widget.readyFuture != null) await widget.readyFuture;
            // Short delay so targets are rendered before the tour starts.
            await Future<void>.delayed(const Duration(milliseconds: 200));
            final prefs = await SharedPreferences.getInstance();
            final bool guide = prefs.getBool('guide_mode') ?? true;
            if (guide && mounted) {
              ShowCaseWidget.of(innerCtx)
                  .startShowCase(widget.autoStartKeys!);
            }
          });
        }
        return widget.child;
      },
    );
  }
}