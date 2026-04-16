import 'dart:convert';
import 'dart:developer';
import 'dart:async'; // provides Completer
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:userinterface/attendance.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:userinterface/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:userinterface/services/notification_service.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:userinterface/help/app_tour.dart';

class FileItem {
  int id;
  String name;
  DateTime date;

  FileItem(this.id, this.name, this.date);
}

class Folder {
  int? id;
  String name;
  DateTime date;
  String? imageUrl;
  List<FileItem> files;
  bool isExpanded;

  Folder(this.name, this.date,
      {this.id, this.imageUrl, this.files = const [], this.isExpanded = false});
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Tour keys
  final GlobalKey _tourSearchKey = GlobalKey();
  final GlobalKey _tourAddGroupKey = GlobalKey();
  final GlobalKey _tourOpenGroupKey = GlobalKey();
  final GlobalKey _tourPersonIconKey = GlobalKey();
  final GlobalKey _tourEditKey = GlobalKey();
  final GlobalKey _tourDeleteKey = GlobalKey();
  final GlobalKey _tourAddScheduleKey = GlobalKey();

  // Completer that signals when the initial folder fetch is done.
  // tourWrapper awaits this so the tour only starts once targets are visible.
  final Completer<void> _dataLoaded = Completer<void>();

  List<Folder> folders = [];
  List<Folder> filteredFolders = [];
  bool isLoading = true;
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedFile;
  List<Map<String, dynamic>> students = [];
  Set<int> selectedStudentIds = {};
  bool isLoadingStudents = false;

  final TextEditingController groupSearchController = TextEditingController();

  static const Map<int, String> _weekdayLabel = {
    DateTime.monday: "Mon",
    DateTime.tuesday: "Tue",
    DateTime.wednesday: "Wed",
    DateTime.thursday: "Thu",
    DateTime.friday: "Fri",
    DateTime.saturday: "Sat",
    DateTime.sunday: "Sun",
  };

  @override
  void initState() {
    super.initState();
    NotificationService.init(); // Initialize notifications
    fetchFolders();
    _syncRemindersInBackground(); // Start auto-sync on app open
  }

  Future<void> _syncRemindersInBackground() async {
    final prefs = await SharedPreferences.getInstance();
    bool isEnabled = prefs.getBool('reminders_enabled') ?? true;

    if (isEnabled) {
      log("DASHBOARD: Proactive sync started...");
      await _setupAttendanceReminder();
    }
  }

  Future<void> _setupAttendanceReminder() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userId;
    final baseUrl = dotenv.env['BASE_URL']!;

