import 'dart:io';
// NOTE: ⚠️ UNCOMMENT THESE IMPORTS AFTER ADDING THE 'camera' PACKAGE TO PUBSPEC.YAML
import 'package:camera/camera.dart';
import 'package:ecopilot/screens/disposal_guidance_screen.dart';
import 'package:ecopilot/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ecopilot/auth/firebase_service.dart';
import 'profile_screen.dart' as profile_screen;
import 'alternative_screen.dart' as alternative_screen;
import 'package:ecopilot/widgets/app_drawer.dart';
import '/utils/constants.dart';
import 'package:ecopilot/models/product_analysis_data.dart';
import 'package:ecopilot/screens/result_screen.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// Colors are defined in lib/utils/constants.dart

// ProductAnalysisData moved to lib/models/product_analysis_data.dart
// --- III. Helper Widgets (ResultScreen, ProfileScreen) ---
// (ResultScreen and ProfileScreen remain unchanged for brevity, but are included in the final file)

// class ProfileScreen extends StatelessWidget {
//   const ProfileScreen({Key? key}) : super(key: key);
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Profile')),
//       body: const Center(child: Text('Profile Screen - Implement me!')),
//     );
//   }
// }

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  // ⚠️ UNCOMMENT THESE VARIABLES FOR CAMERA PACKAGE INTEGRATION
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  List<CameraDescription> _cameras = [];

  // Barcode scanner
  MobileScannerController? _barcodeScannerController;
  bool _isBarcodeMode = false; // Toggle between image and barcode scanning

  bool _isLoading = false;
  late final String _geminiApiKey;
  final ImagePicker _picker = ImagePicker();
  final int _selectedIndex = 2; // Default to 'Scan' tab
  bool _isFlashOn = false; // State for flashlight (controls the icon)
  // bool _isFrontCamera = false; // State for camera toggle (controls the icon)

  // NOTE: This variable is now unused, as the flip button is replaced by Capture.
  // We keep the state logic for conceptual camera control.

  // A. State Variables & Initialization
  @override
  void initState() {
    super.initState();
    _geminiApiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

    // Start camera initialization
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();

    // Initialize barcode scanner
    _barcodeScannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  Future<void> _initializeCamera() async {
    // ⚠️ UNCOMMENT and use these methods for actual camera setup.

    try {
      // Ensure camera permission is granted before initializing cameras.
      final status = await Permission.camera.status;
      if (!status.isGranted) {
        final res = await Permission.camera.request();
        if (!res.isGranted) {
          debugPrint('Camera permission not granted. Aborting camera init.');
          return;
        }
      }
      // 1. Fetch available cameras
      _cameras = await availableCameras();

      // 2. Initialize the controller with the rear camera
      _cameraController = CameraController(
        _cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras.first,
        ),
        ResolutionPreset.high,
        enableAudio: false,
      );

      // 3. Initialize the controller instance
      await _cameraController!.initialize();

      // 4. Update state to reflect readiness
      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
      // Set initial flash mode (don't await inside setState)
      try {
        await _cameraController!.setFlashMode(FlashMode.off);
      } catch (_) {}
    } on CameraException catch (e) {
      debugPrint("Camera initialization error: $e");
      // Handle error gracefully in UI, e.g., show an error message
    }

    debugPrint("Camera initialization logic executed (using simulation).");
    if (mounted) {
      // Simulate initialization completion for UI to render properly
      setState(() {
        // _isCameraInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    // Remove lifecycle observer and dispose controller safely
    WidgetsBinding.instance.removeObserver(this);
    try {
      _cameraController?.dispose();
    } catch (_) {}
    try {
      _barcodeScannerController?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle camera during app lifecycle changes. Prefer pause/resume preview
    // so the underlying texture is preserved where supported.
    super.didChangeAppLifecycleState(state);
    if (_cameraController == null) return;
    try {
      if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused) {
        // Try pausing preview first; on some devices disposing is required.
        try {
          _cameraController?.pausePreview();
        } catch (_) {
          try {
            _cameraController?.dispose();
            _cameraController = null;
            if (mounted) setState(() => _isCameraInitialized = false);
          } catch (_) {}
        }
      } else if (state == AppLifecycleState.resumed) {
        // Resume preview when returning; if controller was disposed, re-init.
        try {
          if (_cameraController != null) {
            // Try to resume preview without awaiting; handle errors by reinitializing
            _cameraController!
                .resumePreview()
                .then((_) {
                  if (mounted) setState(() => _isCameraInitialized = true);
                })
                .catchError((e) async {
                  debugPrint('Error resuming preview: $e');
                  // Reinitialize if resume fails
                  _initializeCamera();
                });
          } else {
            // Reinitialize controller if it was disposed while paused
            _initializeCamera();
          }
        } catch (e) {
          debugPrint('Error resuming camera on resume: $e');
          _initializeCamera();
        }
      }
    } catch (e) {
      debugPrint('Lifecycle camera handling error: $e');
    }
  }

  // --- Image/Analysis Logic ---
  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);

    if (pickedFile != null) {
      final imageFile = File(pickedFile.path);
      await _analyzeProduct(imageFile);
    }
  }

  // NOTE: This handles the barcode scan toggle
  Future<void> _scanBarcodeAndAnalyze() async {
    debugPrint("Toggling to Barcode Scan Mode...");
    setState(() {
      _isBarcodeMode = true;
    });
  }

  // Toggle back to image mode
  Future<void> _switchToImageMode() async {
    try {
      // Stop the barcode scanner first
      if (_barcodeScannerController != null) {
        await _barcodeScannerController!.stop();
        debugPrint('🛑 Barcode scanner stopped');
      }
    } catch (e) {
      debugPrint('⚠️ Error stopping barcode scanner: $e');
    }

    setState(() {
      _isBarcodeMode = false;
    });

    // Always reinitialize camera when returning from barcode mode
    debugPrint('📷 Reinitializing camera after barcode mode...');

    // Dispose existing camera controller if any
    try {
      await _cameraController?.dispose();
      _cameraController = null;
      setState(() => _isCameraInitialized = false);
    } catch (e) {
      debugPrint('⚠️ Error disposing camera: $e');
    }

    // Reinitialize camera
    await _initializeCamera();
  }

  // Handle barcode detection
  Future<void> _handleBarcodeDetection(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty || _isLoading) return;

    final barcode = barcodes.first;
    if (barcode.rawValue == null) return;

    final barcodeValue = barcode.rawValue!;
    debugPrint("Barcode detected: $barcodeValue");

    setState(() => _isLoading = true);

    try {
      // Try to lookup from Open Food Facts or Open Beauty Facts
      final productData = await _lookupBarcode(barcodeValue);

      if (productData != null) {
        // Navigate to result screen
        setState(() {
          _isLoading = false;
          _isBarcodeMode = false;
        });
        _navigateToResultScreen(productData);
      } else {
        // Product not found - Show contribution dialog
        setState(() => _isLoading = false);
        if (mounted) {
          _showProductContributionDialog(barcodeValue);
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error looking up barcode: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Lookup product by barcode from Open Food Facts AND Open Beauty Facts
  Future<ProductAnalysisData?> _lookupBarcode(String barcode) async {
    try {
      // Try Open Food Facts first (for food products)
      debugPrint('🔍 Searching Open Food Facts for barcode: $barcode');
      var uri = Uri.parse(
        'https://world.openfoodfacts.org/api/v0/product/$barcode.json',
      );
      var resp = await http.get(uri).timeout(const Duration(seconds: 8));

      Map<String, dynamic>? json;
      Map<String, dynamic>? prod;
      // Database name available but not currently used
      // String database = 'Open Food Facts';

      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        json = jsonDecode(resp.body) as Map<String, dynamic>;
        if (json['status'] == 1) {
          prod = json['product'] as Map<String, dynamic>;
          debugPrint('✅ Product found in Open Food Facts');
        }
      }

      // If not found in Open Food Facts, try Open Beauty Facts
      if (prod == null) {
        debugPrint('🔍 Searching Open Beauty Facts for barcode: $barcode');
        uri = Uri.parse(
          'https://world.openbeautyfacts.org/api/v0/product/$barcode.json',
        );
        resp = await http.get(uri).timeout(const Duration(seconds: 8));

        if (resp.statusCode == 200 && resp.body.isNotEmpty) {
          json = jsonDecode(resp.body) as Map<String, dynamic>;
          if (json['status'] == 1) {
            prod = json['product'] as Map<String, dynamic>;
            debugPrint('✅ Product found in Open Beauty Facts');
          }
        }
      }

      // If still not found, return null
      if (prod == null) {
        debugPrint('❌ Product not found in either database');
        return null;
      }

      String name =
          (prod['product_name'] as String?) ??
          (prod['brands'] as String?) ??
          'Unknown Product';
      String ingredients = (prod['ingredients_text'] as String?) ?? 'N/A';
      String packaging =
          (prod['packaging'] as String?) ??
          (prod['packaging_tags'] != null
              ? (prod['packaging_tags'] as List).join(', ')
              : 'N/A');
      String eco =
          (prod['ecoscore_grade'] as String?) ??
          (prod['environment_impact_grade'] as String?) ??
          'N/A';

      final ingredientsLower = ingredients.toLowerCase();
      final containsMicroplastics = RegExp(
        r'polyethylene|polypropylene|polymethyl|polystyrene|microplastic',
      ).hasMatch(ingredientsLower);
      final palmOilDerivative =
          ingredientsLower.contains('palm') ||
          ingredientsLower.contains('palmitate') ||
          ingredientsLower.contains('palmitic');

      bool crueltyFree = false;
      if (prod['labels_tags'] is List) {
        final labels = (prod['labels_tags'] as List)
            .map((e) => e.toString().toLowerCase())
            .toList();
        crueltyFree = labels.any(
          (l) =>
              l.contains('cruelty') ||
              l.contains('not-tested-on-animals') ||
              l.contains('no-animal-testing'),
        );
      }

      // Safely derive carbon footprint and disposal method from available product fields,
      // falling back to sensible defaults when data is missing.
      final carbonFootprint =
          (prod['carbon_footprint'] as String?) ??
          (prod['environment_impact'] as String?) ??
          'N/A';
      final disposalMethod =
          (prod['disposal'] as String?) ??
          (prod['recycling_instructions'] as String?) ??
          // If packaging indicates common recyclable materials, provide a generic hint
          ((prod['packaging_tags'] is List &&
                  (prod['packaging_tags'] as List).any(
                    (t) => t.toString().toLowerCase().contains('recycl'),
                  ))
              ? 'Check local recycling guidelines'
              : 'N/A');

      final analysis = ProductAnalysisData(
        imageFile: null,
        imageUrl:
            (prod['image_front_url'] as String?) ??
            (prod['image_url'] as String?),
        productName: name,
        category: (prod['categories'] as String?) ?? 'N/A',
        ingredients: ingredients,
        carbonFootprint: carbonFootprint,
        packagingType: packaging,
        disposalMethod: disposalMethod,
        containsMicroplastics: containsMicroplastics,
        palmOilDerivative: palmOilDerivative,
        crueltyFree: crueltyFree,
        ecoScore: eco,
      );

      return analysis;
    } catch (e) {
      debugPrint('Barcode lookup error: $e');
      return null;
    }
  }

  // NOTE: This handles the top-right button tap (now Capture)
  Future<void> _capturePicture() async {
    debugPrint("Triggering Picture Capture (Top Right Button Tapped)...");

    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final XFile file = await _cameraController!.takePicture();
        final imageFile = File(file.path);
        await _analyzeProduct(imageFile);
      } catch (e) {
        debugPrint("Error taking picture: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to capture image: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        // Fallback to gallery picker
        await _pickImage(ImageSource.gallery);
      }
    } else {
      // Camera not initialized, fallback to gallery/camera picker
      debugPrint("Camera not initialized, using image picker...");
      await _pickImage(ImageSource.camera);
    }
  }

  // Show dialog to request user contribution for unknown product
  Future<void> _showProductContributionDialog(String barcode) async {
    final formKey = GlobalKey<FormState>();
    final productNameController = TextEditingController();
    final categoryController = TextEditingController();
    final ingredientsController = TextEditingController();
    final brandController = TextEditingController();

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.help_outline, color: Colors.orange, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Product Not Found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This product (Barcode: $barcode) is not in our database.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kPrimaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kPrimaryGreen.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.volunteer_activism,
                        color: kPrimaryGreen,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Help us by adding it! Earn 30 eco points',
                              style: TextStyle(
                                color: kPrimaryGreen,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Limit: 3 per day, 10 per week',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Product Name Field
                TextFormField(
                  controller: productNameController,
                  decoration: InputDecoration(
                    labelText: 'Product Name *',
                    hintText: 'e.g., Organic Shampoo',
                    prefixIcon: Icon(Icons.shopping_bag, color: kPrimaryGreen),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kPrimaryGreen, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Product name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Brand Field
                TextFormField(
                  controller: brandController,
                  decoration: InputDecoration(
                    labelText: 'Brand (Optional)',
                    hintText: 'e.g., Green & Clean',
                    prefixIcon: Icon(Icons.business, color: kPrimaryGreen),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kPrimaryGreen, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Category Field
                TextFormField(
                  controller: categoryController,
                  decoration: InputDecoration(
                    labelText: 'Category *',
                    hintText: 'e.g., Personal Care, Food, etc.',
                    prefixIcon: Icon(Icons.category, color: kPrimaryGreen),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kPrimaryGreen, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Category is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Ingredients Field
                TextFormField(
                  controller: ingredientsController,
                  decoration: InputDecoration(
                    labelText: 'Ingredients (Optional)',
                    hintText: 'List main ingredients',
                    prefixIcon: Icon(Icons.list_alt, color: kPrimaryGreen),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kPrimaryGreen, width: 2),
                    ),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                Text(
                  '* Required fields',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _isBarcodeMode = false);
            },
            child: Text('Skip', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                // Save contribution
                await _saveProductContribution(
                  barcode: barcode,
                  productName: productNameController.text.trim(),
                  brand: brandController.text.trim(),
                  category: categoryController.text.trim(),
                  ingredients: ingredientsController.text.trim(),
                );
                Navigator.of(context).pop();
                setState(() => _isBarcodeMode = false);
              }
            },
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Submit & Earn 30 Points'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Save user contribution to Firestore and award points
  Future<void> _saveProductContribution({
    required String barcode,
    required String productName,
    required String brand,
    required String category,
    required String ingredients,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please sign in to contribute')),
          );
        }
        return;
      }

      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );
      }

      // Try to award eco points first (this checks daily/weekly limits)
      try {
        await FirebaseService().addEcoPoints(
          points: 30,
          reason: 'Added new product: $productName',
          activityType: 'add_new_product',
        );

        // Save to user_contributions collection
        await FirebaseFirestore.instance.collection('user_contributions').add({
          'barcode': barcode,
          'productName': productName,
          'brand': brand,
          'category': category,
          'ingredients': ingredients,
          'contributedBy': user.uid,
          'contributedAt': FieldValue.serverTimestamp(),
          'status': 'pending', // Can be reviewed by admin later
        });
      } catch (e) {
        // Close loading dialog if open
        if (mounted) {
          Navigator.of(context).pop();
        }

        // Check if it's a limit error
        final errorMessage = e.toString();
        if (errorMessage.contains('Activity limit') ||
            errorMessage.contains('daily limit') ||
            errorMessage.contains('weekly limit')) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    const Text('Limit Reached'),
                  ],
                ),
                content: const Text(
                  'You have reached the submission limit for adding new products.\n\n'
                  'Limits:\n'
                  '• 3 submissions per day\n'
                  '• 10 submissions per week\n\n'
                  'Please try again tomorrow or next week.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
          return;
        } else {
          rethrow; // Re-throw other errors
        }
      }

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Show success dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kPrimaryGreen.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: kPrimaryGreen,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Thank You!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your contribution helps build a better database for everyone!',
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kPrimaryGreen.withOpacity(0.1),
                        kPrimaryGreen.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.eco, color: kPrimaryGreen, size: 28),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '+30 Eco Points',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: kPrimaryGreen,
                            ),
                          ),
                          Text(
                            'Added to your account',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  // Navigate to home screen
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }

      debugPrint('✅ Product contribution saved and 30 points awarded');
    } catch (e) {
      debugPrint('❌ Error saving contribution: $e');

      // Close loading dialog if open
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save contribution: $e')),
        );
      }
    }
  }

  // ... (analyze, navigate, save, showActionSheet methods remain unchanged) ...
  Future<void> _analyzeImage(File imageFile) async {
    setState(() {
      _isLoading = true;
    });

    ProductAnalysisData analysisData;
    try {
      if (_geminiApiKey.isEmpty) {
        throw Exception(
          "Gemini API key not found. Please check your .env file.",
        );
      }

      final model = GenerativeModel(
        model: 'models/gemini-2.5-pro',
        apiKey: _geminiApiKey,
      );

      final imageBytes = await imageFile.readAsBytes();

      // **CRUCIAL: Prompt updated to enforce parsable output format**
      const prompt = """
You are an eco-expert AI. Analyze the uploaded product image and describe clearly, exactly in this format. Provide 'N/A' if information is not visible or applicable.
Product name: [Product Name]
Category: [Product Category, e.g., Food & Beverages (F&B), Personal Care, Household Products, Electronics, Clothing & Accessories, Health & Medicine, Baby & Kids, Pet Supplies, Automotive, Home & Furniture]
Ingredients: [List of ingredients, comma-separated, e.g., Water, Zinc Oxide, etc.]
Eco-friendliness rating: [Single letter: A, B, C, D, or E. Use STRICT criteria: A=Excellent (organic, plastic-free, certified eco-labels), B=Good (minimal plastic, recyclable, eco certifications), C=Moderate (standard recyclable, conventional), D=Poor (excessive plastic, harmful ingredients), E=Very poor (single-use plastic, toxic, non-recyclable)]
Carbon Footprint: [Estimated CO2e per unit, e.g., 0.36 kg CO2e per unit]
Packaging type: [Material and recyclability, e.g., Plastic Tube - Recyclable (Type 4 - LDPE)]
Disposal method: [Suggested disposal, e.g., Rinse and recycle locally]
Contains microplastics? [Yes/No]
Palm oil derivative? [Yes/No (No trace/Contains)]
Cruelty-Free? [Yes/No (Certified by Leaping Bunny)]
Better Alternative Product (Higher Eco Score): [Name of an alternative product that belongs to the same category but has a better Eco-friendliness rating — e.g., from C to A or B. Include short reason why it’s better, e.g., “Uses biodegradable surfactants and recycled paper packaging.”]
      
STANDARDIZED ECO SCORE CRITERIA (MUST USE CONSISTENTLY):
- A: Excellent sustainability (organic, plastic-free, carbon-neutral, certified eco-labels like FSC, Leaping Bunny)
- B: Good sustainability (minimal plastic, recyclable packaging, some eco certifications, low environmental impact)
- C: Moderate sustainability (standard recyclable packaging, conventional ingredients, average carbon footprint)
- D: Poor sustainability (excessive plastic, non-recyclable materials, harmful ingredients, high carbon footprint)
- E: Very poor sustainability (single-use plastic, toxic ingredients, non-recyclable, very high environmental impact)

IMPORTANT: Apply the SAME eco score criteria consistently. A glass bottle product should always get the same score regardless of which screen analyzes it.
      """;

      final content = [
        Content.multi([TextPart(prompt), DataPart('image/jpeg', imageBytes)]),
      ];

      final response = await model.generateContent(content);
      final outputText = response.text ?? "No analysis result.";

      analysisData = ProductAnalysisData.fromGeminiOutput(
        outputText,
        imageFile: imageFile,
      );

      final uploadedImageUrl = await _saveScanToFirebase(
        imageFile,
        outputText,
        analysisData,
      );

      // If we have an uploaded URL from Cloudinary, attach it to the analysis data
      final analysisToShow = uploadedImageUrl != null
          ? analysisData.copyWith(imageUrl: uploadedImageUrl)
          : analysisData;

      _navigateToResultScreen(analysisToShow);
    } catch (e) {
      debugPrint('❌ Error analyzing image: $e');

      // Show user-friendly error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to analyze product: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _analyzeImage(imageFile),
            ),
          ),
        );
      }

      analysisData = ProductAnalysisData(
        productName: 'Analysis Error',
        ingredients: 'Failed to analyze product: $e',
        ecoScore: 'E',
      );
      _navigateToResultScreen(analysisData);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _analyzeProduct(File imageFile) async {
    await _analyzeImage(imageFile);
  }

  void _navigateToResultScreen(ProductAnalysisData analysisData) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultScreen(analysisData: analysisData),
      ),
    );
  }

  Future<String?> _saveScanToFirebase(
    File imageFile,
    String analysisText,
    ProductAnalysisData analysisData,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not logged in.");
      }

      // Upload image to Cloudinary via FirebaseService helper
      String? imageUrl;
      try {
        imageUrl = await FirebaseService().uploadScannedImage(
          file: imageFile,
          fileName: '${DateTime.now().millisecondsSinceEpoch}.jpg',
          onProgress: (transferred, total) {
            debugPrint('Scan upload progress: $transferred / $total');
          },
        );
      } catch (e) {
        debugPrint('Failed to upload scanned image to Cloudinary: $e');
        imageUrl = null;
      }

      // Persist using centralized FirebaseService so all per-user scan logic
      // (and any legacy writes) are handled in one place.
      try {
        await FirebaseService().saveUserScan(
          analysis: analysisText,
          productName: analysisData.productName,
          ecoScore: analysisData.ecoScore,
          carbonFootprint: analysisData.carbonFootprint,
          imageUrl: imageUrl,
          category: analysisData.category,
          ingredients: analysisData.ingredients,
          packagingType: analysisData.packagingType,
          disposalSteps: analysisData.disposalMethod
              .split('\n')
              .where((s) => s.trim().isNotEmpty)
              .toList(),
          tips: analysisData.tips,
          nearbyCenter: analysisData.nearbyCenter,
          containsMicroplastics: analysisData.containsMicroplastics,
          palmOilDerivative: analysisData.palmOilDerivative,
          crueltyFree: analysisData.crueltyFree,
        );
        debugPrint("✅ Scan saved to Firestore via FirebaseService.");

        // Award points for scanning a product
        try {
          await FirebaseService().addEcoPoints(
            points: 5,
            reason: 'Scanned product: ${analysisData.productName}',
            activityType: 'scan_product',
          );
          debugPrint('✅ Awarded 5 points for product scan');
        } catch (e) {
          debugPrint('⚠️ Failed to award scan points: $e');
        }
      } catch (e) {
        debugPrint("❌ Failed to save scan via FirebaseService: $e");
      }

      // Return the uploaded image URL (if any) so caller can show it immediately
      return imageUrl;
    } catch (e) {
      debugPrint("❌ Error saving to Firestore: $e");
      return null;
    }
  }

  // --- UI Builder Widgets ---

  // Barcode Scanner View
  Widget _buildBarcodeScanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.black, const Color(0xFF1a1a1a)],
        ),
      ),
      child: Stack(
        children: [
          // Mobile Scanner
          MobileScanner(
            controller: _barcodeScannerController,
            onDetect: _handleBarcodeDetection,
          ),

          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.5),
                ],
                stops: const [0.0, 0.2, 0.7, 1.0],
              ),
            ),
          ),

          // Scanner Frame
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.75,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: kPrimaryGreen.withOpacity(0.5),
                  width: 3,
                ),
              ),
              child: Stack(
                children: [
                  // Corner accents
                  ...List.generate(4, (index) {
                    return Positioned(
                      top: index < 2 ? -3 : null,
                      bottom: index >= 2 ? -3 : null,
                      left: index % 2 == 0 ? -3 : null,
                      right: index % 2 == 1 ? -3 : null,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          border: Border(
                            top: index < 2
                                ? BorderSide(color: kPrimaryGreen, width: 5)
                                : BorderSide.none,
                            bottom: index >= 2
                                ? BorderSide(color: kPrimaryGreen, width: 5)
                                : BorderSide.none,
                            left: index % 2 == 0
                                ? BorderSide(color: kPrimaryGreen, width: 5)
                                : BorderSide.none,
                            right: index % 2 == 1
                                ? BorderSide(color: kPrimaryGreen, width: 5)
                                : BorderSide.none,
                          ),
                          borderRadius: BorderRadius.only(
                            topLeft: index == 0
                                ? const Radius.circular(20)
                                : Radius.zero,
                            topRight: index == 1
                                ? const Radius.circular(20)
                                : Radius.zero,
                            bottomLeft: index == 2
                                ? const Radius.circular(20)
                                : Radius.zero,
                            bottomRight: index == 3
                                ? const Radius.circular(20)
                                : Radius.zero,
                          ),
                        ),
                      ),
                    );
                  }),

                  // Center content
                  Center(
                    child: _isLoading
                        ? Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: kPrimaryGreen.withOpacity(0.5),
                                width: 2,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: kPrimaryGreen,
                                  strokeWidth: 3,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  "Looking up product...",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.qr_code_scanner,
                                color: kPrimaryGreen.withOpacity(0.7),
                                size: 60,
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: kPrimaryGreen.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  'Scan product barcode',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Top Controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildModernControlButton(
                  icon: Icons.arrow_back,
                  label: 'Image Mode',
                  onTap: _switchToImageMode,
                ),
                _buildModernControlButton(
                  icon: Icons.flash_on,
                  label: 'Flash',
                  onTap: () {
                    _barcodeScannerController?.toggleTorch();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // B. Live Preview (_buildCameraView)
  Widget _buildCameraView() {
    // Show barcode scanner if in barcode mode
    if (_isBarcodeMode) {
      return _buildBarcodeScanner();
    }

    // Otherwise show regular camera for image recognition
    // ⚠️ UNCOMMENT this block for actual camera initialization check
    if (_cameraController == null || !_isCameraInitialized) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF1a1a1a), const Color(0xFF0a0a0a)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: kPrimaryGreen, strokeWidth: 3),
              const SizedBox(height: 20),
              Text(
                'Initializing Camera...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.black, const Color(0xFF1a1a1a)],
        ),
      ),
      width: double.infinity,
      child: Stack(
        children: [
          // Camera Preview with rounded corners effect
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: SizedBox.expand(child: CameraPreview(_cameraController!)),
            ),
          ),

          // Gradient overlay for better contrast
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.5),
                ],
                stops: const [0.0, 0.2, 0.7, 1.0],
              ),
            ),
          ),

          // Modern Scanner Frame with animated corners
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.width * 0.85 * 0.7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: kPrimaryGreen.withOpacity(0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryGreen.withOpacity(0.2),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Corner accents
                  ...List.generate(4, (index) {
                    return Positioned(
                      top: index < 2 ? -2 : null,
                      bottom: index >= 2 ? -2 : null,
                      left: index % 2 == 0 ? -2 : null,
                      right: index % 2 == 1 ? -2 : null,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          border: Border(
                            top: index < 2
                                ? BorderSide(color: kPrimaryGreen, width: 4)
                                : BorderSide.none,
                            bottom: index >= 2
                                ? BorderSide(color: kPrimaryGreen, width: 4)
                                : BorderSide.none,
                            left: index % 2 == 0
                                ? BorderSide(color: kPrimaryGreen, width: 4)
                                : BorderSide.none,
                            right: index % 2 == 1
                                ? BorderSide(color: kPrimaryGreen, width: 4)
                                : BorderSide.none,
                          ),
                          borderRadius: BorderRadius.only(
                            topLeft: index == 0
                                ? const Radius.circular(24)
                                : Radius.zero,
                            topRight: index == 1
                                ? const Radius.circular(24)
                                : Radius.zero,
                            bottomLeft: index == 2
                                ? const Radius.circular(24)
                                : Radius.zero,
                            bottomRight: index == 3
                                ? const Radius.circular(24)
                                : Radius.zero,
                          ),
                        ),
                      ),
                    );
                  }),

                  // Center content
                  Center(
                    child: _isLoading
                        ? Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: kPrimaryGreen.withOpacity(0.5),
                                width: 2,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: kPrimaryGreen,
                                  strokeWidth: 3,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  "Analyzing Product...",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Please wait",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: kPrimaryGreen.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: kPrimaryGreen.withOpacity(0.3),
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  Icons.qr_code_scanner,
                                  color: kPrimaryGreen,
                                  size: 48,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Container(
                              //   padding: const EdgeInsets.symmetric(
                              //     horizontal: 20,
                              //     vertical: 8,
                              //   ),
                              //   decoration: BoxDecoration(
                              //     color: Colors.black.withOpacity(0.6),
                              //     borderRadius: BorderRadius.circular(20),
                              //     border: Border.all(
                              //       color: kPrimaryGreen.withOpacity(0.3),
                              //       width: 1,
                              //     ),
                              //   ),
                              //   // child: Text(
                              //   //   'Position product here',
                              //   //   style: TextStyle(
                              //   //     color: Colors.white,
                              //   //     fontSize: 14,
                              //   //     fontWeight: FontWeight.w500,
                              //   //   ),
                              //   // ),
                              // ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Top Controls Bar - Redesigned
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildModernControlButton(
                  icon: _isFlashOn ? Icons.flash_on : Icons.flash_off,
                  label: _isFlashOn ? 'Flash On' : 'Flash Off',
                  onTap: () {
                    if (_cameraController != null &&
                        _cameraController!.value.isInitialized) {
                      setState(() {
                        _isFlashOn = !_isFlashOn;
                        _cameraController!.setFlashMode(
                          _isFlashOn ? FlashMode.torch : FlashMode.off,
                        );
                      });
                    }
                  },
                ),
              ],
            ),
          ),

          // Bottom Control Panel - Redesigned
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Instruction text
                // Container(
                //   margin: const EdgeInsets.symmetric(horizontal: 40),
                //   padding: const EdgeInsets.symmetric(
                //     horizontal: 20,
                //     vertical: 12,
                //   ),
                //   // decoration: BoxDecoration(
                //   //   color: Colors.black.withOpacity(0.7),
                //   //   borderRadius: BorderRadius.circular(25),
                //   //   border: Border.all(
                //   //     color: kPrimaryGreen.withOpacity(0.3),
                //   //     width: 1,
                //   //   ),
                //   // ),
                //   child: Row(
                //     mainAxisSize: MainAxisSize.min,
                //     children: [
                //       Icon(Icons.info_outline, color: kPrimaryGreen, size: 18),
                //       const SizedBox(width: 8),
                //       Text(
                //         'Align product within frame',
                //         style: TextStyle(
                //           color: Colors.white,
                //           fontSize: 13,
                //           fontWeight: FontWeight.w500,
                //         ),
                //       ),
                //     ],
                //   ),
                // ),
                const SizedBox(height: 24),

                // Action Buttons Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Gallery Button
                      _buildActionButton(
                        icon: Icons.photo_library_outlined,
                        label: 'Gallery',
                        onTap: () => _pickImage(ImageSource.gallery),
                      ),

                      // Capture Button (Large Center)
                      GestureDetector(
                        onTap: _capturePicture,
                        child: Container(
                          width: 75,
                          height: 75,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                kPrimaryGreen,
                                kPrimaryGreen.withOpacity(0.8),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: kPrimaryGreen.withOpacity(0.5),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),

                      // Barcode Scan Button
                      _buildActionButton(
                        icon: Icons.qr_code_scanner,
                        label: 'Barcode',
                        onTap: _scanBarcodeAndAnalyze,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Modern control button (for flash, etc.)
  Widget _buildModernControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Action button for bottom controls
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, color: Colors.white, size: 24)],
        ),
      ),
    );
  }

  // The main dark bottom section containing the logo, search, and help text
  Widget _buildScannerOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF1a1a1a), const Color(0xFF0f0f0f)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo and App Name - Redesigned
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: kPrimaryGreen.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kPrimaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: kPrimaryGreen.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Image.asset(
                    'assets/ecopilot_logo.png',
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Eco',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  'Pilot',
                  style: TextStyle(
                    color: kPrimaryGreen,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Search Instruction Text - More elegant
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app, color: kPrimaryGreen, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _isBarcodeMode
                        ? 'Scanning from Open Food Facts & Open Beauty Facts...'
                        : 'Scan image or barcode for eco-insights',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Search Bar - Modern redesign
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: kPrimaryGreen.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: TextField(
              onSubmitted: (query) {
                debugPrint("Search for product: $query");
              },
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search products...',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
                filled: true,
                fillColor: const Color(0xFF262626),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 24,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(
                    color: kPrimaryGreen.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(
                    color: kPrimaryGreen.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(color: kPrimaryGreen, width: 2),
                ),
                prefixIcon: Icon(Icons.search, color: kPrimaryGreen, size: 22),
                suffixIcon: Container(
                  margin: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    icon: Icon(
                      Icons.qr_code_scanner,
                      color: kPrimaryGreen,
                      size: 24,
                    ),
                    onPressed: _scanBarcodeAndAnalyze,
                    tooltip: 'Scan barcode',
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Quick Action Cards - Redesigned
          Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.eco,
                  title: 'Eco Score',
                  subtitle: 'Check rating',
                  color: kPrimaryGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.recycling,
                  title: 'Disposal',
                  subtitle: 'Learn how',
                  color: Colors.blue,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Help section - More compact and modern
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF262626),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: kPrimaryGreen.withOpacity(0.15),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kPrimaryGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.volunteer_activism,
                    color: kPrimaryGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Join Our Mission',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Help build a sustainable database',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: kPrimaryGreen.withOpacity(0.6),
                  size: 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Quick action card widget
  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  // --- Bottom Navigation Bar ---
  Widget _buildBottomNavBar() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedIndex,
      selectedItemColor: kPrimaryGreen,
      unselectedItemColor: Colors.grey,
      backgroundColor: Colors.black,
      onTap: (index) async {
        if (index == 0) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const HomeScreen()));
          return;
        }
        if (index == 1) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const alternative_screen.AlternativeScreen(),
            ),
          );
          return;
        }
        if (index == 2) {
          return; // Already on ScanScreen
        }
        if (index == 3) {
          Navigator.of(context).push(
            MaterialPageRoute(
              // ⬅️ CRUCIAL CHANGE HERE
              builder: (_) => const DisposalGuidanceScreen(productId: null),
            ),
          );
          return;
        }
        if (index == 4) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const profile_screen.ProfileScreen(),
            ),
          );
          return;
        }
      },
      items: const <BottomNavigationBarItem>[
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(
          icon: Icon(Icons.shopping_cart),
          label: 'Alternative',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.qr_code_scanner),
          label: 'Scan',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.delete_sweep),
          label: 'Dispose',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final navBarHeight = 56.0; // Approximate bottom nav bar height
    final availableHeight = screenHeight - navBarHeight;

    return Scaffold(
      drawer: const AppDrawer(),
      // Remove AppBar so camera view can go full height
      body: Column(
        children: [
          // 1. Camera View Area - Now takes 60% of available screen
          SizedBox(height: availableHeight * 0.6, child: _buildCameraView()),

          // 2. Scanner Overlay - Takes remaining 40%
          Expanded(child: SingleChildScrollView(child: _buildScannerOverlay())),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }
}
