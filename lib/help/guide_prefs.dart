import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:userinterface/help/feature_guide_dialog.dart';

class GuidePrefs {
  static const String keyGuideMode = 'guide_mode';

  static String seenKeyForPage(String pageId) => 'seen_tour_$pageId';

  static Future<bool> isGuideModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyGuideMode) ?? true;
  }

  static Future<void> setGuideModeEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyGuideMode, value);
  }

  static Future<bool> hasSeenPage(String pageId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(seenKeyForPage(pageId)) ?? false;
  }

  static Future<void> setSeenPage(String pageId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(seenKeyForPage(pageId), value);
  }

  static Future<void> maybeShowIntroDialog(
    BuildContext context, {
    required String pageId,
    required String title,
    List<String>? bullets,
    List<GuideStep>? steps,
  }) async {
    final enabled = await isGuideModeEnabled();
    if (!enabled) return;

    final seen = await hasSeenPage(pageId);
    if (seen) return;

    if (!context.mounted) return;

    final resolvedSteps = steps ??
        (bullets ?? const <String>[]).map((b) {
          return GuideStep(
            title: title,
            description: b,
          );
        }).toList();

    if (resolvedSteps.isEmpty) {
      await setSeenPage(pageId, true);
      return;
    }

    final result = await showFeatureGuideDialog(
      context,
      headline: title,
      steps: resolvedSteps,
    );

    // If user unchecked "Don't show again", we keep it un-seen.
    // (Dialog returns bool via Navigator.pop; barrier dismiss returns null.)
    final dontShowAgain = (result is bool) ? result : true;
    if (dontShowAgain) {
      await setSeenPage(pageId, true);
    }
  }
}