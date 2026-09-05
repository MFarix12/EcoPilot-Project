import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:ecopilot/utils/constants.dart';
import 'package:ecopilot/auth/firebase_service.dart';
import 'package:ecopilot/utils/rank_utils.dart';
import 'package:ecopilot/services/streak_notification_manager.dart';
import 'package:ecopilot/utils/challenge_generator.dart';

// Placeholder data structure for challenge and user progress
class Challenge {
  final String title;
  final int points;
  final String id;

  Challenge(this.id, this.title, this.points);
}

class UserChallengeProgress {
  final List<bool> completed;
  final int pointsEarned;
  final int streakCount;
  final int totalChallengePoints;

  UserChallengeProgress({
    required this.completed,
    this.pointsEarned = 0,
    this.streakCount = 0,
    required this.totalChallengePoints,
  });

  double get progressPercentage {
    // Prefer point-based progress if total points is available
    if (totalChallengePoints > 0) {
      return (pointsEarned / totalChallengePoints).clamp(0.0, 1.0);
    }
    if (completed.isEmpty) return 0.0;
    final completedCount = completed.where((c) => c).length;
    return completedCount / completed.length;
  }

  bool get allCompleted => completed.every((c) => c);
}

extension UserChallengeProgressExt on UserChallengeProgress {
  UserChallengeProgress copyWith({
    List<bool>? completed,
    int? pointsEarned,
    int? streakCount,
    int? totalChallengePoints,
  }) {
    return UserChallengeProgress(
      completed: completed ?? this.completed,
      pointsEarned: pointsEarned ?? this.pointsEarned,
      streakCount: streakCount ?? this.streakCount,
      totalChallengePoints: totalChallengePoints ?? this.totalChallengePoints,
    );
  }
}

class DailyChallengeScreen extends StatefulWidget {
  final String userName;
  final Color primaryGreen;

  const DailyChallengeScreen({
    super.key,
    required this.userName,
    required this.primaryGreen,
  });

  @override
  State<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

class _DailyChallengeScreenState extends State<DailyChallengeScreen> {
  // Use simulated data or fetch streams in a real app
  late List<Challenge> _challenges;
  late UserChallengeProgress _progress;
  final FirebaseService _firebaseService = FirebaseService();
  int _userEcoPoints = 0;
  String _userRank = 'Green Beginner';
  Color _rankColor = kRankGreenBeginner;
  bool _isLoading = true;

  // Dynamic date - recalculated each time to ensure it's always current
  String get today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadChallengeData();
    _loadUserRank();
  }

  Future<void> _loadUserRank() async {
    try {
      final user = _firebaseService.currentUser;
      if (user == null) return;
      final summary = await _firebaseService.getUserSummary(user.uid);
      final points = (summary['ecoScore'] ?? summary['ecoPoints'] ?? 0) as int;
      final rankInfo = rankForPoints(points);
      if (mounted) {
        setState(() {
          _userEcoPoints = points;
          _userRank = rankInfo.title;
          _rankColor = rankInfo.color;
        });
      }
    } catch (e) {
      debugPrint('Failed to load user rank: $e');
    }
  }

  // Rank logic moved to lib/utils/rank_utils.dart

  void _loadChallengeData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Fetch from Firestore first
      final challenges = await _fetchChallengesFromFirestore();
      final progress = await _fetchUserProgress(challenges.length);

      final totalPoints = challenges.fold<int>(
        0,
        (int sum, Challenge c) => sum + c.points,
      );

