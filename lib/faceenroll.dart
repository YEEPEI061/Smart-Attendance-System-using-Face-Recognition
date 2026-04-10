import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:userinterface/faceenroll2.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';

class Enrollment extends StatefulWidget {
  const Enrollment({super.key});

  @override
  State<Enrollment> createState() => _EnrollmentState();
}

class _EnrollmentState extends State<Enrollment> {
  List<CameraDescription>? _cameras;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initializeCameras();
  }

  Future<void> _initializeCameras() async {
    final cameras = await availableCameras();
    setState(() {
      _cameras = cameras;
      _loading = false;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: ScannerScreen(cameras: _cameras!),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  // NEW 👇
  final bool isEditMode;
  final String? studentId;

  const ScannerScreen({
    super.key,
    required this.cameras,
    this.isEditMode = false,
    this.studentId,
  });

  @override
  _ScannerScreenState createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool showSettings = false;
  bool showGrid = false;
  bool soundOn = false;
  bool flashOn = false;
  bool _isCameraReady = false;
  bool _isAddingPhoto = false;

  int currentCameraIndex = 0;
  CameraController? _controller;
  int _currentPreviewIndex = 0;

  // Store multiple captured/picked images
  List<XFile> _capturedImages = [];

  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    if (widget.cameras.isNotEmpty) {
      _initializeCamera(widget.cameras[currentCameraIndex]);
    }
  }

  Future<void> _initializeCamera(CameraDescription camera) async {
    _controller?.dispose();
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller!.initialize();

      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();
      _maxZoom = _maxZoom.clamp(1.0, 3.0);
      _currentZoom = _minZoom;

      await _controller!
          .setFlashMode(flashOn ? FlashMode.torch : FlashMode.off);

      if (mounted) {
        setState(() {
          _isCameraReady = true;
        });
      }
    } catch (e) {
      debugPrint("Camera error: $e");
    }
  }

  void _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => flashOn = !flashOn);
    await _controller!.setFlashMode(flashOn ? FlashMode.torch : FlashMode.off);
  }

  void _switchCamera() async {
    if (widget.cameras.length < 2) return;

    final currentLensDirection =
        widget.cameras[currentCameraIndex].lensDirection;
    final newIndex = widget.cameras.indexWhere((camera) =>
        camera.lensDirection ==
        (currentLensDirection == CameraLensDirection.front
            ? CameraLensDirection.back
            : CameraLensDirection.front));

    if (newIndex == -1) return;

    setState(() {
      currentCameraIndex = newIndex;
      _isCameraReady = false;
    });

    await _initializeCamera(widget.cameras[currentCameraIndex]);
  }

  void _capturePhoto() async {
    if (!_isCameraReady || _controller == null) return;

    try {
      final XFile image = await _controller!.takePicture();

      final fixedImage =
          await FlutterExifRotation.rotateImage(path: image.path);

      setState(() {
        _capturedImages.add(XFile(fixedImage.path));
        _currentPreviewIndex = _capturedImages.length - 1;
        _isAddingPhoto = false;
      });
    } catch (e) {
      debugPrint("Error capturing photo: $e");
    }
  }

  Future<void> _safeNavigate(String routeName) async {
    if (_controller != null && _controller!.value.isInitialized) {
      await _controller!.dispose();
      _controller = null;
    }
    setState(() {
      _capturedImages.clear();
      _isCameraReady = false;
    });
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      Navigator.pushReplacementNamed(context, routeName);
    }
  }

  void _pickMultipleImages() async {
    try {
      final picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage();

      if (images.isNotEmpty && mounted) {
        List<XFile> fixedImages = [];

        for (var img in images) {
          final fixed = await FlutterExifRotation.rotateImage(path: img.path);
          fixedImages.add(XFile(fixed.path));
        }

        setState(() {
          _capturedImages = fixedImages;
          _currentPreviewIndex = 0;
        });
      }
    } catch (e) {
      debugPrint("Error picking multiple images: $e");
    }
  }

  // void _confirmImage() async {
  //   if (_capturedImages.isEmpty) return;

  //   if (_controller != null && _controller!.value.isInitialized) {
  //     await _controller!.dispose();
  //     _controller = null;
  //   }

  //   setState(() => _isCameraReady = false);
  //   await Future.delayed(const Duration(milliseconds: 300));

  //   if (!mounted) return;

  //   Navigator.pushReplacement(
  //     context,
  //     MaterialPageRoute(
  //       builder: (context) => EnrollmentPage(
  //         imagePaths: _capturedImages.map((e) => e.path).toList(),
  //         isEditMode: false,
  //       ),
  //     ),
  //   );
  // }

  void _confirmImage() async {
    if (_capturedImages.isEmpty) return;

    final images = _capturedImages.map((e) => e.path).toList();

    if (!mounted) return;

    // 🔥 CASE 1: EDIT MODE → ADD FACE ONLY
    if (widget.isEditMode) {
      Navigator.pop(context, {
        "mode": "add_face",
        "student_id": widget.studentId,
        "images": images,
      });
      return;
    }

    // 🔥 CASE 2: NEW ENROLLMENT
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => EnrollmentPage(
          imagePaths: _capturedImages.map((e) => e.path).toList(),
          isEditMode: false,
        ),
      ),
    );
  }

  void _retakeImage() async {
    setState(() {
      _capturedImages.clear();
    });

    if (_controller != null &&
        _controller!.value.isInitialized &&
        !_controller!.value.isTakingPicture &&
        !_controller!.value.isStreamingImages) {
      await _controller!.resumePreview();
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: const Color(0xFF1565C0),
      // bottomNavigationBar: _buildBottomNavigationBar(),
      bottomNavigationBar: const SizedBox(height: 60),
      body: (_capturedImages.isNotEmpty && !_isAddingPhoto)
          ? _buildPreview()
          : _buildCameraUI(),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.white, width: 1)),
      ),
      child: BottomNavigationBar(
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
            Navigator.pushReplacementNamed(context, '/dashboard');
          } else if (index == 1) {
            Navigator.pushReplacementNamed(context, '/enroll');
          } else if (index == 2) {
            Navigator.pushReplacementNamed(context, '/reports');
          } else if (index == 3) {
            Navigator.pushReplacementNamed(context, '/settings');
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

  Widget _buildCameraUI() {
    return Column(
      children: [
        _buildTopBar(),
        Expanded(child: _buildCameraPreview()),
        _buildCameraBottomBar(),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: const Color(0xFF1565C0),
      padding: const EdgeInsets.fromLTRB(16, 35, 16, 10),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // CLOSE BUTTON
            GestureDetector(
              onTap: () => {Navigator.pop(context)},
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 28),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: _toggleFlash,
                  child: Icon(
                    flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: flashOn ? Color(0xFFFBC04A) : Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => setState(() => showSettings = !showSettings),
                  child: const Icon(Icons.more_vert_rounded,
                      color: Colors.white, size: 26),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_isCameraReady ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return Container(color: Colors.black);
    }

    return GestureDetector(
      // Pinch to zoom
      onScaleStart: (details) {
        _baseZoom = _currentZoom;
      },

      onScaleUpdate: (details) async {
        if (_controller == null || !_controller!.value.isInitialized) return;
        if (_controller!.description.lensDirection == CameraLensDirection.front)
          return;

        double newZoom = _baseZoom * details.scale;
        newZoom = newZoom.clamp(_minZoom, _maxZoom);

        await _controller!.setZoomLevel(newZoom);
        _currentZoom = newZoom;
      },

      onTap: () {
        if (showSettings) setState(() => showSettings = false);
      },

      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_isCameraReady && _controller != null)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.previewSize!.height,
                  height: _controller!.value.previewSize!.width,
                  child: CameraPreview(_controller!),
                ),
              ),
            )
          else
            Container(color: Colors.grey[200]),
          if (showGrid)
            IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: GridPainter(),
              ),
            ),
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: FaceOutlinePainter(),
            ),
          ),
          if (showSettings) _buildSettingsPanel(),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Positioned(
      top: 0,
      right: 12,
      child: Container(
        width: 200,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFBC04A).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Settings",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Container(
                height: 1,
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 5)),
            const SizedBox(height: 5),
            _buildCustomSwitch(
                "Grid", showGrid, (v) => setState(() => showGrid = v)),
            _buildCustomSwitch(
                "Sound", soundOn, (v) => setState(() => soundOn = v)),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraBottomBar() {
    return Container(
      color: const Color(0xFF1565C0),
      height: 85,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 12,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                ),
                GestureDetector(
                  onTap: _capturePhoto,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 40,
            bottom: 18,
            child: GestureDetector(
              onTap: _pickMultipleImages,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const Icon(Icons.photo_library_rounded,
                      color: Colors.white, size: 28),
                ],
              ),
            ),
          ),
          Positioned(
            right: 40,
            bottom: 18,
            child: GestureDetector(
              onTap: _switchCamera,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const Icon(Icons.cameraswitch_rounded,
                      color: Colors.white, size: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Stack(
      children: [
        PageView.builder(
          itemCount: _capturedImages.length,
          onPageChanged: (index) =>
              setState(() => _currentPreviewIndex = index),
          itemBuilder: (context, index) {
            return SizedBox.expand(
              child: Image.file(
                File(_capturedImages[index].path),
                fit: BoxFit.contain,
              ),
            );
          },
        ),
        Positioned(
          top: 35,
          left: 16,
          child: GestureDetector(
            onTap: _retakeImage,
            child: const Icon(Icons.arrow_back_rounded,
                color: Colors.white, size: 28),
          ),
        ),
        if (_capturedImages.length > 1)
          Positioned(
            top: 35,
            right: 16,
            child: Text(
              "${_currentPreviewIndex + 1} / ${_capturedImages.length}",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
          ),
        Positioned(
          bottom: 40,
          left: MediaQuery.of(context).size.width / 2 - 25,
          child: GestureDetector(
            onTap: () async {
              setState(() => _isAddingPhoto = true);
              if (_controller != null &&
                  _controller!.value.isInitialized &&
                  !_controller!.value.isTakingPicture &&
                  !_controller!.value.isStreamingImages) {
                try {
                  await _controller!.resumePreview();
                } catch (e) {
                  debugPrint("Error resuming preview: $e");
                }
              }
            },
            child: Column(
              children: const [
                Icon(Icons.add_circle_outline, color: Colors.white, size: 40),
                SizedBox(height: 5),
                Text(
                  "Add",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 40,
          left: 50,
          child: GestureDetector(
            onTap: _retakeImage,
            child: Column(
              children: const [
                Icon(Icons.refresh_rounded, color: Colors.white, size: 40),
                SizedBox(height: 5),
                Text(
                  "Retake",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 40,
          right: 50,
          child: GestureDetector(
            onTap: _confirmImage,
            child: Column(
              children: const [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 40),
                SizedBox(height: 5),
                Text(
                  "Confirm",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomSwitch(
      String title, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Container(
            width: 32,
            height: 16,
            decoration: BoxDecoration(
              color: value ? const Color(0xFF1565C0) : Colors.grey,
              borderRadius: BorderRadius.circular(8),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    if (_controller != null && _controller!.value.isInitialized) {
      _controller!.dispose();
    }
    _controller = null;
    super.dispose();
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1;

    double stepX = size.width / 3;
    double stepY = size.height / 3;

    for (int i = 1; i < 3; i++) {
      canvas.drawLine(
          Offset(stepX * i, 0), Offset(stepX * i, size.height), linePaint);
      canvas.drawLine(
          Offset(0, stepY * i), Offset(size.width, stepY * i), linePaint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class FaceOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final ovalWidth = size.width * 0.5;
    final ovalHeight = size.height * 0.5;

    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: ovalWidth,
      height: ovalHeight,
    );

    canvas.drawOval(rect, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
