import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:userinterface/providers/auth_provider.dart';
import 'package:userinterface/main.dart';
import 'dart:developer';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:userinterface/changepsw.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:userinterface/services/notification_service.dart';
import 'package:userinterface/services/attendance_reminder_sync.dart';
// import 'package:showcaseview/showcaseview.dart'; // tour disabled
// import 'package:userinterface/help/app_tour.dart'; // tour disabled
import 'package:userinterface/help/help_center.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  /*final GlobalKey _tourProfileKey = GlobalKey();
  final GlobalKey _tourChangePswKey = GlobalKey();
  final GlobalKey _tourRemindersKey = GlobalKey();
  final GlobalKey _tourGuideModeKey = GlobalKey();
  final GlobalKey _tourHelpCenterKey = GlobalKey();
  final GlobalKey _tourSignOutKey = GlobalKey();*/

  bool attendanceReminders = true;
  String? _profileImageUrl;
  // bool _isProfileLoading = true;
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _emailController = TextEditingController();
    _fetchProfile();
    // Initialize Notification Service
    NotificationService.init();
    
    // Load preference & automatically sync with Database
    _loadAndSyncReminders();
  }

  Future<void> _loadAndSyncReminders() async {
    final prefs = await SharedPreferences.getInstance();
    bool isEnabled = prefs.getBool('reminders_enabled') ?? true;
    
    setState(() {
      attendanceReminders = isEnabled;
    });

    if (isEnabled) {
      // Once open settings send notification 
      //await _setupAttendanceReminder();
    }
  }

  Future<void> _setupAttendanceReminder() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userId;
    if (userId == null) return;
    final baseUrl = dotenv.env['BASE_URL']!;

    log("REAL-SYNC: Fetching schedule for Lecturer ID: $userId");

    await AttendanceReminderSync.sync(baseUrl: baseUrl, userId: userId);
  }

  /*DateTime _parseClassTime(String timeStr) {
    final now = DateTime.now();
    try {
      final parts = timeStr.split(' ')[0].split(':');
      return DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
    } catch (e) { return now.subtract(const Duration(days: 1)); }
  }*/

  Future<void> _fetchProfile() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userId;

    try {
      final baseUrl = dotenv.env['BASE_URL']!;
      final response = await http.get(Uri.parse('$baseUrl/users/$userId'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _usernameController.text = data['username'] ?? '';
          _emailController.text = data['email'] ?? '';

          if (data['profile_image_url'] != null && data['profile_image_url'].toString().isNotEmpty) {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            
            setState(() {
              // Append the timestamp as a query parameter
              _profileImageUrl = '$baseUrl/${data['profile_image_url']}?v=$timestamp';
              
              // Clear the local temporary file
              _selectedImage = null;
            });
          }
          // _isProfileLoading = false;
        });
      }
    } catch (e) {
      log("Error fetching profile: $e");
    }
  }

  Future<void> _uploadPhoto(File imageFile) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userId;
    final baseUrl = dotenv.env['BASE_URL']!;

    try {
      var request = http.MultipartRequest(
          'POST', Uri.parse('$baseUrl/users/upload_photo'));
      request.fields['user_id'] = userId.toString();
      request.files
          .add(await http.MultipartFile.fromPath('image', imageFile.path));

      var response = await request.send();
      if (response.statusCode == 200) {
        log("Uploaded and saved to database!");
        _fetchProfile();
      }
    } catch (e) {
      log("Upload error: $e");
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      File imageFile = File(pickedFile.path);
      setState(() {
        _selectedImage = imageFile;
      });
      await _uploadPhoto(imageFile);
    }
  }

  void _viewPhoto() {
    if (_profileImageUrl == null && _selectedImage == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(
                  image: (_selectedImage != null
                      ? FileImage(_selectedImage!)
                      : NetworkImage(_profileImageUrl!)) as ImageProvider,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close",
                  style: TextStyle(fontSize: 18, color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Choose existing photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_rounded),
                title: const Text('View Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _viewPhoto();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleSignOut() async {
    bool? confirmSignOut = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          insetPadding: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.logout_rounded,
                  color: Color(0xFFF84F31),
                  size: 48,
                ),
                const SizedBox(height: 12),
                const Text(
                  "Sign Out?",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Are you sure you want to sign out?\nYou will need to login again to access your account.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    // Styled Cancel Button
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFF6F6F6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text(
                          "Cancel",
                          style: TextStyle(
                              color: Colors.grey, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF84F31),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text(
                          "Sign Out",
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        );
      },
    );

    if (confirmSignOut == true) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.userId;

      try {
        final baseUrl = dotenv.env['BASE_URL']!;
        final url = Uri.parse('$baseUrl/logout');

        final response = await http.post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"user_id": userId}),
        );

        if (response.statusCode == 200) {
          log('Sign out logged successfully');
        } else {
          log('Failed to log sign out: ${response.body}');
        }
      } catch (e) {
        log('Error logging sign out: $e');
      }

      await authProvider.signOut();

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
          (_) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: const Color(0xFFFFFFFF),
          appBar: AppBar(
              backgroundColor: const Color(0xFFFFFFFF),
              elevation: 0,
              centerTitle: true,
              actions: const []),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF1565C0),
          unselectedItemColor: Colors.grey,
          currentIndex: 3,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedIconTheme: const IconThemeData(size: 24),
          unselectedIconTheme: const IconThemeData(size: 24),
          onTap: (index) {
            if (index == 0) {
              Navigator.pushReplacementNamed(context, '/dashboard');
            } else if (index == 1) {
              Navigator.pushReplacementNamed(context, '/enroll');
            } else if (index == 2) {
              Navigator.pushReplacementNamed(context, '/reports');
            } else if (index == 3) {
              // Stay on Settings
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
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x1A000000)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Account Settings",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Color(0x50000000),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 1,
                      color: const Color(0x1A000000),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _showPhotoOptions,
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey,
                              image: _selectedImage != null
                                  ? DecorationImage(
                                      image: FileImage(_selectedImage!),
                                      fit: BoxFit.cover)
                                  : (_profileImageUrl != null
                                      ? DecorationImage(
                                          image:
                                              NetworkImage(_profileImageUrl!),
                                          fit: BoxFit.cover)
                                      : null),
                            ),
                            child: (_selectedImage == null &&
                                    _profileImageUrl == null)
                                ? const Center(
                                    child: Icon(Icons.person_rounded,
                                        size: 30, color: Colors.white))
                                : null,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: GestureDetector(
                            onTap: _showPhotoOptions,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  "Update Photo",
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Color(0xFF1565C0),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  ".JPG, .PNG, max 5MB",
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ), // Row — profile
                    const SizedBox(height: 15),
                    const Text(
                      "Username",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 5),
                    TextFormField(
                      enabled: false,
                      controller: _usernameController,
                      style: const TextStyle(
                        color: Colors.black54, // ensures the text is visible
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Color(0xFFF6F6F6),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide:
                              BorderSide(color: Color(0x1A000000), width: 1),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide:
                              BorderSide(color: Color(0x1A000000), width: 1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Email",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 5),
                    TextFormField(
                      enabled: false,
                      controller: _emailController,
                      style: const TextStyle(
                        color: Colors.black54, // ensures the text is visible
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Color(0xFFF6F6F6),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide:
                              BorderSide(color: Color(0x1A000000), width: 1),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide:
                              BorderSide(color: Color(0x1A000000), width: 1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () {
                            if (!mounted) return;

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const ChangePasswordPage()),
                            );
                          },
                          child: const Text(
                            "Change Password",
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x1A000000)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Preferences",
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Color(0x50000000)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 1,
                      color: const Color(0x1A000000),
                    ),
                    const SizedBox(height: 5),
                    // TOUR: tourTarget(key: _tourRemindersKey, ...) removed
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Attendance Reminders"),
                          Transform.scale(
                            scale: 0.8,
                            child: Switch(
                              value: attendanceReminders,
                              activeThumbColor: const Color(0xFF1565C0),
                              activeTrackColor: const Color(0x331565C0),
                              inactiveThumbColor: Colors.grey.shade400,
                              inactiveTrackColor: Colors.grey.shade300,
                              splashRadius: 0,
                              trackOutlineColor:
                                  WidgetStateProperty.all(Colors.transparent),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (value) async {
                                setState(() => attendanceReminders = value);

                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setBool('reminders_enabled', value);

                                if (value) {
                                  _setupAttendanceReminder();
                                } else {
                                  log("Attendance reminders deactivated");
                                  await NotificationService.cancelAll();
                                }
                              },
                            ),
                          ),
                      ],
                    ), // Row — reminders
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                          icon: const Icon(Icons.help_outline_rounded,
                              color: Color(0xFF1565C0)),
                          label: const Text(
                            "Help Center",
                            style: TextStyle(
                              color: Color(0xFF1565C0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            side: const BorderSide(color: Color(0x1A000000)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const HelpCenterPage(
                                  initialIndex: 4,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEA324C),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _handleSignOut,
                    child: const Text(
                      "Sign Out",
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}