      if (mounted) {
        setState(() {
          _challenges = challenges;
          _progress = progress.copyWith(totalChallengePoints: totalPoints);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading challenge data: $e');
      // Use date-based fallback challenges
      final fallbackChallenges = _generateDateBasedChallenges();
      if (mounted) {
        setState(() {
          _challenges = fallbackChallenges;
          _progress = UserChallengeProgress(
            completed: List<bool>.filled(fallbackChallenges.length, false),
            pointsEarned: 0,
            streakCount: 0,
            totalChallengePoints: fallbackChallenges.fold<int>(
              0,
              (sum, c) => sum + c.points,
            ),
          );
          _isLoading = false;
        });
      }
    }
  }

  /// Generate different challenges based on current date (fallback when Firestore fails)
  List<Challenge> _generateDateBasedChallenges() {
    final now = DateTime.now();

    // Use the centralized challenge generator
    final generatedChallenges = ChallengeGenerator.generateDailyChallenges(now);

    // Convert to Challenge objects
    return generatedChallenges.map((data) {
      return Challenge(
        data['id'] as String,
        data['title'] as String,
        data['points'] as int,
      );
    }).toList();
  }

  /// Fetch challenge definitions for today from Firestore.
  /// Falls back to date-based generated challenges if nothing found.
  Future<List<Challenge>> _fetchChallengesFromFirestore() async {
    try {
      debugPrint('📅 Fetching challenges for date: $today');
      final doc = await FirebaseFirestore.instance
          .collection('challenges')
          .doc(today)
          .get();

      if (!doc.exists) {
        debugPrint(
          '⚠️ No challenges document found for $today, using date-based fallback',
        );
        return _generateDateBasedChallenges();
      }

      final data = doc.data();
      if (data == null) {
        debugPrint(
          '⚠️ Empty challenges data for $today, using date-based fallback',
        );
        return _generateDateBasedChallenges();
      }

      final list = List.from(data['challenges'] ?? []);
      if (list.isEmpty) {
        debugPrint(
          '⚠️ No challenges in document for $today, using date-based fallback',
        );
        return _generateDateBasedChallenges();
      }

      final challenges = list
          .map(
            (e) => Challenge(
              e['id'] ?? e['title'],
              e['title'] ?? '',
              e['points'] ?? 0,
            ),
          )
          .toList();

      debugPrint(
        '✅ Loaded ${challenges.length} challenges from Firestore for $today',
      );
      return challenges;
    } catch (e) {
      debugPrint('❌ Error fetching challenges: $e, using date-based fallback');
      return _generateDateBasedChallenges();
    }
  }

  /// Fetch the user's progress for today's challenges from Firestore.
  /// If no progress document exists, return a default [UserChallengeProgress].
  /// Streak is fetched from the users document, not user_challenges.
  Future<UserChallengeProgress> _fetchUserProgress(int challengeCount) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return UserChallengeProgress(
          completed: List<bool>.filled(challengeCount, false),
          pointsEarned: 0,
          streakCount: 0,
          totalChallengePoints: 0,
        );
      }

      // Fetch today's challenge progress
      final challengeDoc = await FirebaseFirestore.instance
          .collection('user_challenges')
          .doc('$uid-$today')
          .get();

      List<bool> completed = List<bool>.filled(challengeCount, false);
      int pointsEarned = 0;

      if (challengeDoc.exists) {
        final data = challengeDoc.data() ?? {};
        completed =
            (data['completed'] as List<dynamic>?)
                ?.map((e) => e == true)
                .toList() ??
            List<bool>.filled(challengeCount, false);

        // Ensure completed list matches challenge count
        final adjustedCompleted = List<bool>.filled(challengeCount, false);
        for (var i = 0; i < challengeCount && i < completed.length; i++) {
          adjustedCompleted[i] = completed[i];
        }
        completed = adjustedCompleted;
        pointsEarned = data['pointsEarned'] ?? 0;
      } else {
        debugPrint(
          '📝 No progress found for user $uid on $today, creating new progress',
        );
      }

      // Fetch streak from user's profile document
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final userData = userDoc.data() ?? {};
      final streak = userData['streak'] ?? 0;

      debugPrint(
        '✅ Loaded progress for $uid on $today: ${completed.where((c) => c).length}/$challengeCount completed, streak: $streak',
      );

