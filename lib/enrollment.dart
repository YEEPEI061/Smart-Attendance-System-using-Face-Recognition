import 'package:flutter/material.dart';
// import 'package:showcaseview/showcaseview.dart';
// import 'package:shared_preferences/shared_preferences.dart';
import 'package:userinterface/update_student.dart';
// import 'package:userinterface/help/app_tour.dart';

class EnrollmentChoicePage extends StatelessWidget {
  const EnrollmentChoicePage({super.key});

 /*@override
  State<EnrollmentChoicePage> createState() => _EnrollmentChoicePageState();
}

class _EnrollmentChoicePageState extends State<EnrollmentChoicePage> {
  final GlobalKey _keyAddFace = GlobalKey();
  final GlobalKey _keyUpdateStudent = GlobalKey();

  // Prevents the auto-start from firing more than once per page visit
  bool _tourScheduled = false;

  void _startTour(BuildContext innerCtx) {
    ShowCaseWidget.of(innerCtx).startShowCase([_keyAddFace, _keyUpdateStudent]);
  }*/

  @override
  Widget build(BuildContext context) {
    /*return ShowCaseWidget(
      onFinish: () {
        // Offer "Don't show again?" — deferred so the overlay fully closes.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) AppTour.showDontShowAgainDialog(context);
        });
      },
      builder: (BuildContext innerCtx) {
        // Auto-start every visit when guide mode is ON (no "seen" flag).
        if (!_tourScheduled) {
          _tourScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            final prefs = await SharedPreferences.getInstance();
            final bool guide = prefs.getBool('guide_mode') ?? true;
            if (guide && mounted) {
              _startTour(innerCtx);
            }
          });
        }

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.black),
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline_rounded,
                    color: Color(0xFF9E9E9E)),
                tooltip: 'Show Guide',
                onPressed: () => _startTour(innerCtx),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Select an option",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: Showcase(
                        key: _keyAddFace,
                        title: 'Step 1 — Add New Face',
                        description:
                            'Capture or upload a photo to register a new student.',
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
                        tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: _buildOptionCard(
                          icon: Icons.face_retouching_natural_rounded,
                          title: "Add New Face",
                          subtitle: "Register a new student face",
                          onTap: () =>
                              Navigator.pushNamed(context, '/enroll_face'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Showcase(
                        key: _keyUpdateStudent,
                        title: 'Step 2 — Update Student',
                        description:
                            'Edit an existing student\'s name, ID, or course.',
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
                        tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: _buildOptionCard(
                          icon: Icons.edit_rounded,
                          title: "Update Student",
                          subtitle: "Edit student information",
                          onTap: () {
                            Navigator.of(context).push(PageRouteBuilder(
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      const UpdateStudentPage(),
                              transitionsBuilder: (context, animation,
                                  secondaryAnimation, child) {
                                return FadeTransition(
                                    opacity: animation, child: child);
                              },
                            ));
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),*/
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔤 Title
            const Text(
              "Select an option",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 30),

            // 🎯 Cards Row
            Row(
              children: [
                Expanded(
                  child: _buildOptionCard(
                    icon: Icons.face_retouching_natural_rounded,
                    title: "Add New Face",
                    subtitle: "Register a new student face",
                    onTap: () {
                      Navigator.pushNamed(context, '/enroll_face');
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildOptionCard(
                    icon: Icons.edit_rounded,
                    title: "Update Student",
                    subtitle: "Edit student information",
                    onTap: () {
                      Navigator.of(context).push(PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            const UpdateStudentPage(),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                              opacity: animation, child: child);
                        },
                      ));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF1565C0),
        unselectedItemColor: Colors.grey,
        currentIndex: 1,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        selectedIconTheme: const IconThemeData(size: 24),
        unselectedIconTheme: const IconThemeData(size: 24),
        onTap: (index) {
          if (index == 0) {
            Navigator.pushNamed(context, '/dashboard');
          } else if (index == 1) {
            Navigator.pushNamed(context, '/enroll');
          } else if (index == 2) {
            Navigator.pushNamed(context, '/reports');
          } else if (index == 3) {
            Navigator.pushNamed(context, '/settings');
          }
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.space_dashboard_rounded), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt_rounded), label: 'Enrollment'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded), label: 'Reports'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 180,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF1565C0),
                size: 30,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}