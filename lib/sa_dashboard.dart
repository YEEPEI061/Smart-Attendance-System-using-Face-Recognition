import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:userinterface/providers/auth_provider.dart';

class SuperAdminDashboardApp extends StatelessWidget {
  const SuperAdminDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SA - Dashboard',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: false,
      ),
      home: const AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: Colors.white,
          systemNavigationBarContrastEnforced: true,
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
        ),
        child: SuperAdminDashboardPage(),
      ),
    );
  }
}

class SuperAdminDashboardPage extends StatefulWidget {
  const SuperAdminDashboardPage({super.key});

  @override
  State<SuperAdminDashboardPage> createState() =>
      _SuperAdminDashboardPageState();
}

class _SuperAdminDashboardPageState extends State<SuperAdminDashboardPage> {
  int _totalUsers = 0;
  double _growthPercent = 0.0;
  bool _isStatsLoading = true;
  int _totalAdmins = 0;
  double _adminGrowthPercent = 0.0;
  bool _isAdminStatsLoading = true;
  int _totalStudents = 0;
  double _studentGrowthPercent = 0.0;
  bool _isStudentStatsLoading = true;
  String _username = "";
  String _email = "";
  bool _isUserLoading = true;
  File? _selectedImage;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  // Consolidated data loading
  Future<void> _loadAllData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final userId = authProvider.userId;

    // Use await to ensure the RefreshIndicator knows when done
    await Future.wait([
      _fetchUserStats(),
      _fetchAdminStats(),
      _fetchStudentStats(),
    ]);

    if (userId != null) {
        _fetchUserProfile(userId);
      }
}

  Future<void> _fetchUserProfile(int userId) async {
    try {
      final baseUrl = dotenv.env['BASE_URL']!;
      final response = await http.get(Uri.parse('$baseUrl/sa/user/$userId'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _username = data['username'] ?? "Unknown";
          _email = data['email'] ?? "Unknown";

          if (data['image_url'] != null &&
              data['image_url'].toString().isNotEmpty) {
            String rawUrl = data['image_url'];
            String absoluteUrl =
                rawUrl.startsWith('http') ? rawUrl : '$baseUrl/$rawUrl';

            _profileImageUrl =
                "$absoluteUrl?t=${DateTime.now().millisecondsSinceEpoch}";
          } else {
            _profileImageUrl = null;
          }

          _isUserLoading = false;
          _selectedImage = null;
        });
      }
    } catch (e) {
      log("Error fetching user profile: $e");
      setState(() => _isUserLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      File imageFile = File(pickedFile.path);
      // We don't set _selectedImage here to avoid "flicker"
      // if the upload fails. We upload first.
      await _uploadPhoto(imageFile);
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
        final resBody = await response.stream.bytesToString();
        final data = jsonDecode(resBody);

        // Success: Clear temporary file and refresh profile from server
        setState(() {
          _selectedImage = null;
        });
        await _fetchUserProfile(userId!);

        log("Photo uploaded and profile refreshed");
      }
    } catch (e) {
      log("Upload error: $e");
    }
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

  Future<void> _fetchUserStats() async {
    try {
      final baseUrl = dotenv.env['BASE_URL']!;
      final response = await http.get(Uri.parse('$baseUrl/sa/stats/users'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          _totalUsers = data['total_users'];
          _growthPercent = (data['growth_percentage'] as num).toDouble();
          _isStatsLoading = false;
        });
      } else {
        throw Exception("Failed to load user stats");
      }
    } catch (e) {
      log("Error fetching user stats: $e");
      setState(() => _isStatsLoading = false);
    }
  }

  Future<void> _fetchAdminStats() async {
    try {
      final baseUrl = dotenv.env['BASE_URL']!;
      final response = await http.get(Uri.parse('$baseUrl/sa/stats/admins'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          _totalAdmins = data['total_admins'];
          _adminGrowthPercent = (data['growth_percentage'] as num).toDouble();
          _isAdminStatsLoading = false;
        });
      } else {
        throw Exception("Failed to load admin stats");
      }
    } catch (e) {
      log("Error fetching admin stats: $e");
      setState(() => _isAdminStatsLoading = false);
    }
  }

  Future<void> _fetchStudentStats() async {
    try {
      final baseUrl = dotenv.env['BASE_URL']!;
      final response = await http.get(Uri.parse('$baseUrl/sa/stats/students'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _totalStudents = data['total'];
          _studentGrowthPercent = (data['growth_percent'] as num).toDouble();
          _isStudentStatsLoading = false;
        });
      } else {
        throw Exception("Failed to load stats");
      }
    } catch (e) {
      log("Error fetching student stats: $e");
      setState(() => _isStudentStatsLoading = false);
    }
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
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Are you sure you want to sign out?\nYou will need to login again.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFF6F6F6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text("Cancel"),
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
                          style: TextStyle(color: Colors.white),
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
        final response = await http.post(
          Uri.parse('$baseUrl/sa/logout'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"user_id": userId}),
        );

        if (response.statusCode == 200) {
          log("Logout logged successfully");
        }
      } catch (e) {
        log("Error logging logout: $e");
      }

      await authProvider.signOut();

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          "/sa/login",
          (route) => false,
        );
      }
    }
  }

