import 'dart:async';
import 'package:ecopilot/screens/disposal_guidance_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Required for date formatting
import 'package:share_plus/share_plus.dart';
import '../auth/firebase_service.dart';
import 'profile_screen.dart';
import 'better_alternative_screen.dart';
import 'alternative_screen.dart' as alt_screen;
import '/screens/scan_screen.dart';
import 'notification_screen.dart';
import 'recent_activity_screen.dart';
import 'eco_assistant_screen.dart';
import 'package:ecopilot/utils/constants.dart';
import 'package:ecopilot/utils/challenge_generator.dart';
import 'package:ecopilot/utils/tip_generator.dart';
import 'package:ecopilot/widgets/app_drawer.dart';
import 'package:ecopilot/widgets/bottom_navigation.dart';
import 'package:ecopilot/models/product_analysis_data.dart';
import 'daily_challenge_screen.dart';

// Placeholder data structure for challenge and user progress
class DailyChallenge {
  final String title;
  final int points;
  final bool isCompleted;

  DailyChallenge(this.title, this.points, this.isCompleted);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _userName = 'User';

  // Image slider state
  int _currentSlideIndex = 0;
  Timer? _sliderTimer;
  // Initialize at a large starting position for infinite scroll effect
  late final PageController _pageController;
  final List<String> _sliderImages = [
    'assets/slider1.jpg',
    'assets/slider2.jpg',
    'assets/slider3.jpg',
  ];
  // Large number to simulate infinite scrolling
  static const int _infiniteScrollOffset = 10000;

  // 🚫 REMOVED: String _tip = 'Loading tip...'; // Replaced by FutureBuilder

  // Use a map to store challenge data to simplify state updates on the home screen
  DailyChallenge? _dailyChallenge;
  // Fallback challenge text (legacy code expected `_challenge`)
  final String _challenge = 'Challenge yourself';
  // Recent activity list used by the bottom nav scan flow (legacy callers expect `_recentActivity`)
  final List<Map<String, dynamic>> _recentActivity = <Map<String, dynamic>>[];
  int _userStreak = 0;
  final int _selectedIndex = 0; // For Bottom Navigation Bar

  // Monthly Eco Points tracking
  int _monthlyEcoPoints = 0;
  int _monthlyGoal = 500; // Default monthly goal

  // Tip tracking state
  String _currentTip = '';
  String _currentTipCategory = '';
  bool _isTipBookmarked = false;
  String _todayDateString = '';

  // Cache the future to prevent rebuilds
  late Future<Map<String, String>> _tipFuture;

  // Use theme colors from constants
  final primaryGreen = const Color(0xFF4CAF50);
  final yellowAccent = const Color(0xFFFFEB3B);