      return UserChallengeProgress(
        completed: completed,
        pointsEarned: pointsEarned,
        streakCount: streak,
        totalChallengePoints: 0, // Will be set by caller
      );
    } catch (e) {
      debugPrint('❌ Error fetching user progress: $e');
      return UserChallengeProgress(
        completed: List<bool>.filled(challengeCount, false),
        pointsEarned: 0,
        streakCount: 0,
        totalChallengePoints: 0,
      );
    }
  }

  Future<void> _completeChallenge(int index) async {
    try {
      // Prevent double completion
      if (_progress.completed[index]) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in to complete challenges'),
          ),
        );
        return;
      }

      final challengePoints = _challenges[index].points;

      // Use FirebaseService to complete the challenge (handles all Firestore operations)
      final result = await _firebaseService.completeChallenge(
        challengeIndex: index,
        points: challengePoints,
        totalChallenges: _challenges.length,
        currentCompleted: _progress.completed,
      );

      if (!result['success']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Challenge already completed'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Update local state with the result
      if (mounted) {
        setState(() {
          _progress = _progress.copyWith(
            completed: List<bool>.from(result['completed']),
            pointsEarned: result['pointsEarned'],
            streakCount: result['streak'],
          );
          _userEcoPoints = result['totalEcoPoints'];
        });
        _loadUserRank(); // Refresh rank based on new points

        // Trigger milestone notification if streak reached a milestone
        final newStreak = result['streak'] as int;
        if (_isMilestone(newStreak)) {
          StreakNotificationManager().showMilestoneCelebration(newStreak);
        }
      }

      if (mounted) {
        final bonusPoints = result['bonusPoints'] ?? 0;
        final totalAwarded = challengePoints + bonusPoints;

        String message = '✅ Challenge completed! +$challengePoints Points!';
        if (bonusPoints > 0) {
          message =
              '🎉 All challenges completed! +$totalAwarded Points! ($challengePoints + $bonusPoints bonus)';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  bonusPoints > 0 ? Icons.emoji_events : Icons.check_circle,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: bonusPoints > 0
                ? Colors.amber.shade700
                : Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: Duration(seconds: bonusPoints > 0 ? 5 : 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('completeChallenge failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Failed to complete challenge. Please check your internet connection and try again.',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _completeChallenge(index),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // --- UI Builder Widgets ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(kPrimaryGreen),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading today\'s challenges...',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    final streak = _progress.streakCount;
    final progressPercent = (_progress.progressPercentage * 100).toInt();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: CustomScrollView(
        slivers: [
          // Modern Hero Header with Gradient
          SliverAppBar(
            expandedHeight: 260,
            floating: false,
            pinned: true,
            backgroundColor: kPrimaryGreen,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              // Refresh button
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () {
                  _loadChallengeData();
                  _loadUserRank();
                },
                tooltip: 'Refresh challenges',
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1db954),
                      const Color(0xFF1db954).withOpacity(0.8),
                      kPrimaryGreen,
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 50, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat(
                                  'EEEE, MMMM d',
                                ).format(DateTime.now()),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Welcome Text
                        Text(
                          'Hello ${widget.userName}! 👋',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Complete today\'s eco-challenges',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const Spacer(),

                        // Streak and Points Row
                        Row(
                          children: [
                            // Streak Badge
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      streak >= 3
                                          ? Icons.local_fire_department
                                          : Icons.emoji_events_outlined,
                                      color: streak >= 3
                                          ? Colors.orange.shade300
                                          : Colors.white,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 6),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$streak Days',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Streak',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.8,
                                            ),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Points Badge
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.stars_rounded,
                                      color: Colors.amber,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 6),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${_progress.pointsEarned}/${_progress.totalChallengePoints}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Points',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.8,
                                            ),
                                            fontSize: 11,
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progress Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [kPrimaryGreen, kPrimaryGreen.withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimaryGreen.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
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
                              'Daily Progress',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$progressPercent%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _progress.progressPercentage,
                            minHeight: 12,
                            backgroundColor: Colors.white.withOpacity(0.3),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          progressPercent == 100
                              ? '🎉 Amazing! All challenges completed!'
                              : progressPercent >= 50
                              ? '💪 You\'re halfway there! Keep going!'
                              : '🚀 Let\'s complete these challenges!',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Section Header
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: kPrimaryGreen,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Today\'s Challenges',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Challenge List
                  ..._challenges.asMap().entries.map((entry) {
                    return _buildModernChallengeTile(entry.value, entry.key);
                  }),

                  const SizedBox(height: 32),

                  // Enhanced Rank Card with Progress
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.white, _rankColor.withOpacity(0.05)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _rankColor.withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _rankColor.withOpacity(0.2),
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
                            // Rank Icon with Emoji
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _rankColor,
                                    _rankColor.withOpacity(0.7),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: _rankColor.withOpacity(0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Text(
                                rankForPoints(_userEcoPoints).emoji,
                                style: const TextStyle(fontSize: 32),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Your Rank',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _userRank,
                                    style: TextStyle(
                                      color: _rankColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 22,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.stars,
                                        size: 16,
                                        color: Colors.amber.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$_userEcoPoints points',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Rank Description
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _rankColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            getRankDescription(_userEcoPoints),
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                        // Progress to Next Rank
                        if (pointsToNextRank(_userEcoPoints) > 0) ...[
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Next Rank',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${pointsToNextRank(_userEcoPoints)} points to go',
                                    style: TextStyle(
                                      color: _rankColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value:
                                      _userEcoPoints /
                                      (rankForPoints(
                                            _userEcoPoints,
                                          ).maxPoints ??
                                          _userEcoPoints + 1),
                                  minHeight: 8,
                                  backgroundColor: Colors.grey.shade200,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _rankColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.amber.shade100,
                                  Colors.amber.shade50,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.emoji_events,
                                  color: Colors.amber.shade700,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '🏆 Maximum Rank Achieved!',
                                    style: TextStyle(
                                      color: Colors.amber.shade900,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
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

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Modern Challenge Tile Widget
  Widget _buildModernChallengeTile(Challenge challenge, int index) {
    final isCompleted = _progress.completed[index];

    // Determine challenge category icon (basic detection from title)
    IconData getChallengeIcon() {
      final title = challenge.title.toLowerCase();
      if (title.contains('recycle') || title.contains('plastic')) {
        return Icons.recycling;
      }
      if (title.contains('transport') ||
          title.contains('cycle') ||
          title.contains('walk')) {
        return Icons.directions_bike;
      }
      if (title.contains('bottle') || title.contains('water')) {
        return Icons.water_drop;
      }
      if (title.contains('energy') || title.contains('light')) {
        return Icons.lightbulb_outline;
      }
      if (title.contains('food') || title.contains('meal')) {
        return Icons.restaurant;
      }
      return Icons.eco;
    }

    final challengeIcon = getChallengeIcon();

    // Color scheme: Yellow before completion, Green after
    final cardBackgroundColor = isCompleted
        ? Colors.green.shade50
        : Colors.amber.shade50;
    final borderColor = isCompleted
        ? Colors.green.shade300
        : Colors.amber.shade300;
    final shadowColor = isCompleted
        ? Colors.green.withOpacity(0.15)
        : Colors.amber.withOpacity(0.15);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isCompleted ? null : () => _completeChallenge(index),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Icon Container
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? Colors.green.shade100
                        : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isCompleted ? Icons.check_circle : challengeIcon,
                    color: isCompleted
                        ? Colors.green.shade700
                        : Colors.amber.shade700,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),

                // Challenge Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        challenge.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isCompleted
                              ? Colors.green.shade900
                              : Colors.amber.shade900,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Wrap in Flexible to prevent overflow
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.stars,
                                  color: Colors.amber.shade700,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '+${challenge.points} pts',
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isCompleted)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check,
                                    color: Colors.green.shade700,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Completed',
                                    style: TextStyle(
                                      color: Colors.green.shade900,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
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

                const SizedBox(width: 8),

                // Action Button
                if (!isCompleted)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kPrimaryGreen,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimaryGreen.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 20,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.emoji_events,
                      color: Colors.green.shade700,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Check if streak is a milestone worthy of notification
  bool _isMilestone(int streak) {
    return streak == 7 ||
        streak == 14 ||
        streak == 30 ||
        streak == 50 ||
        streak == 100 ||
        streak == 200;
  }
}
