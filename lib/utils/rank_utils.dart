import 'package:flutter/material.dart';
import 'package:ecopilot/utils/constants.dart';

/// Small value object for user rank display.
class RankInfo {
  final String title;
  final Color color;
  final String emoji;
  final int minPoints;
  final int? maxPoints;

  const RankInfo(
    this.title,
    this.color,
    this.emoji,
    this.minPoints, [
    this.maxPoints,
  ]);
}

/// Eco Point Reward System - 12 Tier Ranking System
///
/// Points can be earned through:
/// - Product scanning (+2 points)
/// - Daily challenge completion (+5 per task, +10 for both)
/// - Streak bonuses (10 days: +5, 30 days: +15, 100 days: +30, 200 days: +50)
/// - Disposal guidance (+3 points)
/// - Exploring alternatives (+5 points)
/// - Reading tips/quizzes (+2-5 points)
/// - Weekly engagement (+10 points)
/// - Monthly leaderboard bonus (up to +20 points)
RankInfo rankForPoints(int points) {
  if (points >= 40000) {
    return const RankInfo(
      'Global Sustainability Icon',
      Color(0xFFFFD700), // Gold
      '🏆',
      40000,
      null,
    );
  }
  if (points >= 30000) {
    return const RankInfo(
      'Eco Legend',
      Color(0xFF9C27B0), // Purple
      '⭐',
      30000,
      39999,
    );
  }
  if (points >= 23000) {
    return const RankInfo(
      'Climate Champion',
      Color(0xFFE91E63), // Pink
      '🔥',
      23000,
      29999,
    );
  }
  if (points >= 17000) {
    return const RankInfo(
      'Earth Guardian',
      Color(0xFF2196F3), // Blue
      '💧',
      17000,
      22999,
    );
  }
  if (points >= 12000) {
    return const RankInfo(
      'Eco Guardian',
      Color(0xFF00BCD4), // Cyan
      '🛡️',
      12000,
      16999,
    );
  }
  if (points >= 8000) {
    return const RankInfo(
      'Planet Protector',
      kRankPlanetProtector, // Dark Green
      '🌳',
      8000,
      11999,
    );
  }
  if (points >= 5000) {
    return const RankInfo(
      'Sustainability Champion',
      kRankSustainabilityHero, // Orange
      '🌎',
      5000,
      7999,
    );
  }
  if (points >= 3000) {
    return const RankInfo(
      'Eco Advocate',
      Color(0xFF4CAF50), // Green
      '📢',
      3000,
      4999,
    );
  }
  if (points >= 1500) {
    return const RankInfo(
      'Eco Explorer',
      kRankEcoExplorer, // Amber
      '🌻',
      1500,
      2999,
    );
  }
  if (points >= 800) {
    return const RankInfo(
      'Sprout',
      Color(0xFF8BC34A), // Light Green
      '🌿',
      800,
      1499,
    );
  }
  if (points >= 300) {
    return const RankInfo(
      'Seedling',
      Color(0xFF9CCC65), // Pale Green
      '🌾',
      300,
      799,
    );
  }
  return const RankInfo(
    'Green Beginner',
    kRankGreenBeginner, // Primary Green
    '🌱',
    0,
    299,
  );
}

/// Get description for each rank tier
String getRankDescription(int points) {
  final rank = rankForPoints(points);

  switch (rank.title) {
    case 'Global Sustainability Icon':
      return 'Top-tier users recognized for exceptional global impact.';
    case 'Eco Legend':
      return 'Elite users with outstanding sustainability contributions.';
    case 'Climate Champion':
      return 'Users actively driving climate-positive behavior.';
    case 'Earth Guardian':
      return 'Advanced users with long-term eco commitment.';
    case 'Eco Guardian':
      return 'Dedicated users who lead sustainability efforts.';
    case 'Planet Protector':
      return 'Users making a visible environmental impact.';
    case 'Sustainability Champion':
      return 'Highly committed users with strong eco habits.';
    case 'Eco Advocate':
      return 'Users who consistently support sustainable practices.';
    case 'Eco Explorer':
      return 'Active users who regularly engage in eco-friendly actions.';
    case 'Sprout':
      return 'Users who participate occasionally in eco challenges and scans.';
    case 'Seedling':
      return 'Users beginning to explore eco-friendly activities.';
    case 'Green Beginner':
    default:
      return 'Users who are new and just starting their sustainability journey.';
  }
}

/// Calculate points needed to reach next rank
int pointsToNextRank(int currentPoints) {
  final rank = rankForPoints(currentPoints);
  if (rank.maxPoints == null) return 0; // Already at max rank
  return rank.maxPoints! - currentPoints + 1;
}