  // --- NEW: Tip Fetch Logic ---
  Future<Map<String, String>> _fetchTodayTip() async {
    // 1. Get today's date string
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      // 2. First, ensure today's tip exists in Firestore
      await TipGenerator.ensureTodayTipExists();

      // 3. Fetch the tip for that date from Firestore
      final doc = await FirebaseFirestore.instance
          .collection('daily_tips')
          .doc(today)
          .get();

      // 4. If it exists, return the tip field and category
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return {
          'tip': data['tip'] as String? ?? 'No eco tips available today 🌍',
          'category': data['category'] as String? ?? 'eco_habits',
        };
      } else {
        // If still not found after ensuring it exists, generate one directly
        debugPrint(
          '⚠️ Tip document not found after ensuring exists, generating directly',
        );
        final tip = TipGenerator.generateDailyTip(DateTime.now());
        return {
          'tip': tip['tip'] as String? ?? 'No eco tips available today 🌍',
          'category': tip['category'] as String? ?? 'eco_habits',
        };
      }
    } catch (e) {
      debugPrint('Error fetching tip: $e');
      // Return a generic tip instead of error message
      return {
        'tip':
            '🌱 Small changes make a big difference! Start your eco journey today.',
        'category': 'eco_habits',
      };
    }
  }

  @override
  void initState() {
    super.initState();
    // Initialize PageController at middle position for infinite scroll
    _pageController = PageController(initialPage: _infiniteScrollOffset);
    _todayDateString = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _tipFuture = _fetchTodayTip(); // Cache the future once
    _loadUserData();
    _loadDailyChallengeData();
    _loadMonthlyEcoPoints();
    _ensureChallengesExist();
    _ensureTipsExist();
    _checkIfTipBookmarked();
    _startSliderTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh monthly points when returning to this screen
    _loadMonthlyEcoPoints();
    _loadDailyChallengeData();
  }

  @override
  void dispose() {
    _sliderTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // Start automatic image slider with seamless infinite loop
  void _startSliderTimer() {
    _sliderTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_pageController.hasClients) {
        // Get current page, add 1, and animate to next page
        // No need for modulo - we have a huge virtual page count
        final currentPage =
            _pageController.page?.round() ?? _infiniteScrollOffset;
        _pageController.animateToPage(
          currentPage + 1,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  // Ensure today's challenges exist in Firestore
  Future<void> _ensureChallengesExist() async {
    try {
      await ChallengeGenerator.ensureTodayChallengesExist();
    } catch (e) {
      debugPrint('Error ensuring challenges exist: $e');
    }
  }

  // Ensure today's tip exists in Firestore
  Future<void> _ensureTipsExist() async {
    try {
      await TipGenerator.ensureTodayTipExists();
    } catch (e) {
      debugPrint('Error ensuring tip exists: $e');
    }
  }

  // Check if today's tip is bookmarked
  Future<void> _checkIfTipBookmarked() async {
    try {
      final user = _firebaseService.currentUser;
      if (user == null) return;

      final bookmarkDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('bookmarked_tips')
          .doc(_todayDateString)
          .get();

      if (mounted) {
        setState(() {
          _isTipBookmarked = bookmarkDoc.exists;
        });
      }
    } catch (e) {
      debugPrint('Error checking bookmark status: $e');
    }
  }

  // Toggle bookmark for today's tip
  Future<void> _toggleTipBookmark() async {
    try {
      final user = _firebaseService.currentUser;
      if (user == null) {
        _showSnackBar('Please sign in to bookmark tips');
        return;
      }

      final bookmarkRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('bookmarked_tips')
          .doc(_todayDateString);

      if (_isTipBookmarked) {
        // Remove bookmark
        await bookmarkRef.delete();
        setState(() {
          _isTipBookmarked = false;
        });
        _showSnackBar('Tip removed from bookmarks');
      } else {
        // Add bookmark
        await bookmarkRef.set({
          'tip': _currentTip,
          'category': _currentTipCategory,
          'date': _todayDateString,
          'bookmarkedAt': FieldValue.serverTimestamp(),
        });
        setState(() {
          _isTipBookmarked = true;
        });
        _showSnackBar('Tip bookmarked! ⭐');
      }
    } catch (e) {
      debugPrint('Error toggling bookmark: $e');
      _showSnackBar('Failed to update bookmark');
    }
  }

  // Share today's tip
  void _shareTip() {
    if (_currentTip.isEmpty) {
      _showSnackBar('No tip to share');
      return;
    }

    Share.share(
      '🌱 Today\'s Eco Tip from EcoPilot:\n\n$_currentTip\n\n'
      'Join me in making sustainable choices! Download EcoPilot app.',
      subject: 'Daily Eco Tip',
    );
  }

  // Helper method to show snackbar
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Load monthly Eco Points for current user
  Future<void> _loadMonthlyEcoPoints() async {
    try {
      final user = _firebaseService.currentUser;
      if (user == null) return;

      // Get current month string (e.g., "2026-01")
      final now = DateTime.now();
      final monthKey = DateFormat('yyyy-MM').format(now);

      debugPrint('🔍 Loading monthly points for user: ${user.uid}');
      debugPrint('📅 Month key: $monthKey');

      // Read directly from monthly_points document (same source as addEcoPoints writes to)
      final monthlyDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('monthly_points')
          .doc(monthKey)
          .get();

      int monthlyPoints = 0;
      int monthlyGoal = 500;

      if (monthlyDoc.exists) {
        final data = monthlyDoc.data();
        monthlyPoints = data?['points'] ?? 0;
        monthlyGoal = data?['goal'] ?? 500;
        debugPrint(
          '✅ Monthly points loaded from document: $monthlyPoints / $monthlyGoal',
        );
      } else {
        debugPrint(
          '⚠️ No monthly points document found for $monthKey, starting at 0',
        );
      }

      if (mounted) {
        setState(() {
          _monthlyEcoPoints = monthlyPoints;
          _monthlyGoal = monthlyGoal;
        });
      }

      debugPrint(
        '✅ Monthly points updated: $monthlyPoints / $monthlyGoal (${monthlyGoal > 0 ? ((monthlyPoints / monthlyGoal) * 100).toStringAsFixed(1) : 0}%)',
      );
    } catch (e) {
      debugPrint('❌ Error loading monthly eco points: $e');
    }
  }

  // Fetch user data from the service
  Future<void> _loadUserData() async {
    final user = _firebaseService.currentUser;
    if (user != null) {
      setState(() {
        _userName = user.displayName ?? 'User';
      });
      // ⚠️ CONCEPTUAL: Fetch user streak and points summary here

      _firebaseService.getUserSummary(user.uid).then((summary) {
        if (mounted) {
          setState(() {
            _userStreak = summary['streak'] ?? 0;
          });
        }
      });
    }
  }

  // Load today's challenge data from Firestore
  Future<void> _loadDailyChallengeData() async {
    // 1. Get today's date string
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final user = _firebaseService.currentUser;
    if (user == null) return;

    try {
      // 2. Fetch challenges from Firestore
      final challengeDoc = await FirebaseFirestore.instance
          .collection('challenges')
          .doc(today)
          .get();
      final userChallengeDoc = await FirebaseFirestore.instance
          .collection('user_challenges')
          .doc('${user.uid}-$today')
          .get();

      if (challengeDoc.exists) {
        final challenges = List.from(challengeDoc.data()?['challenges'] ?? []);
        if (challenges.isNotEmpty) {
          final firstChallenge = challenges.first;
          final isCompleted = userChallengeDoc.exists
              ? List.from(userChallengeDoc.data()!['completed']).first
              : false;

          if (mounted) {
            setState(() {
              _dailyChallenge = DailyChallenge(
                firstChallenge['title'],
                firstChallenge['points'],
                isCompleted,
              );
            });
          }
          return; // Successfully loaded from Firestore
        }
      }
    } catch (e) {
      debugPrint('Error loading daily challenge: $e');
    }

    // Fallback to default challenge if Firestore fails
    if (mounted) {
      setState(() {
        _dailyChallenge = DailyChallenge(
          "Bring your own reusable bottle",
          10,
          false,
        );
      });
    }
  }

  // (preview completion now handled by launching the detailed DailyChallengeScreen and
  // receiving a result when the user completes the challenge there)

  // Modern Tip Card Widget with Bookmark and Share - Redesigned with Yellow Theme
  Widget _buildModernTipCard({
    required String tip,
    required String category,
    bool isError = false,
    bool isLoading = false,
  }) {
    // Update state variables when tip loads
    if (!isError && !isLoading && _currentTip != tip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentTip = tip;
            _currentTipCategory = category;
          });
        }
      });
    }

    // Get category emoji
    String getCategoryEmoji() {
      switch (category) {
        case 'waste_reduction':
          return '♻️';
        case 'energy_saving':
          return '💡';
        case 'sustainable_shopping':
          return '🛍️';
        case 'transportation':
          return '🚶';
        case 'food_habits':
          return '🥗';
        case 'water_conservation':
          return '💧';
        case 'recycling':
          return '♻️';
        case 'eco_habits':
          return '🌱';
        default:
          return '💚';
      }
    }

    // Get category display name
    String getCategoryName() {
      switch (category) {
        case 'waste_reduction':
          return 'Waste Reduction';
        case 'energy_saving':
          return 'Energy Saving';
        case 'sustainable_shopping':
          return 'Sustainable Shopping';
        case 'transportation':
          return 'Transportation';
        case 'food_habits':
          return 'Food Habits';
        case 'water_conservation':
          return 'Water Conservation';
        case 'recycling':
          return 'Recycling';
        case 'eco_habits':
          return 'Eco Habits';
        default:
          return 'Eco Tips';
      }
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isError
              ? [Colors.red.shade50, Colors.red.shade100]
              : isLoading
              ? [Colors.grey.shade100, Colors.grey.shade200]
              : [
                  const Color(0xFFFFF9E6), // Light yellow
                  const Color(0xFFFFF3CC), // Slightly darker yellow
                ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isError
              ? Colors.red.shade300
              : isLoading
              ? Colors.grey.shade300
              : const Color(0xFFFFD54F),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: isError
                ? Colors.red.withOpacity(0.2)
                : isLoading
                ? Colors.grey.withOpacity(0.1)
                : const Color(0xFFFFD54F).withOpacity(0.3),
            blurRadius: 25,
            offset: const Offset(0, 12),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.8),
            blurRadius: 10,
            offset: const Offset(-5, -5),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles in background
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFD54F).withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFC107).withOpacity(0.1),
              ),
            ),
          ),
          // Main content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header section with premium design
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Large emoji with glow effect
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: isError
                                  ? [Colors.red.shade400, Colors.red.shade500]
                                  : isLoading
                                  ? [Colors.grey.shade400, Colors.grey.shade500]
                                  : [
                                      const Color(0xFFFFD54F),
                                      const Color(0xFFFFC107),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: isError
                                    ? Colors.red.withOpacity(0.3)
                                    : isLoading
                                    ? Colors.grey.withOpacity(0.2)
                                    : const Color(0xFFFFC107).withOpacity(0.4),
                                blurRadius: 20,
                                spreadRadius: 2,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              isError
                                  ? '❌'
                                  : isLoading
                                  ? '⏳'
                                  : getCategoryEmoji(),
                              style: const TextStyle(fontSize: 40),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        // Title section
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // "Today" badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFFD54F),
                                      Color(0xFFFFC107),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFFFC107,
                                      ).withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.wb_sunny,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'TODAY',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 1.2,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black.withOpacity(
                                              0.2,
                                            ),
                                            offset: const Offset(0, 1),
                                            blurRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              // Main title
                              Text(
                                "Daily Eco Tip",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 24,
                                  color: const Color(0xFF795548),
                                  letterSpacing: 0.5,
                                  shadows: [
                                    Shadow(
                                      color: Colors.white.withOpacity(0.8),
                                      offset: const Offset(1, 1),
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                              if (!isError && !isLoading) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFFFC107),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        getCategoryName(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFFF57C00),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Decorative divider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        const Color(0xFFFFD54F).withOpacity(0.5),
                        const Color(0xFFFFC107).withOpacity(0.5),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Tip content with enhanced styling
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tip icon and text
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD54F).withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.lightbulb,
                            color: Color(0xFFF57C00),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tip,
                            style: TextStyle(
                              fontSize: 16,
                              color: const Color(0xFF5D4037),
                              height: 1.7,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (!isError && !isLoading) ...[
                      const SizedBox(height: 24),

                      // Action buttons with modern design
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFFFD54F).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            // Bookmark button
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _toggleTipBookmark,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: _isTipBookmarked
                                          ? const LinearGradient(
                                              colors: [
                                                Color(0xFFFFD54F),
                                                Color(0xFFFFC107),
                                              ],
                                            )
                                          : null,
                                      color: _isTipBookmarked
                                          ? null
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _isTipBookmarked
                                            ? const Color(0xFFFFC107)
                                            : Colors.grey.shade300,
                                        width: 1.5,
                                      ),
                                      boxShadow: _isTipBookmarked
                                          ? [
                                              BoxShadow(
                                                color: const Color(
                                                  0xFFFFC107,
                                                ).withOpacity(0.3),
                                                blurRadius: 8,
                                                offset: const Offset(0, 4),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _isTipBookmarked
                                              ? Icons.bookmark
                                              : Icons.bookmark_border,
                                          color: _isTipBookmarked
                                              ? Colors.white
                                              : Colors.grey.shade700,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _isTipBookmarked ? 'Saved' : 'Save',
                                          style: TextStyle(
                                            color: _isTipBookmarked
                                                ? Colors.white
                                                : Colors.grey.shade700,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Share button
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _shareTip,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFFD54F),
                                          Color(0xFFFFC107),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFFFC107),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFFFFC107,
                                          ).withOpacity(0.4),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.share_outlined,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Share',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black.withOpacity(
                                                  0.2,
                                                ),
                                                offset: const Offset(0, 1),
                                                blurRadius: 2,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Modern Challenge Card Widget
  Widget _buildModernChallengeCard() {
    final challenge = _dailyChallenge;
    final isCompleted = challenge?.isCompleted ?? false;
    final challengeText = challenge != null ? challenge.title : _challenge;

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => DailyChallengeScreen(
              userName: _userName,
              primaryGreen: kPrimaryGreen,
            ),
          ),
        );
        if (result == true) {
          // Reload both challenges and monthly points when user completes a challenge
          _loadDailyChallengeData();
          _loadMonthlyEcoPoints();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isCompleted
                          ? [Colors.grey.shade400, Colors.grey.shade300]
                          : [kPrimaryGreen, kPrimaryGreen.withOpacity(0.8)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isCompleted ? Icons.check_circle : Icons.flag_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Eco Challenge',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isCompleted
                              ? Colors.grey.shade600
                              : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        challengeText,
                        style: TextStyle(
                          fontSize: 13,
                          color: isCompleted
                              ? Colors.grey.shade500
                              : Colors.grey.shade700,
                          decoration: isCompleted
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (challenge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: kPrimaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kPrimaryGreen.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.stars, size: 16, color: kPrimaryGreen),
                        const SizedBox(width: 4),
                        Text(
                          '+${challenge.points} pts',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryGreen,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox.shrink(),
                ElevatedButton(
                  onPressed: isCompleted
                      ? null
                      : () async {
                          final result = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => DailyChallengeScreen(
                                userName: _userName,
                                primaryGreen: kPrimaryGreen,
                              ),
                            ),
                          );
                          if (result == true) {
                            _loadDailyChallengeData();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCompleted ? Colors.grey : kPrimaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: isCompleted ? 0 : 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isCompleted ? 'Completed ✓' : 'Start Now',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!isCompleted) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward, size: 16),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Modern Score Card Widget
  Widget _buildModernScoreCard() {
    final progress = _monthlyGoal > 0
        ? (_monthlyEcoPoints / _monthlyGoal).clamp(0.0, 1.0)
        : 0.0;
    final progressPercent = (progress * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kPrimaryGreen, kPrimaryGreen.withOpacity(0.85)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: kPrimaryGreen.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your Monthly Eco Points',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.eco, color: Colors.white, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Points Display
          Text(
            '$_monthlyEcoPoints / $_monthlyGoal',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.white.withOpacity(0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                progressPercent >= 80
                    ? "You're doing amazing! 🌱"
                    : progressPercent >= 50
                    ? "Great progress! Keep going! 💪"
                    : "Let's reach your goal! 🚀",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '$progressPercent%',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Empty Activity Card
  Widget _buildEmptyActivityCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.eco_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No activity yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan a product to get started on your eco journey!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // Refresh all data
  Future<void> _refreshData() async {
    await Future.wait([
      _loadMonthlyEcoPoints(),
      _loadDailyChallengeData(),
      _loadUserData(),
    ]);
    debugPrint('🔄 Home screen data refreshed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey.shade50,
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: CustomScrollView(
          slivers: [
            // Hero Header with Gradient
            SliverAppBar(
              expandedHeight: 240,
              floating: false,
              pinned: true,
              automaticallyImplyLeading: false,
              backgroundColor: kPrimaryGreen,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  children: [
                    // Image Slider Background - Infinite Loop
                    Positioned.fill(
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (index) {
                          // Update slide index without setState to avoid rebuilding entire screen
                          _currentSlideIndex = index % _sliderImages.length;
                        },
                        // Use a very large itemCount for infinite scrolling effect
                        itemCount: _infiniteScrollOffset * 2,
                        itemBuilder: (context, index) {
                          // Map the virtual index to actual image index using modulo
                          final imageIndex = index % _sliderImages.length;
                          return Image.asset(
                            _sliderImages[imageIndex],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              // Fallback to gradient if images not found
                              return Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      kPrimaryGreen,
                                      kPrimaryGreen.withOpacity(0.85),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    // Gradient Overlay for better text visibility
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black],
                          ),
                        ),
                      ),
                    ),
                    // Content
                    Container(
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Greeting
                              Text(
                                'Hello!',
                                style: TextStyle(
                                  fontSize: 20,
                                  color: Colors.white.withOpacity(0.9),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // User Name
                              Text(
                                _userName,
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Streak and Status
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.3),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.eco,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          "Let's make a difference",
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.95,
                                            ),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_userStreak > 0) ...[
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.orange.withOpacity(0.4),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            '🔥',
                                            style: TextStyle(fontSize: 14),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$_userStreak day streak',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Slider Indicators
                              // Row(
                              //   mainAxisAlignment: MainAxisAlignment.center,
                              //   children: List.generate(
                              //     _sliderImages.length,
                              //     (index) => AnimatedContainer(
                              //       duration: const Duration(milliseconds: 300),
                              //       margin: const EdgeInsets.symmetric(
                              //         horizontal: 4,
                              //       ),
                              //       width: _currentSlideIndex == index ? 24 : 8,
                              //       height: 8,
                              //       decoration: BoxDecoration(
                              //         color: _currentSlideIndex == index
                              //             ? Colors.white
                              //             : Colors.white.withOpacity(0.4),
                              //         borderRadius: BorderRadius.circular(4),
                              //       ),
                              //     ),
                              //   ),
                              // ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              leading: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                  onPressed: () {
                    _scaffoldKey.currentState?.openDrawer();
                  },
                ),
              ),
              actions: [
                // Notification Icon
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseAuth.instance.currentUser != null
                        ? FirebaseFirestore.instance
                              .collection('users')
                              .doc(FirebaseAuth.instance.currentUser!.uid)
                              .collection('notifications')
                              .where('read', isEqualTo: false)
                              .snapshots()
                        : null,
                    builder: (context, snapshot) {
                      final hasUnread =
                          snapshot.hasData && snapshot.data!.docs.isNotEmpty;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.notifications_outlined,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const NotificationScreen(),
                                ),
                              );
                            },
                          ),
                          if (hasUnread)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),

            // Content Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Today's Tips Card - Enhanced with Bookmark & Share
                    FutureBuilder<Map<String, String>>(
                      future:
                          _tipFuture, // Use cached future instead of calling function
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return _buildModernTipCard(
                            tip: 'Loading today\'s tip...',
                            category: 'eco_habits',
                            isLoading: true,
                          );
                        } else if (snapshot.hasError) {
                          return _buildModernTipCard(
                            tip: 'Error loading tip.',
                            category: 'eco_habits',
                            isError: true,
                          );
                        } else {
                          final data =
                              snapshot.data ??
                              {
                                'tip': 'No tips available.',
                                'category': 'eco_habits',
                              };
                          return _buildModernTipCard(
                            tip: data['tip']!,
                            category: data['category']!,
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // Daily Eco Challenge - Enhanced
                    _buildModernChallengeCard(),
                    const SizedBox(height: 20),

                    // Weekly Eco Points - Enhanced
                    _buildModernScoreCard(),
                    const SizedBox(height: 30),

                    // Recent Activity Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recent Activity',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RecentActivityScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.history, size: 18),
                          label: const Text('View All'),
                          style: TextButton.styleFrom(
                            foregroundColor: kPrimaryGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Recent Activity List
                    Builder(
                      builder: (context) {
                        final user = FirebaseAuth.instance.currentUser;
                        final Stream<QuerySnapshot<Map<String, dynamic>>>?
                        scansStream = user != null
                            ? FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user.uid)
                                  .collection('scans')
                                  .orderBy('timestamp', descending: true)
                                  .limit(10)
                                  .withConverter<Map<String, dynamic>>(
                                    fromFirestore: (snap, _) =>
                                        snap.data() ?? <String, dynamic>{},
                                    toFirestore: (m, _) => m,
                                  )
                                  .snapshots()
                            : null;

                        return StreamBuilder<
                          QuerySnapshot<Map<String, dynamic>>
                        >(
                          stream: scansStream,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32.0),
                                  child: CircularProgressIndicator(
                                    color: kPrimaryGreen,
                                  ),
                                ),
                              );
                            }
                            if (!snapshot.hasData ||
                                snapshot.data!.docs.isEmpty) {
                              return _buildEmptyActivityCard();
                            }
                            final docs = snapshot.data!.docs;
                            final filtered = docs.where((doc) {
                              final m = doc.data();
                              final v = m['isDisposal'];
                              return v == null ? true : (v == false);
                            }).toList();

                            if (filtered.isEmpty) {
                              return _buildEmptyActivityCard();
                            }

                            final previewDocs = filtered.take(3).toList();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: previewDocs
                                  .map((doc) => _buildActivityTile(doc))
                                  .toList(),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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

  // Custom widget to display the product details, mimicking the image
  Widget _buildProductDetailCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    // ... (Product details logic remains the same)
    final data = doc.data();
    final name = (data['product_name'] ?? 'Unknown Product').toString();
    final category = (data['category'] ?? 'N/A').toString();
    final ingredients = (data['ingredients'] ?? 'N/A').toString();
    final score = (data['eco_score'] ?? 'A')
        .toString()
        .toUpperCase(); // Assuming A-E score
    final co2 = (data['carbon_footprint'] ?? '—').toString();
    final packaging = (data['packaging'] ?? 'N/A').toString();
    final disposal = (data['disposal_method'] ?? 'Rinse and recycle locally')
        .toString();
    // Using the safe boolean read logic from your onTap function
    bool readBool(dynamic v) {
      if (v is bool) return v;
      if (v is String) {
        return v.toLowerCase() == 'true' || v.toLowerCase() == 'yes';
      }
      if (v is num) return v != 0;
      return false;
    }

    final containsMicroplastics = readBool(data['contains_microplastics']);
    final palmOilDerivative = readBool(data['palm_oil_derivative']);
    final crueltyFree = readBool(data['cruelty_free']);

    // Function to determine the color for the Eco-Score background
    Color getEcoScoreColor(String s) {
      switch (s) {
        case 'A':
          return Colors.green.shade700;
        case 'B':
          return Colors.lightGreen.shade700;
        case 'C':
          return Colors.amber.shade700;
        case 'D':
          return Colors.orange.shade700;
        case 'E':
          return Colors.red.shade700;
        default:
          return Colors.grey.shade700;
      }
    }

    // --- Main Card Widget - Redesigned ---
    return Container(
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with gradient and eco score
          Container(
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kPrimaryGreen, kPrimaryGreen.withOpacity(0.8)],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Product Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Eco Score Badge
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        score,
                        style: TextStyle(
                          color: getEcoScoreColor(score),
                          fontWeight: FontWeight.bold,
                          fontSize: 28,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ECO SCORE',
                        style: TextStyle(
                          color: getEcoScoreColor(score),
                          fontWeight: FontWeight.w600,
                          fontSize: 8,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Product Image Section
          Builder(
            builder: (context) {
              // Try to get image URL from various possible keys
              String? imageUrl;
              final possibleKeys = [
                'image',
                'image_url',
                'imageUrl',
                'product_image',
                'thumbnail',
                'photo',
              ];
              for (final k in possibleKeys) {
                final v = data[k];
                if (v is String && v.isNotEmpty) {
                  imageUrl = v;
                  break;
                }
              }

              if (imageUrl != null && imageUrl.isNotEmpty) {
                return Container(
                  height: 200,
                  width: double.infinity,
                  color: Colors.grey.shade50,
                  child: Stack(
                    children: [
                      // Product Image
                      Positioned.fill(
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (c, e, s) => Container(
                            color: Colors.grey.shade100,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.image_not_supported_outlined,
                                    size: 48,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Image not available',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: Colors.grey.shade100,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value:
                                      loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                      : null,
                                  color: kPrimaryGreen,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // Gradient overlay at bottom for better text visibility
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.3),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              // No image available - show placeholder
              return Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      kPrimaryGreen.withOpacity(0.1),
                      kPrimaryGreen.withOpacity(0.05),
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.eco_outlined,
                        size: 56,
                        color: kPrimaryGreen.withOpacity(0.4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No product image',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Content sections
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: kPrimaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: kPrimaryGreen.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.category_outlined,
                        size: 16,
                        color: kPrimaryGreen,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        category,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kPrimaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Ingredients Section
                _buildModernSection(
                  icon: Icons.science_outlined,
                  title: 'Ingredients',
                  content: ingredients,
                  iconColor: Colors.blue.shade600,
                ),
                const SizedBox(height: 16),

                // Eco Impact Section
                const Text(
                  'Eco Impact',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                _buildInfoCard(
                  icon: Icons.cloud_outlined,
                  label: 'Carbon Footprint',
                  value: co2,
                  color: Colors.lightBlue.shade400,
                ),
                const SizedBox(height: 10),
                _buildInfoCard(
                  icon: Icons.eco_outlined,
                  label: 'Packaging',
                  value: packaging,
                  color: Colors.green.shade400,
                ),
                const SizedBox(height: 10),
                _buildInfoCard(
                  icon: Icons.restore_from_trash_outlined,
                  label: 'Disposal',
                  value: disposal,
                  color: Colors.orange.shade400,
                ),
                const SizedBox(height: 20),

                // Environmental Warnings
                const Text(
                  'Environmental Impact',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                _buildWarningCard(
                  label: 'Microplastics Free',
                  isGood: !containsMicroplastics,
                ),
                const SizedBox(height: 8),
                _buildWarningCard(
                  label: 'Palm Oil Free',
                  isGood: !palmOilDerivative,
                ),
                const SizedBox(height: 8),
                _buildWarningCard(label: 'Cruelty-Free', isGood: crueltyFree),

                // Better Alternative Button
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Close the modal first
                      Navigator.of(context).pop();

                      // Navigate to Better Alternative Screen with product data
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BetterAlternativeScreen(
                            scannedProduct: ProductAnalysisData(
                              productName: name,
                              category: category,
                              ingredients: ingredients,
                              carbonFootprint: co2,
                              packagingType: packaging,
                              disposalMethod: disposal,
                              containsMicroplastics: containsMicroplastics,
                              palmOilDerivative: palmOilDerivative,
                              crueltyFree: crueltyFree,
                              ecoScore: score,
                            ),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.eco, size: 20),
                    label: const Text(
                      'View Better Alternatives',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernSection({
    required IconData icon,
    required String title,
    required String content,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningCard({required String label, required bool isGood}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isGood ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isGood ? Colors.green.shade200 : Colors.red.shade200,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isGood ? Colors.green.shade100 : Colors.red.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isGood ? Icons.check : Icons.close,
              size: 16,
              color: isGood ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isGood ? Colors.green.shade900 : Colors.red.shade900,
              ),
            ),
          ),
          if (isGood)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'GOOD',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActivityTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final product =
        (data['product_name'] ?? data['product'] ?? 'Unknown product')
            .toString();
    final score =
        (data['eco_score'] ?? data['ecoscore'] ?? data['score'] ?? 'N/A')
            .toString()
            .toUpperCase();

    final category = (data['category'] ?? 'N/A').toString();

    final ts = data['timestamp'];
    DateTime? dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is DateTime) {
      dt = ts;
    }

    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String formatDateTime(DateTime d) {
      final month = d.month;
      final day = d.day;
      final year = d.year;
      final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final minute = twoDigits(d.minute);
      final ampm = d.hour >= 12 ? 'PM' : 'AM';
      return '$month/$day/$year ${twoDigits(hour12)}:$minute $ampm';
    }

    final timeText = dt != null ? formatDateTime(dt) : '';

    // Try common image keys
    String? imageUrl;
    final possibleKeys = [
      'image',
      'image_url',
      'imageUrl',
      'product_image',
      'thumbnail',
      'photo',
      'img',
    ];
    for (final k in possibleKeys) {
      final v = data[k];
      if (v is String && v.isNotEmpty) {
        imageUrl = v;
        break;
      }
    }

    Color getEcoScoreColor(String s) {
      switch (s) {
        case 'A':
          return Colors.green.shade700;
        case 'B':
          return Colors.lightGreen.shade700;
        case 'C':
          return Colors.amber.shade700;
        case 'D':
          return Colors.orange.shade700;
        case 'E':
          return Colors.red.shade700;
        default:
          return Colors.grey.shade700;
      }
    }

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.9,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              builder: (_, controller) => SingleChildScrollView(
                controller: controller,
                child: _buildProductDetailCard(doc),
              ),
            ),
          );
        },
        child: Container(
          height: 120,
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Product Image - Larger and more prominent
              Hero(
                tag: 'product_home_${doc.id}',
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                              color: Colors.grey.shade100,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 32,
                                color: Colors.grey.shade400,
                              ),
                            ),
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: Colors.grey.shade100,
                                child: const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  kPrimaryGreen.withOpacity(0.1),
                                  kPrimaryGreen.withOpacity(0.05),
                                ],
                              ),
                            ),
                            child: Icon(
                              Icons.eco_outlined,
                              color: kPrimaryGreen,
                              size: 40,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Content area - Product info and metadata
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Product name
                    Text(
                      product,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: Colors.black87,
                      ),
                    ),
                    // Category badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimaryGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: kPrimaryGreen.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        category,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: kPrimaryGreen.withOpacity(0.9),
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Date/Time
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 13,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            timeText,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Eco Score Badge - Prominent on the right
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: getEcoScoreColor(score),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: getEcoScoreColor(score).withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          score,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ECO',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w600,
                            fontSize: 9,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
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
        // When the Alternative tab is tapped, open the Alternative screen (history view)
        if (index == 1) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const alt_screen.AlternativeScreen(),
            ),
          );
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
