/// Eco Point System Constants
///
/// This file defines all point values and limits for the eco point reward system.
/// Points contribute simultaneously to weekly, monthly, and all-time leaderboards.
library;

class EcoPointConstants {
  // ============================================
  // 📊 POINT VALUES
  // ============================================

  /// View daily eco tip: 3 points (Daily limit: 1, Weekly limit: 7)
  static const int viewDailyEcoTip = 3;

  /// Complete daily eco challenge: 20 points (Daily limit: 1, Weekly limit: 7)
  static const int completeDailyChallenge = 20;

  /// Daily streak bonus: 10 points (Daily limit: 1, Weekly limit: 7)
  static const int dailyStreakBonus = 10;

  /// Scan product (image/barcode): 5 points (Daily limit: 10, Weekly limit: 50)
  static const int scanProduct = 5;

  /// First-time product scan bonus: 5 points (Daily limit: 5, Weekly limit: 20)
  static const int firstTimeScanBonus = 5;

  /// Add new product: 30 points (Daily limit: 3, Weekly limit: 10)
  static const int addNewProduct = 30;

  /// Dispose/recycle product: 10 points (Daily limit: 5, Weekly limit: 20)
  static const int disposeProduct = 10;

  /// Verified disposal bonus: 5 points (Daily limit: 5, Weekly limit: 20)
  static const int verifiedDisposalBonus = 5;

  /// Weekly eco goal completion: 30 points (Weekly limit: 1)
  static const int weeklyGoalCompletion = 30;

  /// Monthly eco goal completion: 50 points (Monthly limit: 1)
  static const int monthlyGoalCompletion = 50;

  /// Rank promotion bonus: 20-50 points (one-time per rank)
  static const int rankPromotionBonusMin = 20;
  static const int rankPromotionBonusMax = 50;

  /// Eco campaign/event participation: 20-50 points (campaign-based)
  static const int campaignParticipationMin = 20;
  static const int campaignParticipationMax = 50;

  // ============================================
  // 🚦 DAILY LIMITS
  // ============================================

  static const int dailyLimitViewTip = 1;
  static const int dailyLimitCompleteChallenge = 1;
  static const int dailyLimitStreakBonus = 1;
  static const int dailyLimitScanProduct = 10;
  static const int dailyLimitFirstTimeScan = 5;
  static const int dailyLimitAddProduct = 3;
  static const int dailyLimitDispose = 5;
  static const int dailyLimitVerifiedDisposal = 5;

  /// Overall daily eco point cap (anti-abuse)
  static const int dailyPointCap = 120;

  // ============================================
  // 🗓️ WEEKLY LIMITS
  // ============================================

  static const int weeklyLimitViewTip = 7;
  static const int weeklyLimitCompleteChallenge = 7;
  static const int weeklyLimitStreakBonus = 7;
  static const int weeklyLimitScanProduct = 50;
  static const int weeklyLimitFirstTimeScan = 20;
  static const int weeklyLimitAddProduct = 10;
  static const int weeklyLimitDispose = 20;
  static const int weeklyLimitVerifiedDisposal = 20;
  static const int weeklyLimitGoalCompletion = 1;

  /// Overall weekly eco point cap (anti-abuse)
  static const int weeklyPointCap = 700;

  // ============================================
  // 📅 MONTHLY LIMITS
  // ============================================

  static const int monthlyLimitGoalCompletion = 1;

  // ============================================
  // 🎖️ STREAK MILESTONES
  // ============================================

  /// Streak milestone bonuses (already included in dailyStreakBonus)
  static const Map<int, int> streakMilestoneBonuses = {
    7: 10, // 7-day streak bonus
    14: 10, // 14-day streak bonus
    30: 10, // 30-day streak bonus
    50: 10, // 50-day streak bonus
    100: 10, // 100-day streak bonus
    200: 10, // 200-day streak bonus
  };

  // ============================================
  // 📝 ACTIVITY TYPES (for tracking)
  // ============================================

  static const String activityViewTip = 'view_daily_tip';
  static const String activityCompleteChallenge = 'complete_daily_challenge';
  static const String activityStreakBonus = 'daily_streak_bonus';
  static const String activityScanProduct = 'scan_product';
  static const String activityFirstTimeScan = 'first_time_scan_bonus';
  static const String activityAddProduct = 'add_new_product';
  static const String activityDispose = 'dispose_product';
  static const String activityVerifiedDisposal = 'verified_disposal_bonus';
  static const String activityWeeklyGoal = 'weekly_goal_completion';
  static const String activityMonthlyGoal = 'monthly_goal_completion';
  static const String activityRankPromotion = 'rank_promotion_bonus';
  static const String activityCampaign = 'eco_campaign_event';
}
