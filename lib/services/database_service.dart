// lib/services/database_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ecopilot/models/database_models.dart';

/// Database Service for EcoPilot
/// Provides CRUD operations for all database tables
class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // Auth instance available if needed
  // final FirebaseAuth _auth = FirebaseAuth.instance;

  // ========================================
  // USERS TABLE OPERATIONS
  // ========================================

  /// Create a new user profile
  Future<void> createUser(UserModel user) async {
    await _firestore
        .collection(FirestoreCollections.users)
        .doc(user.userId)
        .set(user.toFirestore());
  }

  /// Get user profile
  Future<UserModel?> getUser(String userId) async {
    final doc = await _firestore
        .collection(FirestoreCollections.users)
        .doc(userId)
        .get();

    if (doc.exists) {
      return UserModel.fromFirestore(doc);
    }
    return null;
  }

  /// Update user profile
  Future<void> updateUser(String userId, Map<String, dynamic> updates) async {
    await _firestore.collection(FirestoreCollections.users).doc(userId).update({
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update user eco points and rank
  Future<void> updateUserPoints(String userId, int points, String rank) async {
    await _firestore.collection(FirestoreCollections.users).doc(userId).update({
      'ecoPoints': points,
      'rank': rank,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Increment user streak
  Future<void> incrementStreak(String userId) async {
    await _firestore.collection(FirestoreCollections.users).doc(userId).update({
      'streakCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reset user streak
  Future<void> resetStreak(String userId) async {
    await _firestore.collection(FirestoreCollections.users).doc(userId).update({
      'streakCount': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ========================================
  // SCANNED PRODUCTS TABLE OPERATIONS
  // ========================================

  /// Add a scanned product
  Future<String> addScannedProduct(ScannedProductModel product) async {
    final docRef = await _firestore
        .collection(FirestoreCollections.scannedProducts)
        .add(product.toFirestore());
    return docRef.id;
  }

  /// Get scanned products for a user
  Future<List<ScannedProductModel>> getUserScannedProducts(
    String userId,
  ) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.scannedProducts)
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => ScannedProductModel.fromFirestore(doc))
        .toList();
  }

  /// Stream of user's scanned products
  Stream<List<ScannedProductModel>> streamUserScannedProducts(String userId) {
    return _firestore
        .collection(FirestoreCollections.scannedProducts)
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ScannedProductModel.fromFirestore(doc))
              .toList(),
        );
  }

  // ========================================
  // DISPOSAL PRODUCTS TABLE OPERATIONS
  // ========================================

  /// Add a disposal product
  Future<String> addDisposalProduct(DisposalProductModel product) async {
    final docRef = await _firestore
        .collection(FirestoreCollections.disposalProducts)
        .add(product.toFirestore());
    return docRef.id;
  }

  /// Get disposal products for a user
  Future<List<DisposalProductModel>> getUserDisposalProducts(
    String userId,
  ) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.disposalProducts)
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => DisposalProductModel.fromFirestore(doc))
        .toList();
  }

  /// Stream of user's disposal products
  Stream<List<DisposalProductModel>> streamUserDisposalProducts(String userId) {
    return _firestore
        .collection(FirestoreCollections.disposalProducts)
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => DisposalProductModel.fromFirestore(doc))
              .toList(),
        );
  }

  // ========================================
  // ALTERNATIVE PRODUCTS TABLE OPERATIONS
  // ========================================

  /// Add an alternative product
  Future<String> addAlternativeProduct(AlternativeProductModel product) async {
    final docRef = await _firestore
        .collection(FirestoreCollections.alternativeProducts)
        .add(product.toFirestore());
    return docRef.id;
  }

  /// Get alternative products for a base product
  Future<List<AlternativeProductModel>> getAlternativeProducts(
    String baseProductId,
  ) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.alternativeProducts)
        .where('baseProductId', isEqualTo: baseProductId)
        .get();

    return snapshot.docs
        .map((doc) => AlternativeProductModel.fromFirestore(doc))
        .toList();
  }

  /// Get all alternative products in a category
  Future<List<AlternativeProductModel>> getAlternativesByCategory(
    String category,
  ) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.alternativeProducts)
        .where('category', isEqualTo: category)
        .get();

    return snapshot.docs
        .map((doc) => AlternativeProductModel.fromFirestore(doc))
        .toList();
  }

  // ========================================
  // ECO CHALLENGES TABLE OPERATIONS
  // ========================================

  /// Add an eco challenge
  Future<String> addEcoChallenge(EcoChallengeModel challenge) async {
    final docRef = await _firestore
        .collection(FirestoreCollections.ecoChallenges)
        .add(challenge.toFirestore());
    return docRef.id;
  }

  /// Get active challenges for a specific date
  Future<List<EcoChallengeModel>> getActiveChallenges(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snapshot = await _firestore
        .collection(FirestoreCollections.ecoChallenges)
        .where('isActive', isEqualTo: true)
        .where(
          'dateAvailable',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where('dateAvailable', isLessThan: Timestamp.fromDate(endOfDay))
        .get();

    return snapshot.docs
        .map((doc) => EcoChallengeModel.fromFirestore(doc))
        .toList();
  }

  /// Stream of active challenges
  Stream<List<EcoChallengeModel>> streamActiveChallenges() {
    return _firestore
        .collection(FirestoreCollections.ecoChallenges)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => EcoChallengeModel.fromFirestore(doc))
              .toList(),
        );
  }

  // ========================================
  // USER CHALLENGES TABLE OPERATIONS
  // ========================================

  /// Record user challenge completion
  Future<void> completeUserChallenge(UserChallengeModel userChallenge) async {
    final docId = '${userChallenge.userId}-${userChallenge.challengeId}';
    await _firestore
        .collection(FirestoreCollections.userChallenges)
        .doc(docId)
        .set(userChallenge.toFirestore(), SetOptions(merge: true));
  }

  /// Get user's completed challenges
  Future<List<UserChallengeModel>> getUserCompletedChallenges(
    String userId,
  ) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.userChallenges)
        .where('userId', isEqualTo: userId)
        .where('isCompleted', isEqualTo: true)
        .orderBy('date', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => UserChallengeModel.fromFirestore(doc))
        .toList();
  }

  /// Check if user completed a specific challenge
  Future<bool> hasUserCompletedChallenge(
    String userId,
    String challengeId,
  ) async {
    final docId = '$userId-$challengeId';
    final doc = await _firestore
        .collection(FirestoreCollections.userChallenges)
        .doc(docId)
        .get();

    if (doc.exists) {
      final data = doc.data();
      return data?['isCompleted'] ?? false;
    }
    return false;
  }

  // ========================================
  // ECO POINT HISTORY TABLE OPERATIONS
  // ========================================

  /// Add point history record
  Future<void> addPointHistory(EcoPointHistoryModel history) async {
    // Add to global collection
    await _firestore
        .collection(FirestoreCollections.ecoPointHistory)
        .add(history.toFirestore());

    // Also add to user's subcollection for easy access
    await _firestore
        .collection(FirestoreCollections.users)
        .doc(history.userId)
        .collection(FirestoreCollections.pointHistory)
        .add(history.toFirestore());
  }

  /// Get user's point history
  Future<List<EcoPointHistoryModel>> getUserPointHistory(String userId) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.users)
        .doc(userId)
        .collection(FirestoreCollections.pointHistory)
        .orderBy('dateEarned', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => EcoPointHistoryModel.fromFirestore(doc))
        .toList();
  }

  /// Stream of user's point history
  Stream<List<EcoPointHistoryModel>> streamUserPointHistory(String userId) {
    return _firestore
        .collection(FirestoreCollections.users)
        .doc(userId)
        .collection(FirestoreCollections.pointHistory)
        .orderBy('dateEarned', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => EcoPointHistoryModel.fromFirestore(doc))
              .toList(),
        );
  }

  /// Get total points earned by source
  Future<Map<String, int>> getPointsBySource(String userId) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.users)
        .doc(userId)
        .collection(FirestoreCollections.pointHistory)
        .get();

    final pointsBySource = <String, int>{};

    for (final doc in snapshot.docs) {
      final history = EcoPointHistoryModel.fromFirestore(doc);
      pointsBySource[history.source] =
          (pointsBySource[history.source] ?? 0) + history.pointsEarned;
    }

    return pointsBySource;
  }

  // ========================================
  // BATCH OPERATIONS
  // ========================================

  /// Initialize user profile with default values
  Future<void> initializeUserProfile(
    String userId,
    String name,
    String email,
  ) async {
    final user = UserModel(
      userId: userId,
      name: name,
      email: email,
      dateJoined: DateTime.now(),
    );

    await createUser(user);
  }

  /// Get all data for a user (for export/backup)
  Future<Map<String, dynamic>> getUserData(String userId) async {
    final user = await getUser(userId);
    final scannedProducts = await getUserScannedProducts(userId);
    final disposalProducts = await getUserDisposalProducts(userId);
    final completedChallenges = await getUserCompletedChallenges(userId);
    final pointHistory = await getUserPointHistory(userId);

    return {
      'user': user?.toFirestore(),
      'scannedProducts': scannedProducts.map((p) => p.toFirestore()).toList(),
      'disposalProducts': disposalProducts.map((p) => p.toFirestore()).toList(),
      'completedChallenges': completedChallenges
          .map((c) => c.toFirestore())
          .toList(),
      'pointHistory': pointHistory.map((h) => h.toFirestore()).toList(),
    };
  }
}
