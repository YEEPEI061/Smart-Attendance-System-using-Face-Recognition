import 'package:shared_preferences/shared_preferences.dart';

class GuidePrefs {
  static String _seenKey(String pageId) => 'seen_tour_$pageId';

  /// Returns true if the user has already seen the tour for [pageId].
  static Future<bool> hasSeenPage(String pageId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_seenKey(pageId)) ?? false;
  }

  /// Marks [pageId] as seen so its tour will not auto-start again.
  static Future<void> setSeenPage(String pageId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey(pageId), value);
  }
}
