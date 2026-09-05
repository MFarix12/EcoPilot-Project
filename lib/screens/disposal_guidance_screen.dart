import 'package:ecopilot/screens/scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ecopilot/screens/disposal_scan_screen.dart';
import 'package:ecopilot/screens/barcode_scanner_screen.dart';
// Avoid importing kPrimaryGreen twice: hide it from the recent_disposal import
import 'package:ecopilot/screens/recent_disposal_screen.dart';
import 'package:ecopilot/utils/constants.dart';
import 'package:ecopilot/widgets/app_drawer.dart';
import 'package:ecopilot/widgets/bottom_navigation.dart';
import 'package:ecopilot/screens/home_screen.dart';
import 'package:ecopilot/screens/alternative_screen.dart';
import 'package:ecopilot/screens/profile_screen.dart';
import 'package:ecopilot/screens/eco_assistant_screen.dart';
import 'package:ecopilot/auth/firebase_service.dart';

/// Clean Disposal Guidance screen (hub + details).
class DisposalGuidanceScreen extends StatefulWidget {
  final String? productId;
  const DisposalGuidanceScreen({super.key, this.productId});

  @override
  State<DisposalGuidanceScreen> createState() => _DisposalGuidanceScreenState();
}

class _DisposalGuidanceScreenState extends State<DisposalGuidanceScreen> {
  bool _loading = true;
  Map<String, dynamic>? _product;
  int _selectedIndex = 3; // default to Dispose tab
  // Recent disposal list used when returning from ScanScreen (kept in memory for this view)
  final List<Map<String, dynamic>> _recentDisposal = [];

  // Location tracking for disposal confirmation
  bool _isAtDisposalCenter = false;
  bool _checkingLocation = false;
  Position? _currentPosition;
  bool _disposalCompleted = false;

  static const Map<String, dynamic> _defaultData = {
    'name': 'General Recycling Guidance',
    'category': 'General Household Item',
    'material': 'Plastic / Mixed',
    'ecoScore': 'B',
    'imageUrl':
        'https://placehold.co/600x800/A8D8B9/212121?text=Placeholder+Image',
    'disposalSteps': [
      'Separate plastics, paper, and glass.',
      'Rinse containers thoroughly before recycling.',
      'Flatten cardboard boxes.',
      'Check local guidelines for battery disposal.',
    ],
    'tips': [
      'Always aim to reuse items before recycling.',
      'Composting food waste significantly reduces landfill volume.',
    ],
  };

  @override
  void initState() {
    super.initState();
    if (widget.productId != null && widget.productId != 'general_fallback') {
      _loadProduct();
    } else {
      _product = _defaultData;
      _loading = false;
    }
  }

