import 'package:flutter/material.dart';
import '/auth/firebase_service.dart';
import 'package:ecopilot/utils/rank_utils.dart';
import '/utils/constants.dart'
    as constants; // Assumed location for kPrimaryGreen/kPrimaryYellow
import 'package:ecopilot/widgets/app_drawer.dart';
import 'package:ecopilot/widgets/bottom_navigation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';
import 'alternative_screen.dart';
import 'home_screen.dart';
import 'scan_screen.dart';
import 'disposal_guidance_screen.dart';
import 'leaderboard_screen.dart';
import 'eco_assistant_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseService _service = FirebaseService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _photoUrlController = TextEditingController();
  final _emailController = TextEditingController();
  // String _rank = 'Rookie'; // Placeholder for user rank
  bool _isSaving = false;
  int _ecoPoints = 0;
  Color _rankColor = constants.kRankGreenExplorer;

  // Recent activity list used to store results from the Scan screen
  final List<Map<String, dynamic>> _recentActivity = [];

  // State variables for photo upload preview and error handling
  bool _isUploading = false;
  Uint8List? _pickedImageBytes;
  String? _pickedFileName;
  String? _uploadError;
  double? _uploadProgress;

  @override
  void initState() {
    super.initState();
    // Initialize controllers with current Firebase user data
    final user = _service.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
      _photoUrlController.text = user.photoURL ?? '';
      _emailController.text = user.email ?? '';
      // Load rank for the user
      _loadUserRank();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload user rank whenever dependencies change (e.g., when navigating back)
    _loadUserRank();
  }

  Future<void> _loadUserRank() async {
    try {
      final user = _service.currentUser;
      if (user == null) return;

      // Get all-time eco points from user summary
      final summary = await _service.getUserSummary(user.uid);
      final points = (summary['ecoScore'] ?? summary['ecoPoints'] ?? 0) as int;

      final rankInfo = rankForPoints(points);
      if (!mounted) return;
      setState(() {
        _ecoPoints = points;
        // _rank = rankInfo.title;
        _rankColor = rankInfo.color;
      });
    } catch (e) {
      debugPrint('Error loading user rank: $e');
    }
  }
  // Rank logic moved to lib/utils/rank_utils.dart

  @override
  void dispose() {
    _nameController.dispose();
    _photoUrlController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // --- Photo Picking and Upload Logic ---

  Future<void> _pickImage() async {
    // Request permission on platforms that need it
    if (!kIsWeb) {
      // Request both common permissions to cover Android and iOS cases.
      // On iOS Permission.photos is used; on Android apps may need READ_EXTERNAL_STORAGE
      // or READ_MEDIA_IMAGES (Android 13+). Request both and continue if either is granted.
      final statuses = await [Permission.photos, Permission.storage].request();

      final photosGranted = statuses[Permission.photos]?.isGranted ?? false;
      final storageGranted = statuses[Permission.storage]?.isGranted ?? false;
      final photosPermDenied =
          statuses[Permission.photos]?.isPermanentlyDenied ?? false;
      final storagePermDenied =
          statuses[Permission.storage]?.isPermanentlyDenied ?? false;

      if (!photosGranted && !storageGranted) {
        if (photosPermDenied || storagePermDenied) {
          // If permission is permanently denied, prompt user to open app settings
          if (!mounted) return;
          final open = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Permission required'),
              content: const Text(
                'Photo access is permanently denied. Please open app settings to enable photo permissions.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
          if (open == true) {
            await openAppSettings();
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Permission denied to access photos'),
              ),
            );
          }
        }
        return;
      }
    }

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;

    // Read bytes for immediate local preview
    Uint8List bytes;
    if (kIsWeb) {
      bytes = await picked.readAsBytes();
    } else {
      bytes = await File(picked.path).readAsBytes();
    }

    setState(() {
      _isUploading = true;
      _pickedImageBytes = bytes;
      _pickedFileName = picked.name;
      _uploadError = null;
    });

    try {
      String url = await _service.uploadProfilePhoto(
        bytes: bytes,
        fileName: picked.name,
        onProgress: (transferred, total) {
          if (!mounted) return;
          setState(() {
            _uploadProgress = (total > 0) ? transferred / total : null;
          });
        },
      );

      _photoUrlController.text = url;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Photo uploaded')));
        // Clear local preview so the final network image loads
        setState(() {
          _pickedImageBytes = null;
          _uploadProgress = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadError = e.toString(); // Show retry button
          _uploadProgress = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _retryUpload() async {
    if (_pickedImageBytes == null) return;
    setState(() {
      _isUploading = true;
      _uploadError = null;
    });
    try {
      // Re-upload using the cached bytes and filename, show progress
      final url = await _service.uploadProfilePhoto(
        bytes: _pickedImageBytes,
        fileName: _pickedFileName,
        onProgress: (transferred, total) {
          if (!mounted) return;
          setState(() {
            _uploadProgress = (total > 0) ? transferred / total : null;
          });
        },
      );
      _photoUrlController.text = url;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Photo uploaded')));
        setState(() {
          _pickedImageBytes = null;
          _uploadError = null;
          _uploadProgress = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadError = e.toString();
          _uploadProgress = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Retry failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // --- Profile Saving Logic ---

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final newName = _nameController.text.trim();
      final newPhoto = _photoUrlController.text.trim();

      if (newName.isNotEmpty) await _service.updateDisplayName(newName);
      // This will update the photo URL in Firebase Auth
      if (newPhoto.isNotEmpty) await _service.updatePhotoUrl(newPhoto);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _openChangePassword() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
  }

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _service.currentUser;
    // Prioritize the newly uploaded URL, otherwise use existing network photo
    final photo = _photoUrlController.text.isNotEmpty
        ? _photoUrlController.text
        : user?.photoURL;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const AppDrawer(),
      body: CustomScrollView(
        slivers: [
          // Hero Header with Profile Picture
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: constants.kPrimaryGreen,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                children: [
                  // Lottie Animation Background
                  Positioned.fill(
                    child: Lottie.asset(
                      'assets/animations/eco_background.json',
                      repeat: true,
                      fit: BoxFit.cover,
                      animate: true,
                    ),
                  ),
                  // Gradient Overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          constants.kPrimaryGreen.withOpacity(0.85),
                          const Color(0xFF1B5E20).withOpacity(0.8),
                          constants.kPrimaryGreen.withOpacity(0.75),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                  // Decorative elements
                  _buildDecorativeElements(),
                  // Main content
                  _buildProfileHeader(),
                ],
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Upload Error Card
                    if (_uploadError != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.red.shade200,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Upload failed. Tap retry or cancel.',
                                style: TextStyle(
                                  color: Colors.red.shade900,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _retryUpload,
                              child: Text(
                                'Retry',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _pickedImageBytes = null;
                                  _uploadError = null;
                                  _uploadProgress = null;
                                });
                              },
                              child: const Text(
                                'Cancel',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Rank Card (Featured)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _rankColor.withOpacity(0.15),
                            _rankColor.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _rankColor.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _rankColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.emoji_events,
                                  color: _rankColor,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Your Rank',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      rankForPoints(_ecoPoints).title,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: _rankColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _rankColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '$_ecoPoints pts',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Progress to next tier
                          Builder(
                            builder: (ctx) {
                              final int points = _ecoPoints;
                              final currentRank = rankForPoints(points);
                              final isMaxRank = currentRank.maxPoints == null;

                              // Calculate progress to next rank
                              final int currentMin = currentRank.minPoints;
                              final int? currentMax = currentRank.maxPoints;

                              String nextRankTitle = 'Max Rank';
                              int pointsNeeded = 0;
                              double pct = 1.0;

                              if (!isMaxRank && currentMax != null) {
                                // Get next rank info
                                final nextRank = rankForPoints(currentMax + 1);
                                nextRankTitle = nextRank.title;
                                pointsNeeded = pointsToNextRank(points);

                                // Calculate progress percentage
                                final int range = currentMax - currentMin + 1;
                                final int relative = (points - currentMin)
                                    .clamp(0, range);
                                pct = (relative / range).clamp(0.0, 1.0);
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          isMaxRank
                                              ? '🎉 Maximum Rank Achieved'
                                              : 'Next: $nextRankTitle',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                      if (!isMaxRank)
                                        Text(
                                          '$pointsNeeded pts to go',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: LinearProgressIndicator(
                                      value: pct,
                                      minHeight: 10,
                                      backgroundColor: Colors.grey.shade200,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        _rankColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    isMaxRank
                                        ? '🎉 You\'ve reached the top!'
                                        : '${(pct * 100).toStringAsFixed(0)}% complete',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const LeaderboardScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.leaderboard, size: 18),
                              label: const Text('View Leaderboard'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _rankColor,
                                side: BorderSide(color: _rankColor),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Section Title
                    const Text(
                      'Account Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Name Field
                    _buildModernInfoCard(
                      icon: Icons.person_outline,
                      label: 'Full Name',
                      iconColor: Colors.blue,
                      contentWidget: TextFormField(
                        controller: _nameController,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                        // decoration: const InputDecoration(
                        //   hintText: 'Enter your name',
                        //   border: InputBorder.none,
                        //   isDense: true,
                        //   contentPadding: EdgeInsets.zero,
                        // ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Please enter a name'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Email Field (Read-only)
                    _buildModernInfoCard(
                      icon: Icons.email_outlined,
                      label: 'Email Address',
                      iconColor: Colors.purple,
                      contentWidget: Text(
                        _emailController.text,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Password Field
                    _buildModernInfoCard(
                      icon: Icons.lock_outline,
                      label: 'Password',
                      iconColor: Colors.orange,
                      contentWidget: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '••••••••••',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                              color: Colors.black87,
                              letterSpacing: 2,
                            ),
                          ),
                          TextButton(
                            onPressed: _openChangePassword,
                            child: Text(
                              'Change',
                              style: TextStyle(
                                color: constants.kPrimaryGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: (_isUploading || _isSaving)
                            ? null
                            : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: constants.kPrimaryGreen,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: constants.kPrimaryGreen
                              .withOpacity(0.6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 2,
                          shadowColor: constants.kPrimaryGreen.withOpacity(0.4),
                        ),
                        child: (_isUploading || _isSaving)
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check, size: 22),
                                  SizedBox(width: 12),
                                  Text(
                                    'Save Changes',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: constants.kPrimaryGreen.withOpacity(0.4),
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
          backgroundColor: constants.kPrimaryGreen,
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

  // Decorative Elements for Header
  Widget _buildDecorativeElements() {
    return Stack(
      children: [
        // Decorative circles pattern
        Positioned(
          top: -80,
          right: -80,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.08),
            ),
          ),
        ),
        Positioned(
          top: 100,
          right: 30,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.06),
            ),
          ),
        ),
        Positioned(
          bottom: 30,
          left: -40,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.07),
            ),
          ),
        ),
        Positioned(
          bottom: 80,
          right: 50,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 2,
              ),
            ),
          ),
        ),
        // Eco icons decoration
        Positioned(
          top: 60,
          left: 30,
          child: Icon(
            Icons.eco,
            size: 40,
            color: Colors.white.withOpacity(0.1),
          ),
        ),
        Positioned(
          bottom: 50,
          right: 40,
          child: Icon(
            Icons.recycling,
            size: 35,
            color: Colors.white.withOpacity(0.09),
          ),
        ),
        // Leaf pattern
        Positioned(
          top: 150,
          left: 60,
          child: Transform.rotate(
            angle: -0.5,
            child: Icon(
              Icons.nature,
              size: 30,
              color: Colors.white.withOpacity(0.08),
            ),
          ),
        ),
      ],
    );
  }

  // Profile Header Content
  Widget _buildProfileHeader() {
    final user = _service.currentUser;
    final photo = _photoUrlController.text.isNotEmpty
        ? _photoUrlController.text
        : user?.photoURL;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 60),
          // Profile Picture
          Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow effect
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
              ),
              // Avatar with border
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                ),
                child: ClipOval(
                  child: CircleAvatar(
                    radius: 63,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    backgroundImage: _pickedImageBytes != null
                        ? MemoryImage(_pickedImageBytes!)
                        : (photo != null && photo.isNotEmpty)
                        ? CachedNetworkImageProvider(photo)
                        : null,
                    child:
                        (_pickedImageBytes == null &&
                            (photo == null || photo.isEmpty))
                        ? const Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
              // Upload progress overlay
              if (_isUploading && _uploadProgress != null)
                Container(
                  width: 130,
                  height: 130,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 50,
                          height: 50,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: _uploadProgress,
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                              Text(
                                '${((_uploadProgress ?? 0) * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Edit button
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: constants.kPrimaryGreen,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _isUploading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: constants.kPrimaryGreen,
                              ),
                            ),
                          )
                        : Icon(
                            _uploadError != null
                                ? Icons.refresh
                                : Icons.camera_alt,
                            color: constants.kPrimaryGreen,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // User Name
          Text(
            _nameController.text.isEmpty ? 'User Name' : _nameController.text,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          // Email
          Text(
            _emailController.text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  // Modern Info Card Widget
  Widget _buildModernInfoCard({
    required IconData icon,
    required String label,
    required Widget contentWidget,
    required Color iconColor,
  }) {
    return Container(
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
              color: iconColor.withOpacity(0.1),
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
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                contentWidget,
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Profile tab index in the shared bottom navigation (0=Home,1=Alternative,2=Scan,3=Dispose,4=Profile)
  final int _selectedIndex = 4;

  Widget _buildBottomNavBar() {
    return AppBottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) async {
        // When the Home tab is tapped, open the Home screen.
        if (index == 0) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const HomeScreen()));
          return;
        }
        // When the Alternative tab is tapped, open the Alternative screen (or do nothing if already here).
        if (index == 1) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AlternativeScreen()));
          return;
        }
        // When Scan tab is tapped, open the ScanScreen and wait for result
        if (index == 2) {
          final result = await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ScanScreen()));

          if (result != null && result is Map<String, dynamic>) {
            // Add to recent activity list (basic shape for the home screen)
            setState(() {
              _recentActivity.insert(0, {
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
        // When the Profile tab is tapped, open the Profile screen.
        if (index == 4) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
          return;
        }
      },
    );
  }
}

// Change Password Screen - Modern Redesign
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  final FirebaseService _service = FirebaseService();

  // Password strength indicator
  double _passwordStrength = 0.0;
  String _passwordStrengthText = '';
  Color _passwordStrengthColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_checkPasswordStrength);
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _checkPasswordStrength() {
    final password = _passwordController.text;
    double strength = 0.0;
    String text = '';
    Color color = Colors.grey;

    if (password.isEmpty) {
      strength = 0.0;
      text = '';
    } else if (password.length < 6) {
      strength = 0.25;
      text = 'Weak';
      color = Colors.red;
    } else if (password.length < 8) {
      strength = 0.5;
      text = 'Fair';
      color = Colors.orange;
    } else if (password.length < 10 && password.contains(RegExp(r'[A-Z]'))) {
      strength = 0.75;
      text = 'Good';
      color = Colors.blue;
    } else if (password.length >= 10 &&
        password.contains(RegExp(r'[A-Z]')) &&
        password.contains(RegExp(r'[0-9]')) &&
        password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      strength = 1.0;
      text = 'Strong';
      color = Colors.green;
    } else {
      strength = 0.65;
      text = 'Good';
      color = Colors.lightGreen;
    }

    setState(() {
      _passwordStrength = strength;
      _passwordStrengthText = text;
      _passwordStrengthColor = color;
    });
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12),
              Text('Passwords do not match'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _service.updatePassword(_passwordController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('Password changed successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: constants.kPrimaryGreen),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back, color: constants.kPrimaryGreen),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),

                      // Header Icon
                      Center(
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                constants.kPrimaryGreen,
                                constants.kPrimaryGreen.withOpacity(0.7),
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: constants.kPrimaryGreen.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.lock_reset,
                            size: 50,
                            color: Colors.white,
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Title
                      const Center(
                        child: Text(
                          'Change Password',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Subtitle
                      Center(
                        child: Text(
                          'Create a strong password to keep\nyour account secure',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // New Password Field
                      _buildModernPasswordField(
                        controller: _passwordController,
                        label: 'New Password',
                        hint: 'Enter your new password',
                        isObscure: _obscurePassword,
                        onToggleVisibility: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (v.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),

                      // Password Strength Indicator
                      if (_passwordController.text.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: LinearProgressIndicator(
                                      value: _passwordStrength,
                                      minHeight: 6,
                                      backgroundColor: Colors.grey.shade200,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        _passwordStrengthColor,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _passwordStrengthText,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _passwordStrengthColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Use 10+ characters with a mix of letters, numbers & symbols',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Confirm Password Field
                      _buildModernPasswordField(
                        controller: _confirmController,
                        label: 'Confirm Password',
                        hint: 'Re-enter your password',
                        isObscure: _obscureConfirm,
                        onToggleVisibility: () {
                          setState(() => _obscureConfirm = !_obscureConfirm);
                        },
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (v != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 32),

                      // Security Tips Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.blue.shade100,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.blue.shade700,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Security Tips',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildSecurityTip('Use a unique password'),
                            _buildSecurityTip('Mix uppercase and lowercase'),
                            _buildSecurityTip('Include numbers and symbols'),
                            _buildSecurityTip('Avoid personal information'),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),

            // Change Password Button
            Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: 24 + MediaQuery.of(context).padding.bottom,
                top: 16,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: _isLoading
                  ? Center(
                      child: SizedBox(
                        height: 56,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: constants.kPrimaryGreen,
                            strokeWidth: 3,
                          ),
                        ),
                      ),
                    )
                  : SizedBox(
                      height: 56,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _changePassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: constants.kPrimaryGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                          shadowColor: constants.kPrimaryGreen.withOpacity(0.4),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline, size: 22),
                            SizedBox(width: 12),
                            Text(
                              'Update Password',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Modern Password Input Field
  Widget _buildModernPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool isObscure,
    required VoidCallback onToggleVisibility,
    required String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            obscureText: isObscure,
            validator: validator,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.normal,
              ),
              prefixIcon: Icon(
                Icons.lock_outline,
                color: constants.kPrimaryGreen,
                size: 22,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  isObscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.grey.shade600,
                  size: 22,
                ),
                onPressed: onToggleVisibility,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Security Tip Item
  Widget _buildSecurityTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.blue.shade600, size: 18),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.blue.shade900,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