    try {
      final response =
          await http.get(Uri.parse('$baseUrl/lecturer/$userId/schedule'));

      if (response.statusCode == 200) {
        List classes = jsonDecode(response.body);
        await NotificationService.cancelAll(); // Refresh all timers

        final now = DateTime.now();
        const weeksToScheduleAhead = 8;

        for (var cls in classes) {
          final classId = cls['id'] as int;
          final className = (cls['course_name'] ?? 'Class').toString();
          final scheduleStr = (cls['start_time'] ?? '').toString();
          final spec = _parseScheduleSpec(scheduleStr);
          if (spec == null) continue;

          // If today is a class day and we're currently within the class window,
          // show an instant reminder (ONLY if attendance not yet taken today).
          final isTodaySelected = spec.weekdays.contains(now.weekday);
          if (isTodaySelected && _isNowWithinWindow(now, spec.start, spec.end)) {
            final taken = await _isAttendanceTakenToday(baseUrl, classId);
            if (!taken) {
              await NotificationService.showInstantNotification(
                "Class In Progress",
                'Your class "$className" is ongoing. Take attendance now.',
              );
            }
          }

          for (final weekday in spec.weekdays) {
            DateTime nextStart = _nextWeekdayTime(
              from: now,
              weekday: weekday,
              time: spec.start,
            );

            for (int i = 0; i < weeksToScheduleAhead; i++) {
              final sessionDate = nextStart.add(Duration(days: 7 * i));
              final sessionEnd = DateTime(
                sessionDate.year,
                sessionDate.month,
                sessionDate.day,
                spec.end.hour,
                spec.end.minute,
              );

              // START notification
              if (sessionDate.isAfter(now)) {
                final startId = NotificationService.buildSessionNotificationId(
                  classId: classId,
                  sessionDate: sessionDate,
                  type: 1,
                );
                await NotificationService.scheduleAttendanceStart(
                  notificationId: startId,
                  className: className,
                  scheduledTime: sessionDate,
                );
              }

              // PRE-END notification (10 minutes before end)
              final preEndTime = sessionEnd.subtract(const Duration(minutes: 10));
              if (preEndTime.isAfter(now)) {
                final preEndId = NotificationService.buildSessionNotificationId(
                  classId: classId,
                  sessionDate: sessionDate,
                  type: 2,
                );
                await NotificationService.scheduleAttendancePreEnd(
                  notificationId: preEndId,
                  className: className,
                  scheduledTime: preEndTime,
                );
              }
            }
          }
        }
        log("DASHBOARD: Sync complete.");
      }
    } catch (e) {
      log("DASHBOARD: Sync error -> $e");
    }
  }

  Future<bool> _isAttendanceTakenToday(String baseUrl, int classId) async {
    try {
      final resp =
          await http.get(Uri.parse('$baseUrl/attendance/taken?class_id=$classId'));
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['taken'] == true);
    } catch (_) {
      return false;
    }
  }

  bool _isNowWithinWindow(DateTime now, TimeOfDay start, TimeOfDay end) {
    final startDt = DateTime(now.year, now.month, now.day, start.hour, start.minute);
    final endDt = DateTime(now.year, now.month, now.day, end.hour, end.minute);
    return now.isAfter(startDt) && now.isBefore(endDt);
  }

  DateTime _nextWeekdayTime({
    required DateTime from,
    required int weekday,
    required TimeOfDay time,
  }) {
    // Weekday uses DateTime weekday (Mon=1..Sun=7).
    final today = DateTime(from.year, from.month, from.day, time.hour, time.minute);
    int deltaDays = (weekday - from.weekday) % 7;
    DateTime candidate = today.add(Duration(days: deltaDays));
    if (!candidate.isAfter(from)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  _ScheduleSpec? _parseScheduleSpec(String scheduleStr) {
    try {
      final raw = scheduleStr.trim();
      String daysPart = "";
      String timePart = raw;

      if (raw.contains("|")) {
        final parts = raw.split("|");
        daysPart = parts[0].trim();
        timePart = parts.sublist(1).join("|").trim();
      }

      final rangeParts = timePart.split("-");
      if (rangeParts.length < 2) return null;

      final startStr = rangeParts[0].trim();
      final endStr = rangeParts.sublist(1).join("-").trim();

      final start = _parseTimeOfDay(startStr);
      final end = _parseTimeOfDay(endStr);
      if (start == null || end == null) return null;

      final weekdays = <int>{};
      if (daysPart.isNotEmpty) {
        final tokens = daysPart
            .split(",")
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        for (final t in tokens) {
          final w = _weekdayFromLabel(t);
          if (w != null) weekdays.add(w);
        }
      }

      // Backward compatibility: if no days were saved, assume "today".
      if (weekdays.isEmpty) {
        weekdays.add(DateTime.now().weekday);
      }

      return _ScheduleSpec(weekdays: weekdays.toList(), start: start, end: end);
    } catch (_) {
      return null;
    }
  }

  int? _weekdayFromLabel(String label) {
    final normalized = label.toLowerCase();
    for (final entry in _weekdayLabel.entries) {
      if (entry.value.toLowerCase() == normalized) return entry.key;
    }
    // Accept full names too
    switch (normalized) {
      case "monday":
        return DateTime.monday;
      case "tuesday":
        return DateTime.tuesday;
      case "wednesday":
        return DateTime.wednesday;
      case "thursday":
        return DateTime.thursday;
      case "friday":
        return DateTime.friday;
      case "saturday":
        return DateTime.saturday;
      case "sunday":
        return DateTime.sunday;
    }
    return null;
  }

  TimeOfDay? _parseTimeOfDay(String s) {
    // Handles "08:30 AM" (preferred) and "08:30" (fallback).
    final v = s.trim();
    try {
    if (v.toLowerCase().contains("am") || v.toLowerCase().contains("pm")) {
        final dt = DateFormat('hh:mm a').parse(v);
        return TimeOfDay(hour: dt.hour, minute: dt.minute);
      }
      final parts = v.split(":");
      if (parts.length >= 2) {
        return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    } catch (_) {}
    return null;
  }

  void _filterGroups(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredFolders = folders;
      } else {
        filteredFolders = folders
            .where((folder) =>
                folder.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _confirmEnrollStudents({
    required List<int> studentIds,
    required int folderId,
  }) async {
    final baseUrl = dotenv.env['BASE_URL']!;
    await http.post(
      Uri.parse('$baseUrl/enrollment/bulk'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'student_ids': studentIds,
        'folder_id': folderId,
      }),
    );
  }

  void _showEnrollStudentDialog(int subjectId) {
    List<int> selectedStudentIds = [];
    bool isLoadingStudents = false;
    List<Map<String, dynamic>> students = [];
    final TextEditingController searchController = TextEditingController();
    Timer? debounce; // For debounce

    // Fetch students from backend
    Future<void> fetchStudents(
        String keyword, StateSetter setDialogState) async {
      setDialogState(() => isLoadingStudents = true);

      try {
        final baseUrl = dotenv.env['BASE_URL']!;

        final response = await http.get(
          Uri.parse('$baseUrl/students?search=$keyword&subject_id=$subjectId'),
        );

        if (response.statusCode == 200) {
          final data =
              List<Map<String, dynamic>>.from(jsonDecode(response.body));

          setDialogState(() {
            students = data;

            // Pre-select already enrolled students
            selectedStudentIds = data
                .where((s) => s['enrolled'] == true)
                .map<int>((s) => s['id'] as int)
                .toList();

            isLoadingStudents = false;
          });
        } else {
          setDialogState(() => isLoadingStudents = false);
        }
      } catch (e) {
        setDialogState(() => isLoadingStudents = false);
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Initial fetch
            if (students.isEmpty && !isLoadingStudents) {
              Future.microtask(() => fetchStudents("", setDialogState));
            }

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              insetPadding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.7,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Enroll Students",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0x80000000)),
                          ),
                          GestureDetector(
                            onTap: () {
                              if (debounce?.isActive ?? false)
                                debounce!.cancel();
                              Navigator.pop(context);
                            },
                            child: const Icon(Icons.close_rounded,
                                color: Colors.black54, size: 24),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(height: 1, color: Color(0xFFF6F6F6)),
                      const SizedBox(height: 15),

                      // Search field
                      TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: "Search by name or student ID",
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.search,
                                color: Color(0xFF1565C0)),
                            onPressed: () {
                              fetchStudents(
                                  searchController.text, setDialogState);
                            },
                          ),
                        ),
                        onChanged: (value) {
                          // Debounce API calls
                          if (debounce?.isActive ?? false) debounce!.cancel();
                          debounce =
                              Timer(const Duration(milliseconds: 500), () {
                            fetchStudents(value, setDialogState);
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      // Select All
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () async {
                            final isAllSelected = students.isNotEmpty &&
                                selectedStudentIds.length == students.length;

                            setDialogState(() {
                              if (isAllSelected) {
                                // Unselect all
                                selectedStudentIds.clear();
                              } else {
                                // Select all
                                selectedStudentIds.clear();
                                for (var student in students) {
                                  selectedStudentIds.add(student['id'] as int);
                                }
                              }
                            });

                            if (isAllSelected) {
                              final baseUrl = dotenv.env['BASE_URL']!;
                              for (var student in students) {
                                try {
                                  await http.post(
                                    Uri.parse('$baseUrl/remove_student'),
                                    headers: {
                                      'Content-Type': 'application/json',
                                    },
                                    body: jsonEncode({
                                      'student_id': student['id'],
                                      'subject_id': subjectId,
                                    }),
                                  );
                                } catch (e) {
                                  print("Error removing student: $e");
                                }
                              }
                            }
                          },
                          child: Text(
                            students.isNotEmpty &&
                                    selectedStudentIds.length == students.length
                                ? "Unselect All"
                                : "Select All",
                            style: const TextStyle(
                              color: Color(0xFF1565C0),
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Student list
                      Expanded(
                        child: isLoadingStudents
                            ? const Center(child: CircularProgressIndicator())
                            : students.isEmpty
                                ? const Center(child: Text("No students found"))
                                : ListView.builder(
                                    padding: const EdgeInsets.only(bottom: 60),
                                    itemCount: students.length,
                                    itemBuilder: (context, index) {
                                      final student = students[index];
                                      final studentId = student['id'] as int;
                                      final isSelected = selectedStudentIds
                                          .contains(studentId);

                                      return Container(
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        height: 78,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF7F8FA),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            // Avatar
                                            CircleAvatar(
                                              radius: 25,
                                              backgroundColor:
                                                  const Color(0xFF9E9E9E),
                                              backgroundImage: student[
                                                              'face_image_url'] !=
                                                          null &&
                                                      student['face_image_url']
                                                          .toString()
                                                          .isNotEmpty
                                                  ? NetworkImage(
                                                      student['face_image_url']
                                                          .toString())
                                                  : null,
                                              child: (student['face_image_url'] ==
                                                          null ||
                                                      student['face_image_url']
                                                          .toString()
                                                          .isEmpty)
                                                  ? const Icon(Icons.person,
                                                      color: Colors.white)
                                                  : null,
                                            ),
                                            const SizedBox(width: 12),

                                            // Name, ID, course
                                            Expanded(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    student['name'] ?? '--',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 15),
                                                  ),
                                                  Text(
                                                    student['student_card_id']
                                                            ?.toString() ??
                                                        '--',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w300,
                                                        fontSize: 12,
                                                        color: Colors.grey),
                                                  ),
                                                  Text(
                                                    student['course']
                                                            ?.toString() ??
                                                        '--',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w300,
                                                        fontSize: 12,
                                                        color: Colors.grey),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Checkbox
                                            Checkbox(
                                              value: isSelected,
                                              onChanged: (val) async {
                                                setDialogState(() {
                                                  if (val == true) {
                                                    selectedStudentIds
                                                        .add(studentId);
                                                  } else {
                                                    selectedStudentIds
                                                        .remove(studentId);
                                                  }
                                                });

                                                // If unticked, remove from backend
                                                if (val == false) {
                                                  final baseUrl =
                                                      dotenv.env['BASE_URL']!;
                                                  try {
                                                    final response =
                                                        await http.post(
                                                      Uri.parse(
                                                          '$baseUrl/remove_student'),
                                                      headers: {
                                                        'Content-Type':
                                                            'application/json'
                                                      },
                                                      body: jsonEncode({
                                                        'student_id': studentId,
                                                        'subject_id': subjectId,
                                                      }),
                                                    );
                                                    if (response.statusCode !=
                                                        200) {
                                                      print(
                                                          "Failed to remove student: ${response.body}");
                                                    }
                                                  } catch (e) {
                                                    print(
                                                        "Error removing student: $e");
                                                  }
                                                }
                                              },
                                              checkColor: Colors.white,
                                              fillColor: WidgetStateProperty
                                                  .resolveWith<Color?>(
                                                      (states) {
                                                if (states.contains(
                                                    WidgetState.selected)) {
                                                  return const Color(
                                                      0xFF1565C0);
                                                }
                                                return null;
                                              }),
                                            )
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                      ),

                      const SizedBox(height: 15),

                      // Confirm button
                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: selectedStudentIds.isEmpty
                              ? null
                              : () async {
                                  await _confirmEnrollStudents(
                                    studentIds: selectedStudentIds,
                                    folderId: subjectId,
                                  );
                                  if (mounted) {
                                    if (debounce?.isActive ?? false)
                                      debounce!.cancel();
                                    // ignore: use_build_context_synchronously
                                    Navigator.pop(context);
                                    // ignore: use_build_context_synchronously
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            "Students enrolled successfully"),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                          child: const Text(
                            "Confirm",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> fetchFolders() async {
    final baseUrl = dotenv.env['BASE_URL']!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userId;
    final url = Uri.parse('$baseUrl/subjects?user_id=$userId');
    final dateFormat = DateFormat('dd/MM/yyyy');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          folders = data
              .map((item) => Folder(
                    item['name'],
                    item['created_at'] != null
                        ? dateFormat.parse(item['created_at'])
                        : DateTime.now(),
                    id: item['id'],
                    imageUrl: item['image_url'] != null &&
                            item['image_url'].toString().isNotEmpty
                        ? "$baseUrl/${item['image_url']}"
                        : null,
                  ))
              .toList();
          filteredFolders = folders;
          isLoading = false;
        });
        if (!_dataLoaded.isCompleted) _dataLoaded.complete();
        log('Successfully fetched subjects: ${folders.length} items');
      } else {
        log('Error fetching subjects: ${response.statusCode}');
        setState(() => isLoading = false);
        if (!_dataLoaded.isCompleted) _dataLoaded.complete();
      }
    } catch (e, stackTrace) {
      log('Error fetching subjects', error: e, stackTrace: stackTrace);
      setState(() => isLoading = false);
      if (!_dataLoaded.isCompleted) _dataLoaded.complete();
    }
  }

  Future<void> fetchFiles(Folder folder) async {
    final baseUrl = dotenv.env['BASE_URL']!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userId;
    final url =
        Uri.parse('$baseUrl/subjects/${folder.id}/files?user_id=$userId');
    final dateFormat = DateFormat('dd/MM/yyyy');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          folder.files = data
              .map((item) => FileItem(
                    item['id'],
                    item['schedule'] ?? 'No Name',
                    item['created_at'] != null
                        ? dateFormat.parse(item['created_at'])
                        : DateTime.now(),
                  ))
              .toList();
        });
        log('Fetched ${folder.files.length} files for ${folder.name}');
      } else {
        log('Error fetching files: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      log('Error fetching files', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _pickImage(StateSetter setDialogState) async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image != null) {
      setDialogState(() {
        _pickedFile = image;
      });
    }
  }

  Future<bool> createFolder(String name, XFile? imageFile) async {
    final baseUrl = dotenv.env['BASE_URL']!;
    final url = Uri.parse('$baseUrl/subjects');

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userId; // get userId from provider

    if (userId == null) {
      log("User not logged in, cannot create folder");
      return false;
    }

    try {
      var request = http.MultipartRequest('POST', url);
      request.fields['name'] = name;
      request.fields['user_id'] = userId.toString();

      if (imageFile != null) {
        request.files
            .add(await http.MultipartFile.fromPath('image', imageFile.path));
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        log('Folder created successfully');
        fetchFolders();
        return true;
      } else {
        log('Failed to create folder: ${response.body}');
        try {
          final body = jsonDecode(response.body);
          final msg = body is Map && body['message'] != null
              ? body['message'].toString()
              : 'Failed to create folder';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
            );
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to create folder'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        return false;
      }
    } catch (e) {
      log('Error creating folder', error: e);
      return false;
    }
  }

  Future<bool> updateFolder(int id, String name, XFile? imageFile) async {
    final baseUrl = dotenv.env['BASE_URL']!;
    final url = Uri.parse('$baseUrl/subjects/$id');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userId;

    if (userId == null) return false;

    try {
      var request = http.MultipartRequest('PUT', url);
      request.fields['name'] = name;
      request.fields['user_id'] = userId.toString();

      if (imageFile != null) {
        request.files
            .add(await http.MultipartFile.fromPath('image', imageFile.path));
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        log('Folder updated successfully');
        fetchFolders();
        return true;
      } else {
        log('Failed to update folder: ${response.body}');
        try {
          final body = jsonDecode(response.body);
          final msg = body is Map && body['message'] != null
              ? body['message'].toString()
              : 'Failed to update folder';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
            );
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to update folder'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        return false;
      }
    } catch (e) {
      log('Error updating folder', error: e);
      return false;
    }
  }

  Future<void> deleteFolder(int id) async {
    final baseUrl = dotenv.env['BASE_URL']!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userId;

    // Pass userId as query parameter
    final url = Uri.parse('$baseUrl/subjects/$id?user_id=$userId');

    try {
      final response = await http.delete(url);

      if (response.statusCode == 200) {
        log('Folder deleted successfully');
        fetchFolders();
      } else {
        log('Failed to delete folder: ${response.body}');
      }
    } catch (e) {
      log('Error deleting folder', error: e);
    }
  }

  Future<bool> createFile(int folderId, String name) async {
    final baseUrl = dotenv.env['BASE_URL']!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userId;

    ////// Pass userId as query parameter
    if (userId == null) return false;

    final url = Uri.parse('$baseUrl/subjects/$folderId/files?user_id=$userId');

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"name": name}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        log('File created successfully');
        final folderIndex = folders.indexWhere((f) => f.id == folderId);
        if (folderIndex != -1) fetchFiles(folders[folderIndex]);
        _syncRemindersInBackground();
        return true;
      } else {
        log('Failed to create file: ${response.body}');
        try {
          final body = jsonDecode(response.body);
          final msg = body is Map && body['message'] != null
              ? body['message'].toString()
              : 'Failed to create schedule';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
            );
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to create schedule'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        return false;
      }
    } catch (e) {
      log('Error creating file', error: e);
      return false;
    }
  }

  Future<bool> updateFile(Folder folder, int fileId, String name) async {
    final baseUrl = dotenv.env['BASE_URL']!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userId;

    ///// Pass userId as query parameter
    if (userId == null) return false;

    final url = Uri.parse('$baseUrl/classes/$fileId?user_id=$userId');

    try {
      final response = await http.put(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"name": name}),
      );

      if (response.statusCode == 200) {
        log('File updated successfully');
        fetchFiles(folder);
        return true;
      } else {
        log('Failed to update file: ${response.body}');
        try {
          final body = jsonDecode(response.body);
          final msg = body is Map && body['message'] != null
              ? body['message'].toString()
              : 'Failed to update schedule';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
            );
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to update schedule'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        return false;
      }
    } catch (e) {
      log('Error updating file', error: e);
      return false;
    }
  }

  Future<void> deleteFile(Folder folder, int fileId) async {
    final baseUrl = dotenv.env['BASE_URL']!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.userId;

    // Pass userId as query parameter
    final url = Uri.parse('$baseUrl/classes/$fileId?user_id=$userId');

    try {
      final response = await http.delete(url);

      if (response.statusCode == 200) {
        log('File deleted successfully');
        fetchFiles(folder);
        _syncRemindersInBackground();
      } else {
        log('Failed to delete file: ${response.body}');
      }
    } catch (e) {
      log('Error deleting file', error: e);
    }
  }

  void _showFolderDialog({Folder? folder, bool isEdit = false}) {
    final TextEditingController nameController =
        TextEditingController(text: folder?.name ?? '');
    _pickedFile = null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          // Added StatefulBuilder to update image preview inside dialog
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              insetPadding: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEdit ? "Edit Group" : "New Group",
                          style: const TextStyle(
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
                    GestureDetector(
                      onTap: () => _pickImage(setDialogState), // Trigger picker
                      child: Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F8FA),
                              borderRadius: BorderRadius.circular(8),
                              image: _pickedFile != null
                                  ? DecorationImage(
                                      image: FileImage(File(_pickedFile!.path)),
                                      fit: BoxFit.cover,
                                    )
                                  : (isEdit &&
                                          folder?.imageUrl != null &&
                                          folder!.imageUrl!.isNotEmpty)
                                      ? DecorationImage(
                                          image: NetworkImage(folder.imageUrl!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                            ),
                            child: (_pickedFile == null &&
                                    !(isEdit && folder?.imageUrl != null))
                                ? const Icon(Icons.image,
                                    size: 40, color: Colors.grey)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _pickedFile != null
                                    ? "Change Picture"
                                    : "Upload Picture",
                                style: const TextStyle(
                                    color: Color(0xFF1565C0),
                                    fontWeight: FontWeight.w600),
                              ),
                              const Text("JPG or PNG, max 5MB",
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        hintText: "Enter Group Name",
                        hintStyle:
                            const TextStyle(color: Colors.grey, fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFFF7F8FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
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
                          if (nameController.text.isNotEmpty) {
                            bool ok = false;
                            if (isEdit && folder != null && folder.id != null) {
                              ok = await updateFolder(folder.id!,
                                  nameController.text, _pickedFile);
                            } else {
                              ok = await createFolder(
                                  nameController.text, _pickedFile);
                            }
                            if (mounted && ok) Navigator.pop(context);
                          }
                        },
                        child: Text(isEdit ? "Confirm Changes" : "Create",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showFileDialog(Folder folder, {FileItem? file, bool isEdit = false}) {
    // Controllers for the time fields
    final TextEditingController startTimeController = TextEditingController();
    final TextEditingController endTimeController = TextEditingController();
    final Set<int> selectedWeekdays = {};

    // Prefill when editing
    if (isEdit && file != null) {
      final spec = _parseScheduleSpec(file.name);
      if (spec != null) {
        startTimeController.text = _formatTimeOfDay(spec.start);
        endTimeController.text = _formatTimeOfDay(spec.end);
        selectedWeekdays.addAll(spec.weekdays);
      }
    }

    // Helper function to pick time
    Future<void> _selectTime(TextEditingController controller) async {
      TimeOfDay? picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (BuildContext context, Widget? child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
            child: Theme(
              data: Theme.of(context).copyWith(
                useMaterial3: true,
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFF1565C0),
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: Colors.black,
                ),
                timePickerTheme: TimePickerThemeData(
                  // Header Style
                  helpTextStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),

                  // Keyboard Icon
                  entryModeIconColor: Colors.black,

                  // AM/PM Styles
                  dayPeriodBorderSide:
                      const BorderSide(color: Color(0xFFE0E0E0)),
                  dayPeriodColor: WidgetStateColor.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? const Color(0xFFE3F2FD) // Light Blue background
                          : Colors.white),
                  dayPeriodTextColor: WidgetStateColor.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? const Color(0xFF1565C0) // Selected text color
                          : Colors.black),

                  // Hour/Minute Styles
                  hourMinuteColor: WidgetStateColor.resolveWith((states) =>
                      states.contains(WidgetState.selected)
                          ? const Color(0xFFE3F2FD)
                          : const Color(0xFFEEEEEE)),
                  hourMinuteTextColor: WidgetStateColor.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? const Color(0xFF1565C0) // Selected text color
                          : Colors.black), // Unselected text color (Black)
                  hourMinuteTextStyle: const TextStyle(
                      fontSize: 50, fontWeight: FontWeight.w500),
                  hourMinuteShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),

                  // Dial Styles (The Clock)
                  dialBackgroundColor: const Color(0xFFF0F0F0),
                  dialHandColor: const Color(0xFF1565C0),
                  dialTextStyle: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w500),

                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
                ),
                // Only one textButtonTheme allowed
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    padding: const EdgeInsets.only(bottom: 5, top: 20),
                  ),
                ),
              ),

              // Using Transform.scale is the safest way to make the dial background bigger
              // without triggering "undefined parameter" errors.
              child: Center(
                child: Transform.scale(
                  scale: 1.0,
                  child: child!,
                ),
              ),
            ),
          );
        },
      );

      if (picked != null) {
        final now = DateTime.now();
        final dt =
            DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
        setState(() {
          controller.text =
              DateFormat('hh:mm a').format(dt);
        });
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          insetPadding: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEdit ? "Edit Schedule Time" : "New Schedule Time",
                      style: const TextStyle(
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
                Container(
                  height: 1,
                  color: const Color(0xFFF6F6F6),
                ),
                const SizedBox(height: 15),

                // Start Time Field
                _buildTimeField("Select Start Time", startTimeController,
                    () => _selectTime(startTimeController)),

                const SizedBox(height: 12),

                // End Time Field
                _buildTimeField("Select End Time", endTimeController,
                    () => _selectTime(endTimeController)),

          const SizedBox(height: 12),

                    const Text(
                      "Select Days",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0x80000000),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _weekdayLabel.entries.map((e) {
                        final selected = selectedWeekdays.contains(e.key);
                        return ChoiceChip(
                          label: Text(e.value),
                          selected: selected,
                          selectedColor: const Color(0xFFE3F2FD),
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                            color: selected ? const Color(0xFF1565C0) : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (val) {
                            setDialogState(() {
                              if (val) {
                                selectedWeekdays.add(e.key);
                              } else {
                                selectedWeekdays.remove(e.key);
                              }
                            });
                          },
                        );
                      }).toList(),
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
                          if (startTimeController.text.isEmpty ||
                              endTimeController.text.isEmpty ||
                              selectedWeekdays.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Please select start time, end time, and at least one day."),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }

                          final daysText = selectedWeekdays.toList()
                            ..sort();
                          final daysLabel = daysText.map((w) => _weekdayLabel[w]!).join(", ");
                          final combinedName =
                              "$daysLabel | ${startTimeController.text} - ${endTimeController.text}";

                          if (isEdit && file != null) {
                            await updateFile(folder, file.id, combinedName);
                          } else if (folder.id != null) {
                            await createFile(folder.id!, combinedName);
                          }
                          if (mounted) Navigator.pop(context);
                        },
                        child: Text(
                          isEdit ? "Save Changes" : "Create",
                          style: const TextStyle(
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
      },
    );
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  // Helper widget to maintain the UI style in your image
  Widget _buildTimeField(
      String hint, TextEditingController controller, VoidCallback onTap) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
        suffixIcon:
            const Icon(Icons.access_time_rounded, color: Color(0xFF1565C0)),
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  void _showDeleteDialog(dynamic item, {bool isFile = false, Folder? folder}) {
    showDialog(
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
                const Icon(Icons.delete_forever_rounded,
                    color: Color(0xFFF84F31), size: 48),
                const SizedBox(height: 12),
                const Text("Are you sure?",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  "Do you really want to delete this ${isFile ? 'schedule time' : 'group'}?\nThis process cannot be undone.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFF6F6F6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text("Cancel",
                            style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF84F31),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8))),
                        onPressed: () async {
                          if (isFile && folder != null) {
                            FileItem file = item as FileItem;
                            await deleteFile(folder, file.id);
                          } else {
                            Folder fold = item as Folder;
                            if (fold.id != null) {
                              await deleteFolder(fold.id!);
                            }
                          }
                          if (mounted) Navigator.pop(context);
                        },
                        child: const Text("Delete",
                            style: TextStyle(color: Colors.white)),
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
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.white,
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
    ));

    return tourWrapper(
      pageId: 'dashboard',
      /*// Only include keys that are ALWAYS rendered (search bar + add button).
      // Folder-specific keys are shown via the manual Help icon when present.
      autoStartKeys: [_tourSearchKey, _tourAddGroupKey],*/
      
      // After readyFuture completes the widget will have rebuilt with the
      // populated filteredFolders list, so the full 6-key list will be used.
      autoStartKeys: filteredFolders.isNotEmpty
          ? [
              _tourSearchKey,
              _tourAddGroupKey,
              _tourOpenGroupKey,
              _tourAddScheduleKey,
              _tourPersonIconKey,
              _tourEditKey,
              _tourDeleteKey,
            ]
          : [_tourSearchKey, _tourAddGroupKey],
      readyFuture: _dataLoaded.future,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          actions: [
            Builder(
              builder: (innerCtx) => IconButton(
                icon: const Icon(
                  Icons.help_outline_rounded,
                  color: Color(0xFF9E9E9E),
                ),
                tooltip: 'Show Guide',
                onPressed: () {
                  final keys = filteredFolders.isNotEmpty
                      ? [
                          _tourSearchKey,
                          _tourAddGroupKey,
                          _tourOpenGroupKey,
                          _tourAddScheduleKey,
                          _tourPersonIconKey,
                          _tourEditKey,
                          _tourDeleteKey,
                        ]
                      : [_tourSearchKey, _tourAddGroupKey];
                  ShowCaseWidget.of(innerCtx).startShowCase(keys);
                },
              ),
            ),
          ],
        ),
        body: GestureDetector(
        behavior: HitTestBehavior.opaque, // Makes entire body tappable
        onTap: () {
          FocusScope.of(context).unfocus(); // Close keyboard
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    tourTarget(
                      key: _tourSearchKey,
                      title: "Step 1 — Search groups",
                      description:
                          "Use search to quickly find the group you want.",
                      child: TextField(
                        controller: groupSearchController,
                        onChanged: _filterGroups,
                        decoration: InputDecoration(
                          hintText: "Search",
                          hintStyle:
                              const TextStyle(color: Color(0xFF9E9E9E)),
                          suffixIcon: groupSearchController.text.isEmpty
                              ? const Icon(Icons.search,
                                  color: Color(0x4D000000))
                              : IconButton(
                                  icon: const Icon(Icons.clear,
                                      color: Color(0xFF1565C0)),
                                  onPressed: () {
                                    groupSearchController.clear();
                                    _filterGroups("");
                                  },
                                ),
                          contentPadding: const EdgeInsets.only(
                              left: 10, top: 12, bottom: 12),
                          filled: true,
                          fillColor: const Color(0xFFF6F6F6),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Color(0x1A000000), width: 1)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Color(0xFFF6F6F6), width: 1)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Groups",
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: filteredFolders.isEmpty
                            ? (groupSearchController.text.isEmpty ? 2 : 1)
                            : filteredFolders.length + 1,
                        itemBuilder: (context, index) {
                          if (filteredFolders.isEmpty &&
                              groupSearchController.text.isNotEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                  child: Text("No matching groups found",
                                      style: TextStyle(color: Colors.grey))),
                            );
                          }

                          if (folders.isEmpty && index == 0) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: Text(
                                  "No groups created yet.\nTap the add button below to start.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            );
                          }

                          if ((filteredFolders.isEmpty && index == 1) ||
                              (filteredFolders.isNotEmpty &&
                                  index == filteredFolders.length)) {
                            return Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: tourTarget(
                                  key: _tourAddGroupKey,
                                  title: "Step 2 — Add a group",
                                  description:
                                      "Tap here to create a new group for a class.",
                                  shapeBorder: const RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(999)),
                                  ),
                                  child: Material(
                                    color: const Color(0xFF1565C0),
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(100),
                                      onTap: () => _showFolderDialog(),
                                      child: const SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: Icon(Icons.add,
                                            color: Colors.white, size: 22),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }

                          final folder = filteredFolders[index];

                          final bool isFirstFolderTile =
                              groupSearchController.text.isEmpty &&
                                  filteredFolders.isNotEmpty &&
                                  index == 0;

                          return Dismissible(
                            key: Key(folder.name),
                            background: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1565C0),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              child: const Icon(Icons.edit_rounded,
                                  color: Colors.white, size: 24),
                            ),
                            secondaryBackground: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF84F31),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete_rounded,
                                  color: Colors.white, size: 24),
                            ),
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.startToEnd) {
                                _showFolderDialog(folder: folder, isEdit: true);
                                return false;
                              } else {
                                _showDeleteDialog(folder);
                                return false;
                              }
                            },
                            child: Column(
                              children: [
                                (isFirstFolderTile
                                        ? tourTarget(
                                            key: _tourOpenGroupKey,
                                            title: "Step 3 — Open a group",
                                            description:
                                                "Tap a group to expand and see schedule times.",
                                            child: GestureDetector(
                                              onTap: () async {
                                                if (!folder.isExpanded &&
                                                    folder.files.isEmpty) {
                                                  await fetchFiles(folder);
                                                }
                                                setState(() => folder.isExpanded =
                                                    !folder.isExpanded);

                                                // After expanding, show add-schedule
                                                // Guide_mode is enabled.
                                                if (folder.isExpanded) {
                                                  WidgetsBinding.instance
                                                      .addPostFrameCallback((_) async {
                                                    try {
                                                      // Skip if the main tour is running.
                                                      final active =
                                                          ShowCaseWidget.activeTargetWidget(
                                                              context);
                                                      if (active == null) {
                                                        final prefs =
                                                            await SharedPreferences
                                                                .getInstance();
                                                        final guide = prefs
                                                                .getBool('guide_mode') ??
                                                            true;
                                                        if (guide) {
                                                          ShowCaseWidget.of(context)
                                                              .startShowCase(
                                                                  [_tourAddScheduleKey]);
                                                        }
                                                      }
                                                    } catch (_) {}
                                                  });
                                                }
                                              },
                                              child: Container(
                                                height: 105,
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFFF7F8FA),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                        12, 10, 12, 5),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Container(
                                                          width: 40,
                                                          height: 40,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color(
                                                                0x1A000000),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(8),
                                                            image: folder.imageUrl !=
                                                                        null &&
                                                                    folder.imageUrl!
                                                                        .isNotEmpty
                                                                ? DecorationImage(
                                                                    image: NetworkImage(
                                                                        folder.imageUrl!),
                                                                    fit: BoxFit.cover,
                                                                  )
                                                                : null,
                                                          ),
                                                          child: folder.imageUrl ==
                                                                      null ||
                                                                  folder.imageUrl!
                                                                      .isEmpty
                                                              ? const Icon(
                                                                  Icons.folder,
                                                                  color:
                                                                      Colors.grey,
                                                                  size: 20)
                                                              : null,
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                folder.name,
                                                                style:
                                                                    const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontSize: 15,
                                                                ),
                                                              ),
                                                              Text(
                                                                "Last updated on ${folder.date.day.toString().padLeft(2, '0')}/"
                                                                "${folder.date.month.toString().padLeft(2, '0')}/"
                                                                "${folder.date.year}",
                                                                style: const TextStyle(
                                                                    fontSize: 12,
                                                                    color:
                                                                        Colors.grey),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        Icon(
                                                          folder.isExpanded
                                                              ? Icons
                                                                  .keyboard_arrow_up_rounded
                                                              : Icons
                                                                  .keyboard_arrow_down_rounded,
                                                          color: const Color(
                                                              0xE6000000),
                                                        ),
                                                      ],
                                                    ),
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.end,
                                                      children: [
                                                        (isFirstFolderTile
                                                            ? tourTarget(
                                                                key: _tourPersonIconKey,
                                                                title:
                                                                    'Step 5 — Assign students',
                                                                description:
                                                                    'Enroll students into this class. Students must be registered first via the Enrollment page.',
                                                                shapeBorder:
                                                                    const CircleBorder(),
                                                                child: IconButton(
                                                                  onPressed: () {
                                                                    _showEnrollStudentDialog(
                                                                        folder
                                                                            .id!);
                                                                  },
                                                                  icon:
                                                                      const Icon(
                                                                    Icons.person,
                                                                    color: Color(
                                                                        0xB3000000),
                                                                    size: 20,
                                                                  ),
                                                                ),
                                                              )
                                                            : IconButton(
                                                                onPressed: () {
                                                                  _showEnrollStudentDialog(
                                                                      folder
                                                                          .id!);
                                                                },
                                                                icon: const Icon(
                                                                  Icons.person,
                                                                  color: Color(
                                                                      0xB3000000),
                                                                  size: 20,
                                                                ),
                                                              )),
                                                        Container(
                                                          width: 1,
                                                          height: 20,
                                                          color: const Color(
                                                              0x1A000000),
                                                        ),
                                                        (isFirstFolderTile
                                                            ? tourTarget(
                                                                key: _tourEditKey,
                                                                title: 'Step 6 — Edit group',
                                                                description:
                                                                    'Tap to edit name or photo. Or swipe → on the card.',
                                                                shapeBorder:
                                                                    const CircleBorder(),
                                                                child: IconButton(
                                                                  onPressed: () =>
                                                                      _showFolderDialog(
                                                                          folder: folder,
                                                                          isEdit: true),
                                                                  icon: const Icon(
                                                                    Icons.edit_rounded,
                                                                    color: Color(0xFF1565C0),
                                                                    size: 20,
                                                                  ),
                                                                ),
                                                              )
                                                            : IconButton(
                                                                onPressed: () =>
                                                                    _showFolderDialog(
                                                                        folder: folder,
                                                                        isEdit: true),
                                                                icon: const Icon(
                                                                  Icons.edit_rounded,
                                                                  color: Color(0xFF1565C0),
                                                                  size: 20,
                                                                ),
                                                              )),
                                                        Container(
                                                          width: 1,
                                                          height: 20,
                                                          color: const Color(
                                                              0x1A000000),
                                                        ),
                                                        (isFirstFolderTile
                                                            ? tourTarget(
                                                                key: _tourDeleteKey,
                                                                title: 'Step 7 — Delete group',
                                                                description:
                                                                    'Tap to delete. Or swipe ← on the card.',
                                                                shapeBorder:
                                                                    const CircleBorder(),
                                                                child: IconButton(
                                                                  onPressed: () =>
                                                                      _showDeleteDialog(
                                                                          folder),
                                                                  icon: const Icon(
                                                                    Icons.delete_rounded,
                                                                    color: Color(0xFFF84F31),
                                                                    size: 20,
                                                                  ),
                                                                ),
                                                              )
                                                            : IconButton(
                                                                onPressed: () =>
                                                                    _showDeleteDialog(
                                                                        folder),
                                                                icon: const Icon(
                                                                  Icons.delete_rounded,
                                                                  color: Color(0xFFF84F31),
                                                                  size: 20,
                                                                ),
                                                              )),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          )
                                        : GestureDetector(
                                    onTap: () async {
                                      if (!folder.isExpanded &&
                                          folder.files.isEmpty) {
                                        await fetchFiles(folder);
                                      }
                                      setState(() => folder.isExpanded =
                                          !folder.isExpanded);
                                    },
                                    child: Container(
                                      height: 105,
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF7F8FA),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 10, 12, 5),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0x1A000000),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  image: folder.imageUrl !=
                                                              null &&
                                                          folder.imageUrl!
                                                              .isNotEmpty
                                                      ? DecorationImage(
                                                          image: NetworkImage(
                                                              folder.imageUrl!),
                                                          fit: BoxFit.cover,
                                                        )
                                                      : null,
                                                ),
                                                child: folder.imageUrl ==
                                                            null ||
                                                        folder.imageUrl!.isEmpty
                                                    ? const Icon(Icons.folder,
                                                        color: Colors.grey,
                                                        size: 20)
                                                    : null,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      folder.name,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                    Text(
                                                      "Last updated on ${folder.date.day.toString().padLeft(2, '0')}/"
                                                      "${folder.date.month.toString().padLeft(2, '0')}/"
                                                      "${folder.date.year}",
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                folder.isExpanded
                                                    ? Icons
                                                        .keyboard_arrow_up_rounded
                                                    : Icons
                                                        .keyboard_arrow_down_rounded,
                                                color:
                                                    const Color(0xE6000000),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              IconButton(
                                                onPressed: () {
                                                  _showEnrollStudentDialog(
                                                      folder.id!);
                                                },
                                                icon: const Icon(
                                                  Icons.person,
                                                  color: Color(0xB3000000),
                                                  size: 20,
                                                ),
                                              ),
                                              Container(
                                                width: 1,
                                                height: 20,
                                                color:
                                                    const Color(0x1A000000),
                                              ),
                                              IconButton(
                                                onPressed: () =>
                                                    _showFolderDialog(
                                                        folder: folder,
                                                        isEdit: true),
                                                icon: const Icon(
                                                  Icons.edit_rounded,
                                                  color: Color(0xFF1565C0),
                                                  size: 20,
                                                ),
                                              ),
                                              Container(
                                                width: 1,
                                                height: 20,
                                                color:
                                                    const Color(0x1A000000),
                                              ),
                                              IconButton(
                                                onPressed: () =>
                                                    _showDeleteDialog(folder),
                                                icon: const Icon(
                                                  Icons.delete_rounded,
                                                  color: Color(0xFFF84F31),
                                                  size: 20,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  )),
                                if (folder.isExpanded)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 0),
                                    child: Column(
                                      children: [
                                        for (var file in folder.files)
                                          InkWell(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      Attendance(
                                                    classId: file.id,
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Container(
                                              height: 60,
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF7F8FA),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 15),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          file.name,
                                                          style:
                                                              const TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                        Text(
                                                          "Last Updated on ${file.date.day.toString().padLeft(2, '0')}/${file.date.month.toString().padLeft(2, '0')}/${file.date.year}",
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 12,
                                                                  color: Colors
                                                                      .grey),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuButton<String>(
                                                    icon: const Icon(
                                                        Icons.more_vert_rounded,
                                                        size: 20),
                                                    color: Color(0xE61565C0),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                    onSelected: (value) {
                                                      if (value == 'edit') {
                                                        _showFileDialog(folder,
                                                            file: file,
                                                            isEdit: true);
                                                      } else if (value ==
                                                          'delete') {
                                                        _showDeleteDialog(file,
                                                            isFile: true,
                                                            folder: folder);
                                                      }
                                                    },
                                                    itemBuilder: (context) => [
                                                      PopupMenuItem(
                                                        value: 'edit',
                                                        child: Row(
                                                          children: const [
                                                            Icon(
                                                                Icons
                                                                    .edit_rounded,
                                                                color: Colors
                                                                    .white,
                                                                size: 20),
                                                            SizedBox(width: 5),
                                                            Text('Edit',
                                                                style: TextStyle(
                                                                    color: Colors
                                                                        .white)),
                                                          ],
                                                        ),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 'delete',
                                                        child: Row(
                                                          children: const [
                                                            Icon(
                                                                Icons
                                                                    .delete_rounded,
                                                                color: Colors
                                                                    .white,
                                                                size: 20),
                                                            SizedBox(width: 5),
                                                            Text('Delete',
                                                                style: TextStyle(
                                                                    color: Colors
                                                                        .white)),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        const SizedBox(height: 4),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                  color:
                                                      const Color(0x1A000000),
                                                  width: 1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: (isFirstFolderTile
                                                ? tourTarget(
                                                    key: _tourAddScheduleKey,
                                                    title: "Step 4 — Schedule time",
                                                    description:
                                                        "Create session times for this subject here.",
                                                    child: TextButton.icon(
                                                      onPressed: () =>
                                                          _showFileDialog(
                                                              folder),
                                                      icon: const Icon(
                                                          Icons.add_rounded,
                                                          color:
                                                              Color(0xFF1565C0),
                                                          size: 18),
                                                      label: const Text(
                                                        "Add New Schedule Time",
                                                        style: TextStyle(
                                                          color: Color(
                                                              0xFF1565C0),
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                : TextButton.icon(
                                                    onPressed: () =>
                                                        _showFileDialog(folder),
                                                    icon: const Icon(
                                                        Icons.add_rounded,
                                                        color:
                                                            Color(0xFF1565C0),
                                                        size: 18),
                                                    label: const Text(
                                                      "Add New Schedule Time",
                                                      style: TextStyle(
                                                        color:
                                                            Color(0xFF1565C0),
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  )),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
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
      ),
    );
  }
}

class _ScheduleSpec {
  final List<int> weekdays; // DateTime weekday integers (1..7)
  final TimeOfDay start;
  final TimeOfDay end;

  _ScheduleSpec({
    required this.weekdays,
    required this.start,
    required this.end,
  });
}