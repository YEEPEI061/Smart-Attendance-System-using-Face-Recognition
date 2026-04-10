import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'dart:developer';
import 'package:userinterface/faceenroll.dart';
import 'package:userinterface/providers/auth_provider.dart';
import 'package:camera/camera.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

// ignore: must_be_immutable
class EnrollmentPage extends StatefulWidget {
  List<String> imagePaths;

  final Map<String, dynamic>? studentData;
  final bool isEditMode;

  EnrollmentPage({
    super.key,
    required this.imagePaths,
    this.studentData,
    this.isEditMode = false,
  });

  @override
  State<EnrollmentPage> createState() => _EnrollmentPageState();
}

class _EnrollmentPageState extends State<EnrollmentPage> {
  String? selectedSubjectId;
  List<Map<String, dynamic>> subjects = [];
  List<Map<String, dynamic>> courses = [];
  String? selectedCourseId;
  int _currentImageIndex = 0;
  late List<String> imagePaths;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController idController = TextEditingController();
  final TextEditingController courseController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchCourses();

    imagePaths = List.from(widget.imagePaths);

    if (widget.isEditMode && widget.studentData != null) {
      nameController.text = widget.studentData!['name'] ?? '';
      idController.text = widget.studentData!['student_card_id'] ?? '';
      selectedCourseId = widget.studentData!['course_id']?.toString();
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    idController.dispose();
    courseController.dispose();
    super.dispose();
  }