  Future<void> _loadProduct() async {
    setState(() {
      _loading = true;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('scans')
          .doc(widget.productId)
          .get();
      if (!doc.exists) {
        _product = _defaultData;
        // specific product guidance not found, continue with general tips
      } else {
        // Normalize various possible field names written by different save flows
        final raw = doc.data();
        if (raw != null) {
          final Map<String, dynamic> norm = Map<String, dynamic>.from(raw);

          // Common legacy -> canonical mappings
          if (norm['name'] == null && norm['product_name'] != null) {
            norm['name'] = norm['product_name'];
          }
          if (norm['ecoScore'] == null && norm['eco_score'] != null) {
            norm['ecoScore'] = norm['eco_score'];
          }
          if (norm['imageUrl'] == null && norm['image_url'] != null) {
            norm['imageUrl'] = norm['image_url'];
          }
          if (norm['material'] == null && norm['packaging'] != null) {
            norm['material'] = norm['packaging'];
          }
          if (norm['createdAt'] == null && norm['timestamp'] != null) {
            norm['createdAt'] = norm['timestamp'];
          }

          // Normalize lists that might be stored as strings
          norm['disposalSteps'] = _ensureList(norm['disposalSteps']);
          norm['tips'] = _ensureList(norm['tips']);

          _product = norm;

          _product!['name'] = _product!['name'] ?? 'Scanned Item';
          _product!['category'] = _product!['category'] ?? 'General';
          _product!['material'] = _product!['material'] ?? 'Unknown';

          // Check if disposal has already been completed for this product
          if (norm['disposalCompleted'] == true) {
            _disposalCompleted = true;
          }
        }
      }
    } catch (e) {
      _product = _defaultData;
      // failed to load product – show general tips
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Normalize various firestore field shapes into a List for safe UI iteration.
  List<dynamic> _ensureList(dynamic value) {
    if (value == null) return <dynamic>[];
    if (value is List) return value;
    if (value is Iterable) return value.toList();
    if (value is String) {
      // Try common delimiters (newline or comma) to split multi-line/string stored lists.
      if (value.contains('\n')) {
        return value
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (value.contains(',')) {
        return value
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      return <dynamic>[value];
    }
    // Fallback: wrap single scalar values
    return <dynamic>[value];
  }

  Future<void> _openMapsForRecycling([
    String query = 'recycling center near me',
  ]) async {
    final mapsUrl =
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}';
    final url = Uri.parse(mapsUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open maps.')));
      }
    }
  }

  // Check if user's current location is near a disposal center
  Future<void> _checkLocationProximity() async {
    if (_checkingLocation) return;

    setState(() {
      _checkingLocation = true;
    });

    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Location permission is required to confirm disposal',
                ),
              ),
            );
          }
          setState(() {
            _checkingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is permanently denied'),
            ),
          );
        }
        setState(() {
          _checkingLocation = false;
        });
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _currentPosition = position;

      // For demonstration: Consider user is "at disposal center" if accuracy is good
      // In production, you would check distance to known disposal centers
      // Using a proximity threshold of 100 meters for this implementation
      // You can integrate with Google Places API to get actual disposal center locations

      // Simulated check: User is considered at disposal center if location accuracy is < 50m
      // This is a placeholder - in production, calculate distance to nearest disposal center
      bool isNearby = position.accuracy < 100;

      setState(() {
        _isAtDisposalCenter = isNearby;
        _checkingLocation = false;
      });

      if (mounted) {
        if (isNearby) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ You are near a disposal center'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please move closer to a disposal center'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Location error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to get location: $e')));
      }
      setState(() {
        _checkingLocation = false;
      });
    }
  }

  // Complete disposal and award eco points
  Future<void> _completeDisposal() async {
    if (!_isAtDisposalCenter || _disposalCompleted) return;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please sign in to earn eco points')),
          );
        }
        return;
      }

      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );
      }

      // Award 10 eco points using FirebaseService (updates all three categories)
      // Base disposal: 10 points, Verified location bonus: 5 points = 15 total
      await FirebaseService().addEcoPoints(
        points: 10,
        reason: 'Product disposal completed',
        activityType: 'dispose_product',
      );

      // Award verified disposal bonus if location is available
      if (_currentPosition != null) {
        await FirebaseService().addEcoPoints(
          points: 5,
          reason: 'Verified disposal with location',
          activityType: 'verified_disposal_bonus',
        );
      }

      // Mark product as disposed
      if (widget.productId != null && widget.productId != 'general_fallback') {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('scans')
            .doc(widget.productId)
            .update({
              'disposalCompleted': true,
              'disposalCompletedAt': FieldValue.serverTimestamp(),
              'disposalLocation': {
                'latitude': _currentPosition?.latitude,
                'longitude': _currentPosition?.longitude,
                'accuracy': _currentPosition?.accuracy,
              },
            });
      }

      setState(() {
        _disposalCompleted = true;
      });

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
                  child: const Icon(
                    Icons.check_circle,
                    color: kPrimaryGreen,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Disposal Complete!',
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
                  'Great job! You\'ve properly disposed of this item.',
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
                      const Icon(Icons.eco, color: kPrimaryGreen, size: 28),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '+10 Eco Points',
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
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop(); // Go back to previous screen
                },
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Disposal completion error: $e');

      // Close loading dialog if open
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to complete disposal: $e')),
        );
      }
    }
  }

  Future<void> _handleScanResult(dynamic result) async {
    if (result == null || result is! Map<String, dynamic>) return;
    final Map<String, dynamic> product = Map<String, dynamic>.from(result);
    final String productId =
        (product['productId'] ??
                product['id'] ??
                DateTime.now().millisecondsSinceEpoch.toString())
            .toString();
    product['productId'] = productId;
    await _saveScannedProduct(product);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DisposalGuidanceScreen(productId: productId),
        ),
      );
    }
  }

  Future<void> _saveScannedProduct(Map<String, dynamic> product) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('scans')
          .doc(product['productId'].toString());
      await docRef.set({
        'name': product['name'] ?? 'Scanned product',
        'category': product['category'] ?? 'General',
        'ecoScore': product['ecoScore'] ?? 'N/A',
        'imageUrl': product['imageUrl'] ?? '',
        'material': product['material'] ?? 'Unknown',
        // Ensure lists are stored as arrays in Firestore regardless of incoming shape
        'disposalSteps': _ensureList(
          product['disposalSteps'],
        ).map((e) => e.toString()).toList(),
        'tips': _ensureList(product['tips']).map((e) => e.toString()).toList(),
        // Persist boolean warning flags when available, default to false
        'containsMicroplastics': product['containsMicroplastics'] ?? false,
        'palmOilDerivative': product['palmOilDerivative'] ?? false,
        'crueltyFree': product['crueltyFree'] ?? false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to save scan: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save scan: $e')));
      }
    }
  }

  Widget _buildDisposalHub() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.grey.shade50, Colors.white],
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Section with Gradient Background
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: kPrimaryGreen,
                // gradient: LinearGradient(
                //   begin: Alignment.topLeft,
                //   end: Alignment.bottomRight,
                //   colors: [kPrimaryGreen, kPrimaryGreen.withOpacity(0.8)],
                // ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.recycling, size: 48, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    'Disposal Hub',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan products to learn proper disposal methods',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.95),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Quick Actions Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Main Scan Card (Featured)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          kPrimaryGreen.withOpacity(0.1),
                          kPrimaryGreen.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: kPrimaryGreen.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          final result = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DisposalScanScreen(),
                            ),
                          );
                          if (result != null) await _handleScanResult(result);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: kPrimaryGreen,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kPrimaryGreen.withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Scan Product',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Use camera to identify materials',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                color: kPrimaryGreen,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Secondary Action Cards Grid
                  Row(
                    children: [
                      // Recent Disposal Card
                      Expanded(
                        child: Container(
                          height: 140,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RecentDisposalScreen(),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: Colors.purple.shade50,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        Icons.history,
                                        color: Colors.purple.shade400,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Recent',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'View history',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Search Card
                      Expanded(
                        child: Container(
                          height: 140,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const BarcodeScannerScreen(),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        Icons.qr_code_scanner,
                                        color: Colors.blue.shade400,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Barcode',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Scan product',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Tips Section
                  const Text(
                    'Disposal Tips',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildTipCard(
                    icon: Icons.emoji_nature,
                    iconColor: Colors.green,
                    iconBg: Colors.green.shade50,
                    title: 'Rinse Before Recycling',
                    description: 'Clean containers prevent contamination',
                  ),
                  _buildTipCard(
                    icon: Icons.layers,
                    iconColor: Colors.orange,
                    iconBg: Colors.orange.shade50,
                    title: 'Separate Materials',
                    description: 'Keep different materials sorted',
                  ),
                  _buildTipCard(
                    icon: Icons.lightbulb_outline,
                    iconColor: Colors.amber,
                    iconBg: Colors.amber.shade50,
                    title: 'Check Local Guidelines',
                    description: 'Rules vary by location',
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String description,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidanceDetail(BuildContext context) {
    final productData = _product!;
    final String name = productData['name'] ?? 'Unknown Item';
    final String category = productData['category'] ?? 'N/A';
    final String material = productData['material'] ?? 'N/A';
    final String ecoScore =
        (productData['ecoScore'] ?? productData['eco_score'] ?? 'N/A')
            .toString()
            .toUpperCase();
    final List disposalSteps = _ensureList(productData['disposalSteps']);
    final List tips = _ensureList(productData['tips']);
    final String imageUrl =
        productData['imageUrl'] ?? productData['image_url'] ?? '';

    // Get eco score color using theme colors
    Color getScoreColor(String score) {
      final ecoScoreColors = {
        'A': kResultCardGreen,
        'B': kDiscoverMoreGreen,
        'C': kPrimaryYellow,
        'D': kRankSustainabilityHero,
        'E': kWarningRed,
      };
      final firstChar = score.isNotEmpty ? score[0].toUpperCase() : 'N';
      return ecoScoreColors[firstChar] ?? Colors.grey.shade600;
    }

    return CustomScrollView(
      slivers: [
        // Hero Image Section with SliverAppBar
        SliverAppBar(
          expandedHeight: 320,
          pinned: true,
          backgroundColor: kPrimaryGreen,
          iconTheme: const IconThemeData(color: Colors.white),
          automaticallyImplyLeading: false,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                // Product Image
                if (imageUrl.isNotEmpty)
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: Icon(
                        Icons.recycling,
                        size: 100,
                        color: kPrimaryGreen.withOpacity(0.3),
                      ),
                    ),
                  )
                else
                  Container(
                    color: Colors.grey.shade200,
                    child: Icon(
                      Icons.recycling,
                      size: 100,
                      color: kPrimaryGreen.withOpacity(0.3),
                    ),
                  ),

                // Gradient Overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                ),

                // Product Name and Category Badge
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 80,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black45,
                              offset: Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: kPrimaryGreen,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.category,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              category,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Eco Score Badge (Circular)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          ecoScore,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: getScoreColor(ecoScore),
                          ),
                        ),
                        Text(
                          'ECO SCORE',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Content Section
        SliverToBoxAdapter(
          child: Container(
            color: Colors.grey.shade50,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Material Composition Card (Blue)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFBBDEFB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          color: Color(0xFF1976D2),
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Material Composition',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              material,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Disposal Steps Section
                Row(
                  children: [
                    const Icon(
                      Icons.playlist_add_check_rounded,
                      color: kPrimaryGreen,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Disposal Steps',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (disposalSteps.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Center(
                      child: Text(
                        'No disposal steps available',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  )
                else
                  ...disposalSteps.asMap().entries.map((entry) {
                    final index = entry.key;
                    final step = entry.value.toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: kPrimaryGreen,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              step,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                const SizedBox(height: 24),

                // Pro Tips Section
                if (tips.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb,
                            color: Colors.amber.shade700,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Eco Tips',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ...tips.map((tip) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.amber.shade200,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.stars,
                                  color: Colors.amber.shade700,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  tip.toString(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade800,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 24),
                    ],
                  ),

                // Recycling Center Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade200, width: 1),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: kPrimaryGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.location_on,
                          size: 36,
                          color: kPrimaryGreen,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Find Nearby Recycling Centers',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Locate the nearest facility for proper disposal',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _openMapsForRecycling('recycling center near me'),
                          icon: const Icon(
                            Icons.navigation,
                            size: 20,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Open in Maps',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Done Disposal Button Section
                if (!_disposalCompleted) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _isAtDisposalCenter
                            ? [
                                kPrimaryGreen.withOpacity(0.1),
                                kPrimaryGreen.withOpacity(0.05),
                              ]
                            : [Colors.grey.shade50, Colors.grey.shade100],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isAtDisposalCenter
                            ? kPrimaryGreen.withOpacity(0.3)
                            : Colors.grey.shade300,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _isAtDisposalCenter
                              ? Icons.check_circle
                              : Icons.location_searching,
                          size: 48,
                          color: _isAtDisposalCenter
                              ? kPrimaryGreen
                              : Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isAtDisposalCenter
                              ? 'You\'re at a disposal center!'
                              : 'Location Check Required',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _isAtDisposalCenter
                                ? kPrimaryGreen
                                : Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isAtDisposalCenter
                              ? 'Tap below to confirm disposal and earn 10 eco points'
                              : 'Please go to a disposal center and check your location',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        // Check Location Button
                        if (!_isAtDisposalCenter)
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _checkingLocation
                                  ? null
                                  : _checkLocationProximity,
                              icon: _checkingLocation
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.my_location,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                              label: Text(
                                _checkingLocation
                                    ? 'Checking...'
                                    : 'Check My Location',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 2,
                              ),
                            ),
                          ),

                        // Done Disposal Button
                        if (_isAtDisposalCenter)
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton.icon(
                              onPressed: _completeDisposal,
                              icon: const Icon(
                                Icons.verified,
                                size: 24,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Done Disposal (+10 Points)',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimaryGreen,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 4,
                                shadowColor: kPrimaryGreen.withOpacity(0.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],

                // Disposal Completed Message
                if (_disposalCompleted)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.green.shade50, Colors.green.shade100],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.green.shade300,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Disposal Completed! ✓',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'You earned 10 eco points',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavBar() {
    return AppBottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) async {
        if (index == 0) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const HomeScreen()));
          return;
        }
        if (index == 1) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AlternativeScreen()));
          return;
        }
        if (index == 2) {
          final result = await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ScanScreen()));

          if (result != null && result is Map<String, dynamic>) {
            // Add to recent disposal list (basic shape for the home screen)
            setState(() {
              _recentDisposal.insert(0, {
                'product': result['product'] ?? 'Scanned product',
                'score':
                    result['raw'] != null &&
                        result['raw']['ecoscore_score'] != null
                    ? (result['raw']['ecoscore_score'].toString())
                    : 'N/A',
                'co2':
                    result['raw'] != null &&
                        result['raw']['carbon_footprint'] != null
                    ? result['raw']['carbon_footprint'].toString()
                    : '—',
              });
            });
          }

          return;
        }
        if (index == 3) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DisposalGuidanceScreen()),
          );
          return;
        }
        if (index == 4) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
          return;
        }
        setState(() {
          _selectedIndex = index;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showDetail = widget.productId != null && !_loading;

    return Scaffold(
      drawer: showDetail ? null : const AppDrawer(),
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        centerTitle: true,
        // Show drawer on the hub, but show a back button on the details view
        leading: showDetail
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  // Navigate back to previous screen (Recent Disposal)
                  Navigator.of(context).pop();
                },
              )
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        title: Text(
          showDetail ? 'Disposal Details' : 'Disposal Guidance',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : showDetail
          ? _buildGuidanceDetail(context)
          : _buildDisposalHub(),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: kPrimaryGreen.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EcoAssistantScreen()),
            );
          },
          backgroundColor: kPrimaryGreen,
          icon: Container(
            padding: const EdgeInsets.all(6),
            child: Image.asset(
              'assets/chatbot.png',
              width: 40,
              height: 40,
              color: Colors.white,
            ),
          ),
          label: const Text(
            'EcoBot',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }
}
