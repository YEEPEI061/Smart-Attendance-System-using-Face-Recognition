import 'dart:async';
import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Public helpers ────────────────────────────────────────────────────────────

class AppTour {
  /// Shows a "Tour complete!" dialog with only a "Got it!" button.
  /// The user can replay the tour anytime via the ? icon.
  static Future<void> showTourCompleteDialog(BuildContext context) async {
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
                    TextSpan(text: 'You can replay this tour anytime using the '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(
                        Icons.help_outline_rounded,
                        size: 16,
                        color: Color(0xFF9E9E9E),
                      ),
                    ),
                    TextSpan(text: ' icon.'),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              // Got it button
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
            ],
          ),
        ),
      ),
    );
  }

  /// Legacy stub kept for backward compatibility.
  static Future<void> maybeAutoStart(
    BuildContext context, {
    required String pageId,
    required List<GlobalKey> keys,
  }) async {}
}

/// Wraps [child] in a [ShowCaseWidget].
///
/// - [pageId] is combined with [userId] to form a per-user seen key:
///   `seen_tour_<pageId>_<userId>`.  This means a new user on the same
///   device always gets the tour on their first login.
/// - Auto-starts when the per-user seen key is not yet set.
/// - [readyFuture]: waits for this future then one extra frame so all
///   Showcase targets are registered before the tour fires.
/// - When the tour finishes the seen flag is saved silently and a
///   "Tour complete!" dialog (Got it only) is shown.
Widget tourWrapper({
  String? pageId,
  String? userId,
  List<GlobalKey>? autoStartKeys,
  Future<void>? readyFuture,
  VoidCallback? onFinish,
  required Widget child,
}) {
  return _TourWrapper(
    pageId: pageId,
    userId: userId,
    autoStartKeys: autoStartKeys,
    readyFuture: readyFuture,
    onFinish: onFinish,
    child: child,
  );
}

/// Styled help icon for AppBar.actions — blue circle with white ?.
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
  final String? userId;
  final List<GlobalKey>? autoStartKeys;
  final Future<void>? readyFuture;
  final VoidCallback? onFinish;
  final Widget child;

  const _TourWrapper({
    this.pageId,
    this.userId,
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

  // Set by the Builder INSIDE ShowCaseWidget.builder so it is a true
  // DESCENDANT context of ShowCaseWidget. ShowCaseWidget.of() uses
  // findAncestorStateOfType which requires a descendant — using the
  // ShowCaseWidget's own builder context directly does NOT work.
  BuildContext? _showcaseCtx;

  /// Per-user seen key: seen_tour_<pageId>_<userId>
  /// Falls back to seen_tour_<pageId> if userId is not available.
  String get _seenKey {
    final page = widget.pageId ?? '';
    final uid = widget.userId;
    return uid != null && uid.isNotEmpty
        ? 'seen_tour_${page}_$uid'
        : 'seen_tour_$page';
  }

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      onFinish: () {
        if (widget.pageId != null) {
          // Save seen flag immediately so the tour never auto-starts again.
          SharedPreferences.getInstance().then((prefs) {
            prefs.setBool(_seenKey, true);
          });

          // Show "Tour complete!" dialog.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) AppTour.showTourCompleteDialog(context);
          });
        }
        widget.onFinish?.call();
      },
      builder: (BuildContext innerCtx) {
        // Schedule auto-start once per State lifetime.
        if (!_autoStartScheduled &&
            widget.pageId != null &&
            widget.autoStartKeys != null) {
          _autoStartScheduled = true;

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            // Wait for data (e.g. folders) to finish loading.
            if (widget.readyFuture != null) await widget.readyFuture;

            // Wait one more frame so every Showcase target is rendered
            // and registered with ShowCaseWidget before starting.
            final frameReady = Completer<void>();
            WidgetsBinding.instance
                .addPostFrameCallback((_) => frameReady.complete());
            await frameReady.future;

            if (!mounted || _showcaseCtx == null) return;

            final prefs = await SharedPreferences.getInstance();
            final bool seen = prefs.getBool(_seenKey) ?? false;

            if (!seen && mounted && _showcaseCtx != null) {
              ShowCaseWidget.of(_showcaseCtx!)
                  .startShowCase(widget.autoStartKeys!);
            }
          });
        }

        // Wrap child in Builder so _showcaseCtx is a TRUE DESCENDANT of
        // ShowCaseWidget. This is required for ShowCaseWidget.of() to work —
        // it traverses up the tree looking for ShowCaseWidget as an ancestor,
        // so the context must be BELOW ShowCaseWidget in the element tree.
        return Builder(builder: (BuildContext descendantCtx) {
          _showcaseCtx = descendantCtx; // updated every rebuild
          return widget.child;
        });
      },
    );
  }
}