// Profile Dialog
  Future<void> _showProfileDialog() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userId;
    setState(() => _isUserLoading = true);
    await _fetchUserProfile(userId!);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          insetPadding: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Account Settings",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0x80000000),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.black54, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(height: 1, color: const Color(0xFFF6F6F6)),
                const SizedBox(height: 15),

                // Avatar Upload Section
                Row(
                  children: [
                    StatefulBuilder(
                      builder: (context, setStateDialog) {
                        // Compute avatar image
                        ImageProvider<Object>? avatarImage;
                        if (_selectedImage != null) {
                          avatarImage = FileImage(_selectedImage!);
                        } else if (_profileImageUrl != null &&
                            _profileImageUrl!.isNotEmpty) {
                          avatarImage = NetworkImage(_profileImageUrl!);
                        }

                        return GestureDetector(
                          onTap: () async {
                            final picker = ImagePicker();
                            final pickedFile = await picker.pickImage(
                                source: ImageSource.gallery);

                            if (pickedFile != null) {
                              File imageFile = File(pickedFile.path);

                              // Update the dashboard state
                              setState(() => _selectedImage = imageFile);

                              // Update the dialog UI immediately
                              setStateDialog(() {});

                              // Upload to server
                              await _uploadPhoto(imageFile);

                              // Refresh the dialog avatar after upload
                              setStateDialog(() {});
                            }
                          },
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0x1A000000),
                            backgroundImage: avatarImage,
                            child: avatarImage == null
                                ? const Icon(
                                    Icons.person_rounded,
                                    size: 30,
                                    color: Color(0xB3000000),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: _showPhotoOptions,
                          child: const Text(
                            "Update Photo",
                            style: TextStyle(
                              color: Color(0xFF1565C0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          "JPG or PNG, max 5MB",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                const Text(
                  "Username",
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 5),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F6F6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0x1A000000),
                      width: 1,
                    ),
                  ),
                  child: _isUserLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _username,
                          style: const TextStyle(color: Colors.black87),
                        ),
                ),

                const SizedBox(height: 10),
                const Text(
                  "Email",
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 5),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F6F6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0x1A000000),
                      width: 1,
                    ),
                  ),
                  child: _isUserLoading
                      ? const CircularProgressIndicator()
                      : Text(
                          _email,
                          style: const TextStyle(color: Colors.black87),
                        ),
                ),
                const SizedBox(height: 15),

                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      Navigator.pushNamed(context, '/sa/users/change-password');
                    },
                    child: const Text(
                      "Change Password",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Container(height: 1, color: const Color(0xFFF6F6F6)),
                const SizedBox(height: 15),

                SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEB3349),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _handleSignOut,
                      child: const Text(
                        "Sign Out",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ))
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _addNewAdmin(String name, String email, String password) async {
    try {
      final baseUrl = dotenv.env['BASE_URL']!;
      final url = Uri.parse('$baseUrl/sa/add');

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.userId;

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': name,
          'email': email,
          'password': password,
          'role': 'superadmin',
          'user_id': userId,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print("Failed: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Error: $e");
      return false;
    }
  }

  // Add Admin Dialog
  void _showAddAdminDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController emailController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          insetPadding: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "New Admin",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0x80000000),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.black54, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(height: 1, color: const Color(0xFFF6F6F6)),
                const SizedBox(height: 15),

                // Name TextField
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    hintText: "Enter Name",
                    hintStyle: TextStyle(
                      color: Color(0x4D000000),
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF7F8FA),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Colors.transparent, width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Colors.transparent, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Colors.transparent, width: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Email TextField
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    hintText: "Enter Email",
                    hintStyle: TextStyle(
                      color: Color(0x4D000000),
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF7F8FA),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Colors.transparent, width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Colors.transparent, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Colors.transparent, width: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Password TextField
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: "Enter Password",
                    hintStyle: TextStyle(
                      color: Color(0x4D000000),
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF7F8FA),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Colors.transparent, width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Colors.transparent, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Colors.transparent, width: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () async {
                      final name = nameController.text.trim();
                      final email = emailController.text.trim();
                      final password = passwordController.text;

                      if (name.isEmpty || email.isEmpty || password.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("All fields are required.")),
                        );
                        return;
                      }

                      // Call backend API
                      final success = await _addNewAdmin(name, email, password);

                      if (success) {
                        Navigator.pop(context);

                        // Refresh data immediately!
                        _loadAllData();

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text("New Super Admin added successfully!")),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text("Failed to add new Super Admin.")),
                        );
                      }
                    },
                    child: const Text(
                      "Add",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatarImage =
        (_profileImageUrl != null && _profileImageUrl!.isNotEmpty)
            ? NetworkImage(_profileImageUrl!)
            : null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(10),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Profile Avatar
              Positioned(
                top: -10,
                right: 16,
                child: GestureDetector(
                  onTap: _showProfileDialog,
                  child: Builder(builder: (context) {
                    // Compute the avatar image safely
                    ImageProvider<Object>? avatarImage;

                    if (_selectedImage != null) {
                      avatarImage = FileImage(_selectedImage!);
                    } else if (_profileImageUrl != null &&
                        _profileImageUrl!.isNotEmpty) {
                      avatarImage = NetworkImage(_profileImageUrl!);
                    } else {
                      avatarImage = null;
                    }

                    return CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0x1A000000),
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? const Icon(
                              Icons.person_rounded,
                              size: 30,
                              color: Color(0xB3000000),
                            )
                          : null,
                    );
                  }),
                ),
              ),

              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          "Overview",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF000000),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ],
              ),

              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0x1A000000),
                ),
              ),
            ],
          ),
        ),
      ),
      // RefreshIndicator to enable pull-to-refresh
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        color: const Color(0xFF1565C0),
        child: SingleChildScrollView(
          // For pull-to-refresh to work on short lists
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0x1A1565C0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Total Users",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                            Text(
                              _isStatsLoading ? "—" : _totalUsers.toString(),
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            Row(
                              children: [
                                Icon(
                                  _growthPercent >= 0
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 14,
                                  color: _growthPercent >= 0
                                      ? const Color(0xFF00B38A)
                                      : Colors.red,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _isStatsLoading
                                      ? "-- %"
                                      : "${_growthPercent >= 0 ? "+" : ""}${_growthPercent.toStringAsFixed(1)} %",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _growthPercent >= 0
                                        ? const Color(0xFF00B38A)
                                        : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0x1A1565C0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Total Admins",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                            Text(
                              _isAdminStatsLoading
                                  ? "—"
                                  : _totalAdmins.toString(),
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            Row(
                              children: [
                                Icon(
                                  _adminGrowthPercent >= 0
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 14,
                                  color: _adminGrowthPercent >= 0
                                      ? const Color(0xFF00B38A)
                                      : Colors.red,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _isAdminStatsLoading
                                      ? "-- %"
                                      : "${_adminGrowthPercent >= 0 ? "+" : ""}${_adminGrowthPercent.toStringAsFixed(1)} %",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _adminGrowthPercent >= 0
                                        ? const Color(0xFF00B38A)
                                        : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(0xFF1565C0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "User Enrollment",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0x99FFFFFF),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _isStudentStatsLoading
                                      ? "—"
                                      : _totalStudents.toString(),
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0x80FFFFFF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _studentGrowthPercent >= 0
                                            ? Icons.arrow_upward_rounded
                                            : Icons.arrow_downward_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        _isStudentStatsLoading
                                            ? "-- %"
                                            : "${_studentGrowthPercent >= 0 ? "+" : ""}${_studentGrowthPercent.toStringAsFixed(1)} %",
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.normal,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Image.asset(
                        'assets/images/happy.png',
                        width: 35,
                        height: 35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Quick Access",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF000000),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  GestureDetector(
                    onTap: _showAddAdminDialog,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Color(0xFFF6F6F6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Color(0x1A000000),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person_add_alt_rounded,
                            size: 30,
                            color: Color(0xFF1565C0),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            "Add Admin",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1565C0),
                            ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF1565C0),
        unselectedItemColor: Colors.grey,
        currentIndex: 0,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        selectedIconTheme: const IconThemeData(size: 24),
        unselectedIconTheme: const IconThemeData(size: 24),
        onTap: (index) {
          if (index == 0) {
            Navigator.pushNamed(context, '/sa/dashboard');
          } else if (index == 1) {
            Navigator.pushNamed(context, '/sa/users');
          } else if (index == 2) {
            Navigator.pushNamed(context, '/sa/logs');
          } else if (index == 3) {
            Navigator.pushNamed(context, '/sa/settings');
          }
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.space_dashboard_rounded), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.people_rounded), label: 'Users'),
          BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded), label: 'Logs'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}
