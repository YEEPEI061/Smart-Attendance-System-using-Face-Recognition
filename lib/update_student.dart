import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:userinterface/faceenroll2.dart';
import 'package:cached_network_image/cached_network_image.dart';

class UpdateStudentPage extends StatefulWidget {
  const UpdateStudentPage({super.key});

  @override
  State<UpdateStudentPage> createState() => _UpdateStudentPageState();
}

class _UpdateStudentPageState extends State<UpdateStudentPage> {
  final TextEditingController _searchController = TextEditingController();

  String selectedCourse = "All";
  String selectedType = "All"; // All | Degree | Diploma

  bool isLoading = false;

  List<Map<String, dynamic>> studentList = [];

  Map<String, List<Map<String, dynamic>>> groupedStudents = {};

  @override
  void initState() {
    super.initState();
    initData();
  }

  Future<void> initData() async {
    await fetchCourses();
    await fetchStudents();
  }

  // 🔹 Group by course
  Map<String, List<Map<String, dynamic>>> groupByCourse(
      List<Map<String, dynamic>> students) {
    Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var student in students) {
      final course = student['course'] ?? 'Unknown';

      if (!grouped.containsKey(course)) {
        grouped[course] = [];
      }

      grouped[course]!.add(student);
    }

    return grouped;
  }

  Future<void> fetchStudents() async {
    setState(() => isLoading = true);

    final baseUrl = dotenv.env['BASE_URL'] ?? '';

    try {
      final uri = Uri.parse('$baseUrl/update/students');

      final response = await http.get(uri);
      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200 && decoded is List) {
        studentList = List<Map<String, dynamic>>.from(decoded);

        for (var s in studentList) {
          final courseId = s['course_id']?.toString();
          s['course_data'] = courseMap[courseId];
        }

        groupedStudents = groupByCourse(studentList);
      } else {
        print("API Error: $decoded");
      }
    } catch (e) {
      print("Error: $e");
    }

    setState(() => isLoading = false);
  }

  Map<String, dynamic> courseMap = {};

  Future<void> fetchCourses() async {
    final baseUrl = dotenv.env['BASE_URL'] ?? '';
    final response = await http.get(Uri.parse('$baseUrl/courses'));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      for (var course in data) {
        courseMap[course['id'].toString()] = course;
      }
    }
  }

  // 🔹 Search + regroup
  void _filterStudents(String value) {
    final q = value.toLowerCase();

    final filtered = studentList.where((student) {
      final name = (student['name'] ?? '').toLowerCase();
      final id = (student['student_card_id'] ?? '').toLowerCase();
      final course = (student['course'] ?? '').toLowerCase();

      return name.contains(q) || id.contains(q) || course.contains(q);
    }).toList();

    groupedStudents = groupByCourse(filtered);
    setState(() {});
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = studentList;

    // 1️⃣ filter by course
    if (selectedCourse != "All") {
      filtered = filtered.where((s) => s['course'] == selectedCourse).toList();
    }

    // 2️⃣ filter by degree/diploma
    if (selectedType != "All") {
      filtered = filtered.where((s) {
        final courseData = s['course_data'];

        if (courseData == null) return false;

        final shortName =
            (courseData['short_name'] ?? '').toString().toLowerCase();

        if (selectedType == "Degree") {
          return shortName.startsWith("b");
        } else if (selectedType == "Diploma") {
          return shortName.startsWith("d");
        }

        return true;
      }).toList();
    }

    setState(() {
      groupedStudents = groupByCourse(filtered);
    });
  }

  void _showFilterPopup(BuildContext iconContext) {
    final RenderBox renderBox = iconContext.findRenderObject() as RenderBox;

    final Offset offset = renderBox.localToGlobal(Offset.zero);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx - 120,
        offset.dy + renderBox.size.height,
        offset.dx + renderBox.size.width,
        0,
      ),
      color: const Color(0xE61565C0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 0,
      items: [
        PopupMenuItem(
          enabled: false,
          child: StatefulBuilder(
            builder: (context, menuSetState) {
              return SizedBox(
                width: 170,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Filter Students",
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    const Divider(color: Colors.white),

                    // 📚 COURSE FILTER
                    const Text(
                      "Course",
                      style: TextStyle(color: Colors.white70),
                    ),

                    _buildFilterItem(
                      "All Courses",
                      selectedCourse == "All",
                      () {
                        menuSetState(() {
                          selectedCourse = "All";
                          _applyFilters();
                        });
                      },
                    ),

                    ...studentList
                        .map((e) => e['course'])
                        .toSet()
                        .map((course) {
                      return _buildFilterItem(
                        course,
                        selectedCourse == course,
                        () {
                          menuSetState(() {
                            selectedCourse = course;
                            _applyFilters();
                          });
                        },
                      );
                    }).toList(),

                    const Divider(color: Colors.white),

                    // 🎓 TYPE FILTER
                    const Text(
                      "Type",
                      style: TextStyle(color: Colors.white70),
                    ),

                    _buildFilterItem(
                      "All",
                      selectedType == "All",
                      () {
                        menuSetState(() {
                          selectedType = "All";
                          _applyFilters();
                        });
                      },
                    ),

                    _buildFilterItem(
                      "Degree",
                      selectedType == "Degree",
                      () {
                        menuSetState(() {
                          selectedType = "Degree";
                          _applyFilters();
                        });
                      },
                    ),

                    _buildFilterItem(
                      "Diploma",
                      selectedType == "Diploma",
                      () {
                        menuSetState(() {
                          selectedType = "Diploma";
                          _applyFilters();
                        });
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDeleteStudentDialog(int studentId, String name) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔴 Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFEBEE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_rounded,
                  color: Color(0xFFEA324C),
                  size: 40,
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                "Delete Student",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 15,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: "Are you sure you want to delete\n"),
                    TextSpan(
                      text: name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const TextSpan(text: "?\nThis action cannot be undone."),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              Row(
                children: [
                  // ❌ Cancel
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Color(0xFFE0E0E0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // 🗑 Confirm Delete
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        deleteStudent(studentId);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEA324C),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        "Delete",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> deleteStudent(int studentId) async {
    final baseUrl = dotenv.env['BASE_URL'] ?? '';

    // 🔵 SHOW LOADING DIALOG
    showDialog(
      context: context,
      barrierDismissible: false, // ❌ cannot close
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/update/students/$studentId'),
      );

      // 🔴 CLOSE LOADING
      Navigator.pop(context);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Student deleted successfully")),
        );

        fetchStudents(); // 🔥 refresh list
      } else {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Delete failed: ${response.body}")),
        );
      }
    } catch (e) {
      // ignore: use_build_context_synchronously
      Navigator.pop(context);

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Something went wrong")),
      );
    }
  }

  void _showTipsPopup() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 💡 Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFE3F2FD),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
                  color: Color(0xFF1565C0),
                  size: 40,
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                "Tips",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                "• 👆 Tap a student to edit\n"
                "• 🗑 Long press a student to delete\n"
                "• 🔍 Use filter to narrow results",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: 28),

              // ✅ Close button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    "Got it",
                    style: TextStyle(
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

  Widget _buildFilterItem(String text, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Builder(
            builder: (iconContext) {
              return IconButton(
                icon: const Icon(Icons.info_outline, color: Color(0xFF9E9E9E)),
                onPressed: () => _showTipsPopup(),
              );
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),

                  // 🔍 SEARCH
                  TextField(
                    controller: _searchController,
                    onChanged: _filterStudents,
                    decoration: InputDecoration(
                      hintText: "Search student",
                      hintStyle: const TextStyle(color: Color(0xFF9E9E9E)),
                      suffixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0xFFF6F6F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 📚 GROUPED LIST
                  Expanded(
                    child: ListView(
                      children: (groupedStudents.entries.toList()
                            ..sort((a, b) =>
                                a.key.toString().compareTo(b.key.toString())))
                          .asMap()
                          .entries
                          .map((entry) {
                        final index = entry.key;
                        final course = entry.value.key;
                        final students = entry.value.value;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // COURSE HEADER + FILTER ICON
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    course,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (index == 0)
                                    Builder(
                                      builder: (iconContext) {
                                        return IconButton(
                                          icon: const Icon(
                                            Icons.filter_alt_rounded,
                                            color: Color(0xFF1565C0),
                                          ),
                                          onPressed: () =>
                                              _showFilterPopup(iconContext),
                                        );
                                      },
                                    )
                                  else
                                    const SizedBox(width: 48),
                                ],
                              ),
                            ),
                            // 👇 STUDENTS
                            ...students.map((student) {
                              return InkWell(
                                  onTap: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EnrollmentPage(
                                          imagePaths: (student['faces']
                                                      as List<dynamic>?)
                                                  ?.map((e) => e.toString())
                                                  .toList() ??
                                              [],
                                          isEditMode: true,
                                          studentData: student,
                                        ),
                                      ),
                                    );

                                    // Refresh after returning
                                    if (result == true) {
                                      fetchStudents();
                                    }
                                  },
                                  onLongPress: () {
                                    _showDeleteStudentDialog(
                                      student['id'],
                                      student['name'] ?? '',
                                    );
                                  },
                                  child: Container(
                                    height: 78,
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF7F8FA),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    child: Row(
                                      children: [
                                        // 👤 IMAGE
                                        CircleAvatar(
                                          radius: 25,
                                          backgroundColor:
                                              const Color(0xFF9E9E9E),
                                          child: ClipOval(
                                            child: (student['face_image_url'] !=
                                                        null &&
                                                    student['face_image_url']
                                                        .toString()
                                                        .isNotEmpty)
                                                ? CachedNetworkImage(
                                                    imageUrl: student[
                                                        'face_image_url'],
                                                    width: 50,
                                                    height: 50,
                                                    fit: BoxFit.cover,
                                                    placeholder: (context,
                                                            url) =>
                                                        const CircularProgressIndicator(
                                                            strokeWidth: 2),
                                                    errorWidget: (context, url,
                                                            error) =>
                                                        const Icon(Icons.person,
                                                            color:
                                                                Colors.white),
                                                  )
                                                : const Icon(Icons.person,
                                                    color: Colors.white),
                                          ),
                                        ),
                                        const SizedBox(width: 12),

                                        // 📝 INFO
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                student['name'] ?? '',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              Text(
                                                student['student_card_id'] ??
                                                    '--',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        const Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          size: 16,
                                          color: Colors.grey,
                                        ),
                                      ],
                                    ),
                                  ));
                            }).toList(),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