  Future<void> fetchCourses() async {
    final baseUrl = dotenv.env['BASE_URL'] ?? '';
    final url = Uri.parse('$baseUrl/courses');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final loadedCourses = List<Map<String, dynamic>>.from(data);

        setState(() {
          courses = loadedCourses;
        });

        if (widget.isEditMode && widget.studentData != null) {
          final courseId = widget.studentData!['course_id']?.toString();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            final match = loadedCourses.any(
              (c) => c['id'].toString() == courseId,
            );

            if (match) {
              setState(() {
                selectedCourseId = courseId;
              });
            }
          });
        }
      }
    } catch (e) {
      log("Error fetching courses: $e");
    }
  }

  // ENROLL STUDENT FUNCTION
  Future<void> enrollStudent() async {
    if (nameController.text.isEmpty ||
        idController.text.isEmpty ||
        selectedCourseId == null) {
      _showAnimatedDialog(
        context: context,
        icon: Icons.error_outline_rounded,
        iconColor: Colors.red,
        title: "Validation Error",
        message: "Please fill in all required fields.",
        buttonText: "Close",
        onPressed: () => Navigator.of(context).pop(),
      );
      return;
    }

    try {
      _showLoadingDialog(context);

      final baseUrl = dotenv.env['BASE_URL'] ?? '';
      if (baseUrl.isEmpty) return;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.userId;

      var uri = Uri.parse('$baseUrl/enroll');
      var request = http.MultipartRequest("POST", uri);

      request.fields["name"] = nameController.text;
      request.fields["student_card_id"] = idController.text;
      request.fields["course_id"] = selectedCourseId ?? '';
      request.fields["primary_index"] = _currentImageIndex.toString();
      request.fields["user_id"] = userId.toString();

      if (imagePaths.isNotEmpty) {
        for (var imagePath in imagePaths) {
          final file = File(imagePath);
          log("Sending file: $imagePath, exists: ${file.existsSync()}, size: ${file.existsSync() ? file.lengthSync() : 0} bytes");

          if (file.existsSync()) {
            request.files.add(await http.MultipartFile.fromPath(
              "images", // must match backend getlist("images")
              imagePath,
              filename: path.basename(imagePath),
            ));
          }
        }
      }

      var response = await request.send();
      var responseBody = await http.Response.fromStream(response);

      if (mounted) _hideLoadingDialog(context);

      if (responseBody.statusCode == 201 || responseBody.statusCode == 200) {
        if (mounted) {
          _showAnimatedDialog(
            context: context,
            icon: Icons.check_circle_outline_rounded,
            iconColor: const Color(0xFF00B38A),
            title: "Enrollment Successful",
            message: "Student has been enrolled successfully.",
            buttonText: "Continue",
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const Enrollment()),
              );
            },
          );
        }
      } else {
        if (mounted) {
          _showAnimatedDialog(
            context: context,
            icon: Icons.error_outline_rounded,
            iconColor: Colors.red,
            title: "Enrollment Failed",
            message:
                "Error: ${responseBody.body.isNotEmpty ? responseBody.body : responseBody.statusCode}",
            buttonText: "Close",
            onPressed: () => Navigator.of(context).pop(),
          );
        }
      }
    } catch (e, stackTrace) {
      if (mounted) _hideLoadingDialog(context);
      log("Error enrolling student", error: e, stackTrace: stackTrace);
      if (mounted) {
        _showAnimatedDialog(
          context: context,
          icon: Icons.error_outline_rounded,
          iconColor: Colors.red,
          title: "Enrollment Failed",
          message: "An unexpected error occurred.",
          buttonText: "Close",
          onPressed: () => Navigator.of(context).pop(),
        );
      }
    }
  }

  Future<void> updateStudent() async {
    if (nameController.text.isEmpty ||
        idController.text.isEmpty ||
        selectedCourseId == null) {
      _showAnimatedDialog(
        context: context,
        icon: Icons.error_outline_rounded,
        iconColor: Colors.red,
        title: "Validation Error",
        message: "Please fill in all required fields.",
        buttonText: "Close",
        onPressed: () => Navigator.of(context).pop(),
      );
      return;
    }

    try {
      _showLoadingDialog(context);

      final baseUrl = dotenv.env['BASE_URL'] ?? '';
      final studentId = widget.studentData!['id'];

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.userId;

      var uri = Uri.parse('$baseUrl/update-student/$studentId');
      var request = http.MultipartRequest("PUT", uri);

      // 1️⃣ TEXT FIELDS
      request.fields["name"] = nameController.text;
      request.fields["student_card_id"] = idController.text;
      request.fields["course_id"] = selectedCourseId ?? '';
      request.fields["user_id"] = userId.toString();

      // 2️⃣ PRIMARY FACE INDEX
      request.fields["primary_index"] = _currentImageIndex.toString();

      // 3️⃣ IMAGES (IMPORTANT)
      for (var imagePath in imagePaths) {
        final file = File(imagePath);

        if (file.existsSync()) {
          request.files.add(
            await http.MultipartFile.fromPath(
              "images",
              imagePath,
              filename: path.basename(imagePath),
            ),
          );
        }
      }

      // 4️⃣ SEND REQUEST
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (mounted) _hideLoadingDialog(context);

      if (response.statusCode == 200) {
        _showAnimatedDialog(
          // ignore: use_build_context_synchronously
          context: context,
          icon: Icons.check_circle_outline,
          iconColor: const Color(0xFF00B38A),
          title: "Updated",
          message: "Student updated successfully",
          buttonText: "OK",
          onPressed: () {
            Navigator.of(context).pop(); // close dialog

            Future.delayed(const Duration(milliseconds: 100), () {
              // ignore: use_build_context_synchronously
              Navigator.of(context).pop(true); // go back to update list page
            });
          },
        );
      } else {
        _showAnimatedDialog(
          // ignore: use_build_context_synchronously
          context: context,
          icon: Icons.error_outline,
          iconColor: Colors.red,
          title: "Failed",
          message: response.body,
          buttonText: "Close",
          onPressed: () => Navigator.pop(context),
        );
      }
    } catch (e, stack) {
      if (mounted) _hideLoadingDialog(context);
      log("Update error: $e", stackTrace: stack);
    }
  }

  void _showAnimatedDialog({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 60, color: iconColor),
            const SizedBox(height: 16),
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: iconColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: onPressed,
                child: Text(buttonText),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _hideLoadingDialog(BuildContext context) {
    if (Navigator.canPop(context)) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          // Wrap Column to prevent overflow
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 0),
                // Profile Image Preview
                Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF1565C0),
                    ),
                    child: imagePaths.isEmpty
                        ? const Icon(Icons.person,
                            color: Colors.white, size: 100)
                        : Stack(
                            children: [
                              ClipOval(
                                child: PageView.builder(
                                  itemCount: imagePaths.length,
                                  onPageChanged: (index) {
                                    setState(() {
                                      _currentImageIndex = index;
                                    });
                                  },
                                  itemBuilder: (context, index) {
                                    final imagePath = imagePaths[index];

                                    if (imagePath.startsWith('http')) {
                                      return Image.network(
                                        imagePath,
                                        fit: BoxFit.cover,
                                      );
                                    } else {
                                      return Image.file(
                                        File(imagePath),
                                        fit: BoxFit.cover,
                                      );
                                    }
                                  },
                                ),
                              ),

                              // ⭐ ADD BUTTON (only edit mode)
                              if (widget.isEditMode)
                                Positioned(
                                  right: 20,
                                  bottom: 10,
                                  child: GestureDetector(
                                    onTap: () async {
                                      final cameras = await availableCameras();

                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ScannerScreen(
                                            cameras: cameras,
                                            isEditMode: true,
                                            studentId: widget.studentData!['id']
                                                .toString(),
                                          ),
                                        ),
                                      );

                                      if (result != null && result is Map) {
                                        if (result["mode"] == "add_face") {
                                          List<String> newImages =
                                              List<String>.from(
                                                  result["images"]);

                                          setState(() {
                                            imagePaths.insertAll(0, newImages);
                                          });
                                        }
                                      }
                                    },
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF1565C0),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black26,
                                            blurRadius: 8,
                                            offset: Offset(0, 2),
                                          )
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.add,
                                        size: 26,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                // 🔵 Swipe indicator dots
                if (imagePaths.length > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(imagePaths.length, (index) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentImageIndex == index ? 12 : 8,
                        height: _currentImageIndex == index ? 12 : 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentImageIndex == index
                              ? const Color(0xFF1565C0)
                              : Colors.grey,
                        ),
                      );
                    }),
                  ),

                const SizedBox(height: 20),
                // Student Details
                SizedBox(
                    height: 50,
                    child:
                        _buildTextField("Enter student name", nameController)),
                const SizedBox(height: 10),
                SizedBox(
                    height: 50,
                    child: _buildTextField("Enter student ID", idController)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton2<String>(
                            isExpanded: true,
                            hint: const Text("Select course"),
                            value: selectedCourseId,

                            items: courses.map((course) {
                              return DropdownMenuItem<String>(
                                value: course['id'].toString(),
                                child: Text(course['short_name'] ?? 'Unknown'),
                              );
                            }).toList(),

                            onChanged: (value) {
                              setState(() {
                                selectedCourseId = value;
                              });
                            },

                            // 🔥 EXACT MATCH WIDTH
                            dropdownStyleData: DropdownStyleData(
                              maxHeight: 200,
                              width: constraints
                                  .maxWidth - 32, // 👈 THIS fixes it perfectly
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),

                            menuItemStyleData: const MenuItemStyleData(
                              height: 45,
                            ),

                            buttonStyleData: const ButtonStyleData(
                              height: 50,
                              padding: EdgeInsets.symmetric(horizontal: 0),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 15),
                // Dropdown (Subjects) HIDDEN!
                Visibility(
                  visible: false,
                  child: SizedBox(
                    height: 50,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F6F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          hint: const Text("Select subject..",
                              style: TextStyle(color: Colors.grey)),
                          value: selectedSubjectId,
                          items: subjects.map((subject) {
                            return DropdownMenuItem<String>(
                              value: subject['id'].toString(),
                              child: Text(subject['name']),
                            );
                          }).toList(),
                          onChanged: (value) =>
                              setState(() => selectedSubjectId = value),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: Colors.grey),
                          isExpanded: true,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
      // BottomNavigationBar with Enroll button
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 8, 15, 12),
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: widget.isEditMode ? updateStudent : enrollStudent,
              child: Text(
                widget.isEditMode ? "Update Student" : "Enroll",
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String hint, TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
