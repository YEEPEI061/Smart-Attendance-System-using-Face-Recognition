import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:userinterface/scanattendance.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:userinterface/services/notification_service.dart';

class Attendance extends StatefulWidget {
  final int classId;
  const Attendance({
    super.key,
    required this.classId,
  });

  @override
  State<Attendance> createState() => _AttendanceState();
}

class _AttendanceState extends State<Attendance> {
  List<Map<String, dynamic>> masterAttendanceList = [];
  List<Map<String, dynamic>> attendanceList = [];
  bool isLoading = true;

  List<String> selectedFilters = ["All"];
  String sortOrder = "A-Z";

  final GlobalKey _filterKey = GlobalKey();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchAttendance(widget.classId);
    fetchSummary(widget.classId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null && args['refresh'] == true) {
      fetchAttendance(widget.classId); // reload list
    }
  }

  void _showFilterPopup() {
    final RenderBox renderBox =
        _filterKey.currentContext!.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx - 130,
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
              const subFilters = ["Present", "Absent"];

              return IconTheme(
                data: const IconThemeData(
                  color: Color(0xFFFFFFFF),
                  size: 18,
                ),
                child: SizedBox(
                  width: 140,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 5.0, top: 5.0),
                        child: Text(
                          "Sort & Filter",
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white, thickness: 1),
                      ...["All", ...subFilters].map((item) {
                        bool checked = selectedFilters.contains(item);
                        return _buildSelectionRow(
                          label: item,
                          icon: checked
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          onTap: () {
                            menuSetState(() {
                              if (item == "All") {
                                if (checked) {
                                  selectedFilters = [];
                                } else {
                                  selectedFilters = ["All", ...subFilters];
                                }
                              } else {
                                if (checked) {
                                  selectedFilters.remove(item);
                                  selectedFilters.remove("All");
                                } else {
                                  selectedFilters.add(item);
                                  if (subFilters.every((element) =>
                                      selectedFilters.contains(element))) {
                                    selectedFilters.add("All");
                                  }
                                }
                              }
                              _applySortFilter();
                            });
                          },
                        );
                      }).toList(),
                      const Divider(color: Colors.white, thickness: 1),
                      _buildSelectionRow(
                        label: "A-Z",
                        icon: sortOrder == "A-Z"
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        onTap: () => menuSetState(() {
                          sortOrder = "A-Z";
                          _applySortFilter();
                        }),
                      ),
                      _buildSelectionRow(
                        label: "Z-A",
                        icon: sortOrder == "Z-A"
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        onTap: () => menuSetState(() {
                          sortOrder = "Z-A";
                          _applySortFilter();
                        }),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showTipsDialog() {
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
                "• 📷 Tap to scan attendance\n"
                "• 👆 Long press to mark manually\n"
                "• ⬅️ Swipe left to remove\n"
                "• 🔍 Filter to sort",
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

  Widget _buildSelectionRow({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  void _applySortFilter() {
    setState(() {
      List<Map<String, dynamic>> filtered = List.from(masterAttendanceList);

      String query = _searchController.text.toLowerCase();
      if (query.isNotEmpty) {
        filtered = filtered.where((item) {
          return item['name'].toString().toLowerCase().contains(query) ||
              item['student_card_id'].toString().toLowerCase().contains(query);
        }).toList();
      }

      if (!selectedFilters.contains("All")) {
        filtered = filtered.where((item) {
          String status = item['status'].toString().toLowerCase();
          bool matchesPresent =
              selectedFilters.contains("Present") && status == 'present';
          bool matchesAbsent =
              selectedFilters.contains("Absent") && status == 'absent';

          return matchesPresent || matchesAbsent;
        }).toList();
      }

      filtered.sort((a, b) {
        final nameA = a['name'].toString().toLowerCase();
        final nameB = b['name'].toString().toLowerCase();
        return sortOrder == "A-Z"
            ? nameA.compareTo(nameB)
            : nameB.compareTo(nameA);
      });

      attendanceList = filtered;
    });
  }

  void _showManualAttendanceDialog(
    int studentId,
    String name,
    String currentStatus,
  ) {
    final bool isCurrentlyPresent = currentStatus.toLowerCase() == 'present';

    final String newStatus = isCurrentlyPresent ? 'Absent' : 'Present';
    final Color statusColor =
        isCurrentlyPresent ? const Color(0xFFEA324C) : const Color(0xFF00B38A);

    final Color iconBgColor =
        isCurrentlyPresent ? const Color(0xFFFFEBEE) : const Color(0xFFE3F2FD);

    final Color iconColor =
        isCurrentlyPresent ? const Color(0xFFEA324C) : const Color(0xFF1565C0);

    final IconData dialogIcon = isCurrentlyPresent
        ? Icons.person_remove_alt_1_rounded
        : Icons.how_to_reg_rounded;

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
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  dialogIcon,
                  color: iconColor,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Manual Attendance",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
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
                    const TextSpan(text: "Are you sure you want to mark\n"),
                    TextSpan(
                      text: name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const TextSpan(text: " as "),
                    TextSpan(
                      text: newStatus,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                    const TextSpan(text: "?"),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
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
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);

                        if (newStatus == 'Present') {
                          updateManualAttendance(studentId, newStatus);
                        } else {
                          // DELETE attendance instead of creating "Absent"
                          final record = attendanceList.firstWhere(
                            (e) => e['student_id'] == studentId,
                            orElse: () => {},
                          );

                          if (record.isNotEmpty && record['id'] != null) {
                            final attendanceId =
                                int.tryParse(record['id'].toString());

                            if (attendanceId != null) {
                              deleteAttendance(attendanceId);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text("Invalid attendance ID")),
                              );
                            }
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        "Confirm",
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

  Future<void> fetchAttendance(int classId) async {
    try {
      final baseUrl = dotenv.env['BASE_URL']!;
      final response = await http.get(
        Uri.parse('$baseUrl/attendance?class_id=$classId'),
      );

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        setState(() {
          final List mappedData = data
              .map((e) => {
                    'id': e['id'],
                    'student_id': e['student_id'],
                    'name': e['name'] ?? 'Unknown',
                    'student_card_id': e['student_card_id'] ?? '--',
                    'course': e['course'] ?? '--',
                    'time': e['time'] ?? '--:-- --',
                    'status': e['status'] ?? 'Absent',
                    'face_image_url': e['face_image_url'] ?? '',
                    'date': e['date'] ?? '',
                  })
              .toList();
          masterAttendanceList = List.from(mappedData);
          attendanceList = List.from(mappedData);
          isLoading = false;
          _applySortFilter();
        });
      } else {
        throw Exception('Failed to load data');
      }
    } catch (e) {
      log("Error fetching attendance: $e");
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> updateManualAttendance(int studentId, String status) async {
    try {
      final baseUrl = dotenv.env['BASE_URL']!;
      final response = await http.post(
        Uri.parse('$baseUrl/attendance/manual'),
        body: jsonEncode({
          'class_id': widget.classId,
          'student_id': studentId,
          'status': status,
        }),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Student marked as $status"),
            behavior: SnackBarBehavior.floating,
          ),
        );

        fetchAttendance(widget.classId);
        fetchSummary(widget.classId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update attendance: ${response.body}"),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      log("Error updating manual attendance: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Error updating attendance"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> deleteAttendance(int attendanceId) async {
    try {
      final baseUrl = dotenv.env['BASE_URL']!;
      final response = await http.delete(
        Uri.parse('$baseUrl/attendance/$attendanceId'),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Marked as Absent"),
            behavior: SnackBarBehavior.floating,
          ),
        );

        fetchAttendance(widget.classId);
        fetchSummary(widget.classId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed: ${response.body}")),
        );
      }
    } catch (e) {
      log("Error deleting attendance: $e");
    }
  }

  Future<void> deleteEnrollment(int studentId) async {
    try {
      final baseUrl = dotenv.env['BASE_URL']!;
      final url =
          Uri.parse('$baseUrl/enrollments/$studentId/${widget.classId}');
      final response = await http.delete(url);

      if (response.statusCode == 200) {
        // Attendance is taken now, so cancel today's "10 minutes before end" reminder.
        final preEndId = NotificationService.buildSessionNotificationId(
          classId: widget.classId,
          sessionDate: DateTime.now(),
          type: 2,
        );
        await NotificationService.cancel(preEndId);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Student removed from class"),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Refresh the attendance list since the student is no longer enrolled
        fetchAttendance(widget.classId);
        fetchSummary(widget.classId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to remove student: ${response.body}")),
        );
      }
    } catch (e) {
      log("Error deleting enrollment: $e");
    }
  }

  int presentCount = 0;
  int absentCount = 0;

  Future<void> fetchSummary(int classId) async {
    try {
      final baseUrl = dotenv.env['BASE_URL']!;
      final response = await http
          .get(Uri.parse('$baseUrl/attendance/summary?class_id=$classId'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        log("Fetched summary data: $data");
        setState(() {
          presentCount = data['present_count'] ?? 0;
          absentCount = data['absent_count'] ?? 0;
        });
      } else {
        log("Failed to load summary: ${response.statusCode}");
        setState(() {
          presentCount = 0;
          absentCount = 0;
        });
      }
    } catch (e) {
      log("Error fetching summary: $e");
      setState(() {
        presentCount = 0;
        absentCount = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Color(0xFF9E9E9E)),
            onPressed: () => _showTipsDialog(),
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

                  // Search Bar
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => _applySortFilter(),
                    style: const TextStyle(
                      color: Color(0xFF000000),
                    ),
                    decoration: InputDecoration(
                      hintText: "Search",
                      hintStyle: const TextStyle(
                        color: Color(0xFF9E9E9E),
                      ),
                      suffixIcon:
                          const Icon(Icons.search, color: Color(0x4D000000)),
                      contentPadding:
                          const EdgeInsets.only(left: 10, top: 12, bottom: 12),
                      filled: true,
                      fillColor: const Color(0xFFF6F6F6),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0x1A000000),
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFFF6F6F6),
                          width: 1,
                        ),
                      ),
                    ),
                    cursorColor: Colors.black,
                  ),

                  const SizedBox(height: 15),

                  // Summary
                  const Text(
                    "Today's Summary",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: Container(
                          height: 70,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.2),
                                spreadRadius: 1,
                                blurRadius: 3,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$presentCount',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              const Text('Present',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 70,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.2),
                                spreadRadius: 1,
                                blurRadius: 3,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$absentCount',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              const Text('Absent',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 15),

                  // Recent Scans Label
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Recent Scans",
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        key: _filterKey,
                        icon: const Icon(
                          Icons.filter_alt_rounded,
                          color: Color(0xFF1565C0),
                        ),
                        onPressed: () {
                          _showFilterPopup();
                        },
                      ),
                    ],
                  ),

                  // Scrollable Recent Scans List
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 43),
                      itemCount: attendanceList.length,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemBuilder: (context, index) {
                        final record = attendanceList[index];
                        return Dismissible(
                          key: Key(record['id'].toString() + record['status']),
                          background: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF84F31),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            height: 60,
                            child: const Icon(Icons.delete,
                                color: Colors.white, size: 24),
                          ),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (direction) async {
                            if (direction == DismissDirection.endToStart) {
                              bool confirmed = await showDialog(
                                context: context,
                                builder: (_) => Dialog(
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  insetPadding: const EdgeInsets.all(24),
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.delete_forever_rounded,
                                            color: Color(0xFFF84F31), size: 48),
                                        const SizedBox(height: 12),
                                        const Text(
                                          "Are you sure?",
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          "Do you really want to delete this record?\nThis process cannot be undone.",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                        const SizedBox(height: 24),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: () => Navigator.pop(
                                                    context, false),
                                                style: OutlinedButton.styleFrom(
                                                  backgroundColor:
                                                      const Color(0xFFF6F6F6),
                                                  side: const BorderSide(
                                                      color: Color(0xFFF6F6F6)),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                ),
                                                child: const Text(
                                                  "Cancel",
                                                  style: TextStyle(
                                                      color: Colors.grey,
                                                      fontWeight:
                                                          FontWeight.w600),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      const Color(0xFFF84F31),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8)),
                                                ),
                                                onPressed: () => Navigator.pop(
                                                    context, true),
                                                child: const Text(
                                                  "Delete",
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600),
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

                              if (confirmed == true &&
                                  record['student_id'] != null) {
                                await deleteEnrollment(record['student_id']);
                              }
                              return false;
                            }
                            return false;
                          },
                          child: GestureDetector(
                            onLongPress: () {
                              _showManualAttendanceDialog(
                                record['student_id'],
                                record['name'],
                                record['status']?.toString() ?? 'Absent',
                              );
                            },
                            child: Container(
                              height: 78,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F8FA),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 25,
                                    backgroundColor: const Color(0xFF9E9E9E),
                                    child: ClipOval(
                                      child:
                                          (record['face_image_url'] != null &&
                                                  record['face_image_url']
                                                      .toString()
                                                      .isNotEmpty)
                                              ? Builder(
                                                  builder: (context) {
                                                    final imageUrl =
                                                        record['face_image_url']
                                                            .toString();
                                                    log("Student image URL: $imageUrl");

                                                    return Image.network(
                                                      imageUrl,
                                                      width: 50,
                                                      height: 50,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context,
                                                          error, stackTrace) {
                                                        log("Image load failed: $imageUrl");
                                                        log("Error: $error");
                                                        return const Icon(
                                                          Icons
                                                              .account_circle_rounded,
                                                          color: Colors.white,
                                                          size: 30,
                                                        );
                                                      },
                                                    );
                                                  },
                                                )
                                              : const Icon(
                                                  Icons.account_circle_rounded,
                                                  color: Colors.white,
                                                  size: 30,
                                                ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          record['name'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                        Text(
                                          record['student_card_id']
                                                  ?.toString() ??
                                              '--',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w300,
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          record['course']?.toString() ?? '--',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w300,
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          record['time'],
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0XCC000000),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        (record['status'] != null)
                                            ? '${record['status'][0].toUpperCase()}${record['status'].substring(1).toLowerCase()}'
                                            : 'Unknown',
                                        style: TextStyle(
                                          color: (record['status']
                                                      ?.toString()
                                                      .toLowerCase() ==
                                                  'present')
                                              ? const Color(0xFF00B38A)
                                              : const Color(0xFFEA324C),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),

                                      // Vertical divider
                                      Container(
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        height: 20,
                                        width: 1,
                                        color: const Color(0x1A000000),
                                      ),

                                      // Delete icon
                                      GestureDetector(
                                        onTap: () async {
                                          bool confirmed = await showDialog(
                                            context: context,
                                            builder: (context) => Dialog(
                                              backgroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                              insetPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 40),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(24),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    // Red Trash Icon Header
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              16),
                                                      decoration:
                                                          const BoxDecoration(
                                                        color: Color(
                                                            0xFFFFEBEE), // Very light red background
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: const Icon(
                                                        Icons
                                                            .delete_forever_rounded,
                                                        color:
                                                            Color(0xFFF84F31),
                                                        size: 40,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 20),

                                                    // Title
                                                    const Text(
                                                      "Are you sure?",
                                                      style: TextStyle(
                                                        fontSize: 20,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.black87,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 12),

                                                    // Warning Text
                                                    const Text(
                                                      "Do you really want to delete this record?\nThis process cannot be undone.",
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                        color: Colors.grey,
                                                        fontSize: 15,
                                                        height: 1.5,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 32),

                                                    // Action Buttons
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: OutlinedButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    context,
                                                                    false),
                                                            style:
                                                                OutlinedButton
                                                                    .styleFrom(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      vertical:
                                                                          12),
                                                              backgroundColor:
                                                                  const Color(
                                                                      0xFFF6F6F6),
                                                              side: const BorderSide(
                                                                  color: Color(
                                                                      0xFFF6F6F6)),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            8),
                                                              ),
                                                            ),
                                                            child: const Text(
                                                              "Cancel",
                                                              style: TextStyle(
                                                                color:
                                                                    Colors.grey,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 12),
                                                        Expanded(
                                                          child: ElevatedButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    context,
                                                                    true),
                                                            style:
                                                                ElevatedButton
                                                                    .styleFrom(
                                                              backgroundColor:
                                                                  const Color(
                                                                      0xFFF84F31), // Red action
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      vertical:
                                                                          12),
                                                              elevation: 0,
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            8),
                                                              ),
                                                            ),
                                                            child: const Text(
                                                              "Delete",
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
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

                                          if (confirmed == true &&
                                              record['student_id'] != null) {
                                            await deleteEnrollment(
                                                record['student_id']);
                                          }
                                        },
                                        child: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 20,
                                          color: Color(0xFFF84F31),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70),
        child: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      ScanAttendance(classId: widget.classId)),
            );
          },
          child: Container(
            height: 48,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1565C0), width: 2),
            ),
            child: const Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    "Take Attendance",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.grey,
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
}
