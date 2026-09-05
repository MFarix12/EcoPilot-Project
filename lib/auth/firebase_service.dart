import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Added for Firestore
import 'package:intl/intl.dart';
import 'package:ecopilot/utils/rank_utils.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// A comprehensive Firebase service class handling:
/// 1. Firebase Authentication (Email/Password, Google, Facebook, Apple).
/// 2. Firebase Storage (Profile Photo Upload).
/// 3. Cloud Firestore (User Profiles, Scanned Products, Challenges, Notifications).
class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance; // Added Firestore

  /// Returns the currently signed in [User], or null if not signed in.
  User? get currentUser => _auth.currentUser;

  /// Returns the current user's UID, or an empty string if not signed in.
  String get currentUserId => _auth.currentUser?.uid ?? '';

  // ===============================================
  // 🔰 AUTHENTICATION (From Version 1) 🔰
  // ===============================================

  // Top-level helper used by compute() to perform image resizing and JPEG encoding
  // in a background isolate. Keep this function top-level so compute() can call it.
  Uint8List _encodeResizeJpeg(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;

      // Resize to a smaller width to prioritize speed and lower upload size.
      final resized = img.copyResize(decoded, width: 400);

      // Encode with lower quality to further reduce payload size for faster uploads.
      final encoded = img.encodeJpg(resized, quality: 50);
      return Uint8List.fromList(encoded);
    } catch (e) {
      // If decoding/encoding fails, return the original bytes so upload can still proceed.
      return bytes;
    }
  }

  Future<User?> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return credential.user;
  }

  Future<User?> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // If a display name was provided, update the user profile.
    if (fullName != null && credential.user != null) {
      await credential.user!.updateDisplayName(fullName);
      // Refresh the user to make sure displayName is available immediately.
      await credential.user!.reload();
      // Ensure the Firestore profile is created immediately after a successful sign-up
      await createUserProfile(fullName, email, credential.user!.photoURL ?? '');
      return _auth.currentUser;
    }

    // Ensure the Firestore profile is created for basic sign-up
    if (credential.user != null) {
      await createUserProfile(
        credential.user!.displayName ?? 'New User',
        email,
        credential.user!.photoURL ?? '',
      );
    }
    return credential.user;
  }

  Future<void> signOut() async {
    try {
      // Try to sign out from provider SDKs where applicable to fully clear tokens
      try {
        final google = GoogleSignIn();
        await google.signOut();
      } catch (_) {}

      try {
        await FacebookAuth.instance.logOut();
      } catch (_) {}

      await _auth.signOut();
    } catch (e) {
      debugPrint('signOut failed: $e');
      rethrow;
    }
  }

  /// Update the current user's password. This will fail if the user's
  /// credentials are too old and re-authentication is required.
  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user signed in');
    await user.updatePassword(newPassword);
    await user.reload();
  }

  /// Send a password reset email to the provided [email].
  ///
  /// Throws a [FirebaseAuthException] on failure.
  Future<void> sendPasswordReset({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      // Provide user-friendly error messages
      switch (e.code) {
        case 'user-not-found':
          throw Exception('No account found with this email address.');
        case 'invalid-email':
          throw Exception('Please enter a valid email address.');
        case 'too-many-requests':
          throw Exception('Too many attempts. Please try again later.');
        default:
          throw Exception('Failed to send reset email. Please try again.');
      }
    } catch (e) {
      throw Exception('An error occurred. Please check your connection.');
    }
  }

  // --- Social Sign-In Methods ---

  /// Sign in using Google. Supports web (popup) and mobile flows.
  Future<User?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();
        final userCredential = await _auth.signInWithPopup(googleProvider);
        if (userCredential.user != null) {
          await _handleSocialSignInProfile(userCredential.user!);
        }
        return userCredential.user;
      } else {
        final googleSignIn = GoogleSignIn();
        final account = await googleSignIn.signIn();
        if (account == null) return null; // User canceled

        final auth = await account.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: auth.accessToken,
          idToken: auth.idToken,
        );

        final userCredential = await _auth.signInWithCredential(credential);
        if (userCredential.user != null) {
          await _handleSocialSignInProfile(userCredential.user!);
        }
        return userCredential.user;
      }
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      rethrow;
    }
  }

  /// Sign in with Facebook.
  Future<User?> signInWithFacebook() async {
    try {
      if (kIsWeb) {
        final fbProvider = OAuthProvider('facebook.com');
        final userCredential = await _auth.signInWithPopup(fbProvider);
        if (userCredential.user != null) {
          await _handleSocialSignInProfile(userCredential.user!);
        }
        return userCredential.user;
      } else {
        final LoginResult result = await FacebookAuth.instance.login();
        if (result.status == LoginStatus.success &&
            result.accessToken != null) {
          final dynamic at = result.accessToken;
          final accessToken = at?.token ?? at?.accessToken ?? at?.value;
          final credential = FacebookAuthProvider.credential(
            accessToken as String,
          );
          final userCredential = await _auth.signInWithCredential(credential);
          if (userCredential.user != null) {
            await _handleSocialSignInProfile(userCredential.user!);
          }
          return userCredential.user;
        } else if (result.status == LoginStatus.cancelled) {
          return null;
        } else {
          throw Exception(result.message ?? 'Facebook sign-in failed');
        }
      }
    } catch (e) {
      debugPrint('Facebook sign-in failed: $e');
      rethrow;
    }
  }

  /// Sign in with Apple.
  Future<User?> signInWithApple() async {
    try {
      if (kIsWeb) {
        final appleProvider = OAuthProvider('apple.com');
        final userCredential = await _auth.signInWithPopup(appleProvider);
        if (userCredential.user != null) {
          await _handleSocialSignInProfile(userCredential.user!);
        }
        return userCredential.user;
      } else {
        final rawNonce = _generateNonce();
        final hashedNonce = _sha256ofString(rawNonce);

        final appleCredential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
          nonce: hashedNonce,
        );

        final oauthCredential = OAuthProvider('apple.com').credential(
          idToken: appleCredential.identityToken,
          rawNonce: rawNonce,
        );

        final userCredential = await _auth.signInWithCredential(
          oauthCredential,
        );
        if (userCredential.user != null) {
          await _handleSocialSignInProfile(userCredential.user!);
        }
        return userCredential.user;
      }
    } catch (e) {
      debugPrint('Apple sign-in failed: $e');
      rethrow;
    }
  }

  // Helper function to create Firestore profile after a successful social sign-in
  Future<void> _handleSocialSignInProfile(User user) async {
    await createUserProfile(
      user.displayName ?? 'New User',
      user.email ??
          '', // Email can be null for anonymous sign-in, though not for these providers
      user.photoURL ?? '',
    );
  }

  // Helpers for Apple sign-in nonce generation (from Version 1)
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = DateTime.now().microsecondsSinceEpoch;
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(charset[(random + i) % charset.length]);
    }
    return buffer.toString();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ===============================================
  // ✏️ USER PROFILE UPDATES (From Version 1 - Auth part) ✏️
  // ===============================================

  /// Update the current user's display name in Firebase Auth and Firestore.
  Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user signed in');
    await user.updateDisplayName(name);
    await user.reload();
    await updateUserProfile(name: name); // Update in Firestore
  }

  /// Update the current user's photo URL in Firebase Auth and Firestore.
  Future<void> updatePhotoUrl(String photoUrl) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user signed in');
    await user.updatePhotoURL(photoUrl);
    await user.reload();
    await updateUserProfile(photoUrl: photoUrl); // Update in Firestore
  }

  // ===============================================
  // ☁️ FIREBASE STORAGE (From Version 1) ☁️
  // ===============================================

  /// Upload a local file to Firebase Storage and return the download URL.
  Future<String> uploadProfilePhoto({
    File? file,
    Uint8List? bytes,
    String? fileName,
    void Function(int transferred, int total)? onProgress,
    int maxAttempts = 3,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('No user signed in');

      final uid = user.uid;
      final name =
          fileName ?? 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Prepare bytes (prefer provided bytes so callers can reuse them)
      Uint8List uploadBytes;
      if (bytes != null) {
        uploadBytes = bytes;
      } else if (file != null) {
        uploadBytes = await file.readAsBytes();
      } else {
        throw Exception('No image data provided for upload');
      }

      // Adaptive sizing: if already small, skip resizing. Threshold 80KB.
      try {
        if (uploadBytes.length > 80 * 1024) {
          uploadBytes = await compute(_encodeResizeJpeg, uploadBytes);
        }
      } catch (e) {
        debugPrint('Image processing failed, using original bytes. Error: $e');
      }

      // Upload to Cloudinary (unsigned preset) using HTTP multipart upload.
      final cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
      final uploadPreset = dotenv.env['CLOUDINARY_UPLOAD_PRESET'] ?? '';
      if (cloudName.isEmpty || uploadPreset.isEmpty) {
        throw Exception(
          'Cloudinary configuration missing. Set CLOUDINARY_CLOUD_NAME and CLOUDINARY_UPLOAD_PRESET in .env',
        );
      }

      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      );

      int attempt = 0;
      int backoffMs = 500;
      while (true) {
        attempt++;
        try {
          final request = http.MultipartRequest('POST', uri);
          request.fields['upload_preset'] = uploadPreset;
          request.fields['folder'] = 'profile_photos/$uid';
          request.files.add(
            http.MultipartFile.fromBytes('file', uploadBytes, filename: name),
          );

          final streamed = await request.send();
          if (onProgress != null) {
            onProgress(uploadBytes.length, uploadBytes.length);
          }

          final respStr = await streamed.stream.bytesToString();
          if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
            throw Exception(
              'Cloudinary upload failed: ${streamed.statusCode} $respStr',
            );
          }
          final Map<String, dynamic> decoded = jsonDecode(respStr);
          final url = decoded['secure_url'] as String?;
          if (url == null || url.isEmpty) {
            throw Exception('Cloudinary response missing secure_url');
          }

          await updatePhotoUrl(url);
          return url;
        } catch (e) {
          debugPrint('Cloudinary upload attempt $attempt failed: $e');
          if (attempt >= maxAttempts) rethrow;
          await Future<void>.delayed(Duration(milliseconds: backoffMs));
          backoffMs *= 2;
        }
      }
    } catch (e) {
      debugPrint('Upload failed: $e');
      rethrow;
    }
  }

  /// Upload a scanned image (product scan) to Cloudinary and return the secure URL.
  Future<String> uploadScannedImage({
    File? file,
    Uint8List? bytes,
    String? fileName,
    void Function(int transferred, int total)? onProgress,
    int maxAttempts = 3,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('No user signed in');
      final uid = user.uid;

      final name =
          fileName ?? 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';

      Uint8List uploadBytes;
      if (bytes != null) {
        uploadBytes = bytes;
      } else if (file != null) {
        uploadBytes = await file.readAsBytes();
      } else {
        throw Exception('No image data provided for upload');
      }

      try {
        if (uploadBytes.length > 80 * 1024) {
          uploadBytes = await compute(_encodeResizeJpeg, uploadBytes);
        }
      } catch (e) {
        debugPrint('Image processing failed, using original bytes. Error: $e');
      }

      final cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
      final uploadPreset = dotenv.env['CLOUDINARY_UPLOAD_PRESET'] ?? '';
      if (cloudName.isEmpty || uploadPreset.isEmpty) {
        throw Exception(
          'Cloudinary configuration missing. Set CLOUDINARY_CLOUD_NAME and CLOUDINARY_UPLOAD_PRESET in .env',
        );
      }

      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      );

      int attempt = 0;
      int backoffMs = 500;
      while (true) {
        attempt++;
        try {
          final request = http.MultipartRequest('POST', uri);
          request.fields['upload_preset'] = uploadPreset;
          request.fields['folder'] = 'scanned_images/$uid';
          request.files.add(
            http.MultipartFile.fromBytes('file', uploadBytes, filename: name),
          );

          final streamed = await request.send();
          if (onProgress != null) {
            onProgress(uploadBytes.length, uploadBytes.length);
          }

          final respStr = await streamed.stream.bytesToString();
          if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
            throw Exception(
              'Cloudinary upload failed: ${streamed.statusCode} $respStr',
            );
          }
          final Map<String, dynamic> decoded = jsonDecode(respStr);
          final url = decoded['secure_url'] as String?;
          if (url == null || url.isEmpty) {
            throw Exception('Cloudinary response missing secure_url');
          }
          return url;
        } catch (e) {
          debugPrint(
            'Cloudinary scanned image upload attempt $attempt failed: $e',
          );
          if (attempt >= maxAttempts) rethrow;
          await Future<void>.delayed(Duration(milliseconds: backoffMs));
          backoffMs *= 2;
        }
      }
    } catch (e) {
      debugPrint('uploadScannedImage failed: $e');
      rethrow;
    }
  }

  // ===============================================
  // 📖 FIRESTORE - USER DATA (From Version 2) 📖
  // ===============================================

  Future<void> createUserProfile(
    String name,
    String email,
    String photoUrl,
  ) async {
    final uid = _auth.currentUser!.uid;

    final userRef = _firestore.collection('users').doc(uid);
    final existingUser = await userRef.get();

    // Only create profile if it doesn't exist yet
    if (!existingUser.exists) {
      // Generate a username from name (or use email prefix)
      String username = _generateUsername(name, email);

      // Default to the lowest rank title when creating a new profile
      await userRef.set({
        'userId': uid, // Store UID for reference
        'username': username, // Human-readable username
        'name': name,
        'email': email,
        'photoUrl': photoUrl,
        'ecoPoints': 0, // Changed from ecoScore to ecoPoints
        'title': 'Green Beginner',
        'streakCount':
            0, // Changed from streakDays to streakCount to match Firestore rules
        'streak': 0,
        'lastChallengeDate': null, // Track last challenge completion
        'createdAt': Timestamp.now(),
      });
    }
  }

  /// Generate a username from display name or email
  String _generateUsername(String name, String email) {
    // Remove spaces and special characters from name
    String username = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    // If name is empty or too short, use email prefix
    if (username.isEmpty || username.length < 3) {
      username = email
          .split('@')[0]
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
    }

    // Limit to 20 characters
    if (username.length > 20) {
      username = username.substring(0, 20);
    }

    return username.isEmpty
        ? 'user${DateTime.now().millisecondsSinceEpoch}'
        : username;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getUserProfile() async {
    final uid = _auth.currentUser!.uid;
    return _firestore.collection('users').doc(uid).get();
  }

  /// Return a small summary for the user used by UI (streak, ecoPoints, etc.).
  /// If the document doesn't exist, returns defaults.
  /// Also validates and resets streak if user missed days.
  Future<Map<String, dynamic>> getUserSummary(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data() ?? {};

      // Validate streak based on last challenge completion date
      int streak = data['streak'] ?? data['streakDays'] ?? 0;
      final lastChallengeDate = data['lastChallengeDate'] as String?;

      // MIGRATION: If streak exists but no lastChallengeDate, reset to 0
      if (streak > 0 && lastChallengeDate == null) {
        debugPrint(
          '⚠️ Streak exists ($streak) but no lastChallengeDate found. Resetting to 0 for migration.',
        );
        streak = 0;
        await _firestore.collection('users').doc(uid).set({
          'streak': 0,
          'lastChallengeDate': null,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (streak > 0 && lastChallengeDate != null) {
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final yesterday = DateFormat(
          'yyyy-MM-dd',
        ).format(DateTime.now().subtract(const Duration(days: 1)));

        // Reset streak if user missed a day
        if (lastChallengeDate != today && lastChallengeDate != yesterday) {
          streak = 0;
          // Update Firestore to reflect the reset
          await _firestore.collection('users').doc(uid).set({
            'streak': 0,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          debugPrint(
            'Streak reset to 0: Last completion was $lastChallengeDate, today is $today',
          );
        }
      }

      final ecoPoints = data['ecoPoints'] ?? 0;
      final totalPoints =
          data['totalPoints'] ?? ecoPoints; // For backward compatibility
      final username = data['username'] ?? data['name'] ?? 'User';
      return {
        'streak': streak,
        'ecoPoints': ecoPoints,
        'totalPoints': totalPoints,
        'ecoScore': ecoPoints, // Keep for backward compatibility
        'username': username,
        'profile': data,
      };
    } catch (e) {
      debugPrint('getUserSummary failed: $e');
      return {
        'streak': 0,
        'ecoPoints': 0,
        'totalPoints': 0,
        'ecoScore': 0,
        'username': 'User',
        'profile': {},
      };
    }
  }

  Future<void> updateUserProfile({String? name, String? photoUrl}) async {
    final uid = _auth.currentUser!.uid;
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;

    if (updates.isNotEmpty) {
      await _firestore.collection('users').doc(uid).update(updates);
    }
  }

  Future<void> updateEcoScore(int points) async {
    final uid = _auth.currentUser!.uid;
    final userRef = _firestore.collection('users').doc(uid);
    final userDoc = await userRef.get();

    if (userDoc.exists) {
      final currentScore = (userDoc.data()?['ecoPoints'] ?? 0) as int;
      final newScore = currentScore + points;

      // Compute a new title based on the new score
      final rank = rankForPoints(newScore);

      await userRef.update({'ecoPoints': newScore, 'title': rank.title});
    }
  }

  /// Return a simple leaderboard of users ordered by ecoPoints desc.
  /// Each entry will include the user's document data plus the uid.
  Future<List<Map<String, dynamic>>> getLeaderboard({int limit = 50}) async {
    try {
      debugPrint('Fetching leaderboard with limit: $limit');
      // Try to query with orderBy first - force server fetch to get latest data
      final snapshot = await _firestore
          .collection('users')
          .orderBy('ecoPoints', descending: true)
          .limit(limit)
          .get(const GetOptions(source: Source.server));

      debugPrint(
        'Leaderboard query returned ${snapshot.docs.length} documents',
      );

      final results = snapshot.docs.map((d) {
        final data = d.data();
        final points = data['ecoPoints'] ?? 0;
        final username = data['username'] ?? data['name'] ?? 'Anonymous';
        return {
          'uid': d.id,
          'username': username,
          'name': data['name'] ?? data['displayName'] ?? 'Anonymous',
          'photoUrl': data['photoUrl'] ?? '',
          'ecoScore': points, // For backward compatibility
          'ecoPoints': points,
          'title': data['title'] ?? '',
        };
      }).toList();

      // Sort manually by ecoScore
      results.sort(
        (a, b) => (b['ecoScore'] as int).compareTo(a['ecoScore'] as int),
      );
      debugPrint('Returning ${results.length} users in leaderboard');
      return results;
    } catch (e) {
      debugPrint('Error in getLeaderboard with orderBy, falling back: $e');

      // Fallback: Get all users and sort manually
      try {
        final snapshot = await _firestore
            .collection('users')
            .limit(limit)
            .get();

        final results = snapshot.docs.map((d) {
          final data = d.data();
          final points = data['ecoPoints'] ?? 0;
          final username = data['username'] ?? data['name'] ?? 'Anonymous';
          return {
            'uid': d.id,
            'username': username,
            'name': data['name'] ?? data['displayName'] ?? 'Anonymous',
            'photoUrl': data['photoUrl'] ?? '',
            'ecoScore': points, // For backward compatibility
            'ecoPoints': points,
            'title': data['title'] ?? '',
          };
        }).toList();

        // Sort by ecoScore manually
        results.sort(
          (a, b) => (b['ecoScore'] as int).compareTo(a['ecoScore'] as int),
        );
        return results;
      } catch (fallbackError) {
        debugPrint('Fallback also failed: $fallbackError');
        return []; // Return empty list if everything fails
      }
    }
  }

  /// Get weekly leaderboard by calculating points from point_history in the last 7 days
  Future<List<Map<String, dynamic>>> getWeeklyLeaderboard({
    int limit = 50,
  }) async {
    try {
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      debugPrint(
        '🔍 Fetching weekly leaderboard (last 7 days from ${DateFormat('yyyy-MM-dd').format(sevenDaysAgo)})',
      );

      // Get all users
      final usersSnapshot = await _firestore.collection('users').get();
      debugPrint('👥 Total users found: ${usersSnapshot.docs.length}');

      final userPointsMap = <String, Map<String, dynamic>>{};
      int usersChecked = 0;
      int usersWithPoints = 0;

      // For each user, calculate their points from point_history in the last 7 days
      for (final userDoc in usersSnapshot.docs) {
        final userId = userDoc.id;
        final userData = userDoc.data();
        usersChecked++;

        // Query point_history for entries in the last 7 days
        final pointHistorySnapshot = await _firestore
            .collection('users')
            .doc(userId)
            .collection('point_history')
            .where(
              'timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(sevenDaysAgo),
            )
            .get();

        // Sum up all points from the last 7 days
        int weeklyPoints = 0;
        for (final historyDoc in pointHistorySnapshot.docs) {
          final points = historyDoc.data()['points'] ?? 0;
          weeklyPoints += points as int;
        }

        if (weeklyPoints > 0) {
          usersWithPoints++;
          userPointsMap[userId] = {
            'uid': userId,
            'username': userData['username'] ?? userData['name'] ?? 'Anonymous',
            'name': userData['name'] ?? userData['displayName'] ?? 'Anonymous',
            'photoUrl': userData['photoUrl'] ?? '',
            'ecoScore': weeklyPoints,
            'ecoPoints': weeklyPoints,
            'title': userData['title'] ?? '',
          };
          debugPrint(
            '  ✓ ${userData['name']}: $weeklyPoints points (last 7 days)',
          );
        }
      }

      debugPrint(
        '📊 Weekly summary: $usersWithPoints/$usersChecked users have activity in the last 7 days',
      );

      // Convert to list and sort
      final results = userPointsMap.values.toList();
      results.sort(
        (a, b) => (b['ecoScore'] as int).compareTo(a['ecoScore'] as int),
      );

      debugPrint('✅ Weekly leaderboard: ${results.length} users with activity');
      return results.take(limit).toList();
    } catch (e) {
      debugPrint('❌ Error fetching weekly leaderboard: $e');
      return [];
    }
  }

  /// Get monthly leaderboard by reading from monthly_points collection
  /// (same source as addEcoPoints writes to and home screen reads from)
  Future<List<Map<String, dynamic>>> getMonthlyLeaderboard({
    int limit = 50,
  }) async {
    try {
      final now = DateTime.now();
      final monthKey = DateFormat('yyyy-MM').format(now);
      debugPrint('🔍 Fetching monthly leaderboard for $monthKey');

      // Get all users - force server fetch to get latest data
      final usersSnapshot = await _firestore
          .collection('users')
          .get(const GetOptions(source: Source.server));
      debugPrint('👥 Total users found: ${usersSnapshot.docs.length}');

      final userPointsMap = <String, Map<String, dynamic>>{};
      int usersChecked = 0;
      int usersWithPoints = 0;

      // For each user, read their monthly points directly from monthly_points document
      for (final userDoc in usersSnapshot.docs) {
        final userId = userDoc.id;
        final userData = userDoc.data();
        usersChecked++;

        int monthlyPoints = 0;

        try {
          // Read monthly points from the same location addEcoPoints writes to
          final monthlyDoc = await _firestore
              .collection('users')
              .doc(userId)
              .collection('monthly_points')
              .doc(monthKey)
              .get();

          if (monthlyDoc.exists) {
            final data = monthlyDoc.data();
            monthlyPoints = data?['points'] ?? 0;
          }

          debugPrint(
            '  ✓ ${userData['name']}: $monthlyPoints points this month',
          );
        } catch (e) {
          debugPrint(
            '  ❌ Error fetching monthly_points for user ${userData['name']}: $e',
          );
          // Continue with 0 points even if error occurs
        }

        // Add all users to the leaderboard, even with 0 monthly points
        if (monthlyPoints > 0) {
          usersWithPoints++;
        }

        userPointsMap[userId] = {
          'uid': userId,
          'username': userData['username'] ?? userData['name'] ?? 'Anonymous',
          'name': userData['name'] ?? userData['displayName'] ?? 'Anonymous',
          'photoUrl': userData['photoUrl'] ?? '',
          'ecoScore': monthlyPoints,
          'ecoPoints': monthlyPoints,
          'title': userData['title'] ?? '',
        };
      }

      debugPrint(
        '📊 Monthly summary: $usersWithPoints/$usersChecked users have activity in $monthKey',
      );

      // Convert to list and sort by points
      final results = userPointsMap.values.toList();
      results.sort(
        (a, b) => (b['ecoScore'] as int).compareTo(a['ecoScore'] as int),
      );

      debugPrint(
        '✅ Monthly leaderboard: ${results.length} users, showing top $limit',
      );
      return results.take(limit).toList();
    } catch (e) {
      debugPrint('❌ Error fetching monthly leaderboard: $e');
      return [];
    }
  }

  // ===============================================
  // 📦 FIRESTORE - SCANNED PRODUCTS (From Version 2) 📦
  // ===============================================

  Future<void> saveScannedProduct({
    required String productName,
    required String ecoScore,
    required String imageUrl,
    required String packaging,
    required String disposalMethod,
    double? carbonFootprint,
    String? barcode,
  }) async {
    final uid = _auth.currentUser!.uid;

    // Save under users/{uid}/scans for per-user history (centralized location).
    final scansRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('scans');
    await scansRef.add({
      'analysis':
          '', // legacy callers may not pass raw analysis; keep empty by default
      'product_name': productName,
      'eco_score': ecoScore,
      'barcode': barcode ?? '',
      'carbon_footprint': carbonFootprint ?? 0.0,
      'packaging': packaging,
      'disposal_method': disposalMethod,
      'image_url': imageUrl,
      'timestamp': Timestamp.now(),
      'date': DateTime.now().toIso8601String(),
    });

    // Also keep the legacy global collection for compatibility (optional).
    await _firestore.collection('scanned_products').add({
      'userId': uid,
      'productName': productName,
      'ecoScore': ecoScore,
      'barcode': barcode ?? '',
      'carbonFootprint': carbonFootprint ?? 0.0,
      'packaging': packaging,
      'disposalMethod': disposalMethod,
      'imageUrl': imageUrl,
      'scannedAt': Timestamp.now(),
    });
  }

  /// Save a user scan with analysis text and optional image URL to per-user scans.
  Future<void> saveUserScan({
    required String analysis,
    required String productName,
    required String ecoScore,
    required String carbonFootprint,
    String? imageUrl,
    String? category,
    String? ingredients,
    String? packagingType,
    List<dynamic>? disposalSteps,
    String? tips,
    String? nearbyCenter,
    bool isDisposal = false,
    bool? containsMicroplastics,
    bool? palmOilDerivative,
    bool? crueltyFree,
  }) async {
    // Allow saving scans even when no FirebaseAuth user is signed in by
    // falling back to the 'anonymous' UID. Callers (UI) already sometimes
    // write to users/anonymous directly, so make the helper consistent.
    final uid = _auth.currentUser?.uid ?? 'anonymous';
    final scansRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('scans');
    // Normalize disposalSteps and tips into lists for storage
    List<dynamic> disposalList = <dynamic>[];
    if (disposalSteps != null) {
      disposalList = List<dynamic>.from(disposalSteps);
    }

    List<String> tipsList = <String>[];
    if (tips != null) {
      if (tips.contains('\n')) {
        tipsList = tips
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (tips.contains(',')) {
        tipsList = tips
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } else {
        tipsList = [tips.trim()];
      }
    }

    // Persist both camelCase and legacy snake_case/legacy keys for compatibility.
    await scansRef.add({
      // Raw analysis text produced by Gemini or API (kept for diagnostics)
      'analysis': analysis,
      'analysis_text': analysis,

      // Product name (both conventions)
      'product_name': productName,
      'productName': productName,
      'name': productName,

      // Eco score / carbon footprint (both conventions)
      'eco_score': ecoScore,
      'ecoScore': ecoScore,
      'carbon_footprint': carbonFootprint,
      'carbonFootprint': carbonFootprint,

      // Image URL (both conventions)
      'image_url': imageUrl,
      'imageUrl': imageUrl,

      // Category / packaging
      'category': category,
      'product_category': category,

      // Ingredients (both conventions)
      'ingredients': ingredients,
      'ingredient_list': ingredients,
      'ingredientList': ingredients,

      'packaging': packagingType,
      'packagingType': packagingType,

      // Disposal steps stored as an array plus a joined string
      'disposalSteps': disposalList.isNotEmpty ? disposalList : null,
      'disposal_method': disposalList.isNotEmpty
          ? disposalList.join('\n')
          : null,
      'disposalMethod': disposalList.isNotEmpty
          ? disposalList.join('\n')
          : null,

      // Tips stored as list and text
      'tips': tipsList.isNotEmpty ? tipsList : null,
      'tips_text': tipsList.isNotEmpty ? tipsList.join('\n') : null,

      // Nearby center
      'nearbyCenter': nearbyCenter,
      'nearby_center': nearbyCenter,

      'isDisposal': isDisposal,

      // Persist explicit boolean analysis flags (both camelCase and snake_case)
      'containsMicroplastics': containsMicroplastics ?? false,
      'contains_microplastics': containsMicroplastics ?? false,
      'palmOilDerivative': palmOilDerivative ?? false,
      'palm_oil_derivative': palmOilDerivative ?? false,
      'crueltyFree': crueltyFree ?? false,
      'cruelty_free': crueltyFree ?? false,

      // Timestamps
      'timestamp': FieldValue.serverTimestamp(),
      'date': DateFormat('yyyy-MM-dd – kk:mm').format(DateTime.now()),
    });

    // Reward 5 Eco Points for scanning a product (part of the reward system)
    // Daily limit: 10 scans, Weekly limit: 50 scans
    // This encourages engagement and discovery of eco-friendly products.
    if (_auth.currentUser != null) {
      try {
        await addEcoPoints(
          points: 5,
          reason: 'Product scan',
          activityType: 'scan_product',
        );
      } catch (e) {
        debugPrint('Failed to award points after scan: $e');
      }
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getUserRecentScans() {
    final uid = _auth.currentUser!.uid;
    return _firestore
        .collection('scanned_products')
        .where('userId', isEqualTo: uid)
        .orderBy('scannedAt', descending: true)
        .snapshots();
  }

  Future<List<Map<String, dynamic>>> getScannedProductsOnce() async {
    final uid = _auth.currentUser!.uid;
    final snapshot = await _firestore
        .collection('scanned_products')
        .where('userId', isEqualTo: uid)
        .orderBy('scannedAt', descending: true)
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  // ===============================================
  // 🌱 FIRESTORE - ALTERNATIVES (From Version 2) 🌱
  // ===============================================

  Future<List<Map<String, dynamic>>> getAlternatives(String forProduct) async {
    final snapshot = await _firestore
        .collection('alternatives')
        .where('forProduct', isEqualTo: forProduct)
        .get();

    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  Future<void> addAlternative({
    required String forProduct,
    required String alternativeName,
    required String ecoScore,
    required String reason,
    required String productUrl,
  }) async {
    await _firestore.collection('alternatives').add({
      'forProduct': forProduct,
      'alternativeName': alternativeName,
      'ecoScore': ecoScore,
      'reason': reason,
      'productUrl': productUrl,
      'createdAt': Timestamp.now(),
    });
  }

  // ===============================================
  // 🏆 FIRESTORE - DAILY CHALLENGES (From Version 2) 🏆
  // ===============================================

  Stream<QuerySnapshot<Map<String, dynamic>>> getDailyChallenges() {
    return _firestore
        .collection('challenges')
        .orderBy('date', descending: true)
        .snapshots();
  }

  Future<void> addChallenge({
    required String title,
    required String description,
    required int points,
    required String date,
  }) async {
    await _firestore.collection('challenges').add({
      'title': title,
      'description': description,
      'points': points,
      'date': date,
      'createdAt': Timestamp.now(),
    });
  }

  /// Mark a daily challenge as completed for the current user.
  ///
  /// This will create/update a document under `user_challenges/{uid}-{yyyy-MM-dd}`
  /// recording which challenges were completed and increment the user's eco score.
  /// Also updates monthly points and streak if all challenges are completed.
  Future<Map<String, dynamic>> completeChallenge({
    required int challengeIndex,
    required int points,
    required int totalChallenges,
    required List<bool> currentCompleted,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user signed in');

    final uid = user.uid;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      // 1. Get current user challenge progress
      final challengeDoc = await _firestore
          .collection('user_challenges')
          .doc('$uid-$today')
          .get();

      List<bool> completed = List.from(currentCompleted);
      int currentPoints = 0;

      if (challengeDoc.exists) {
        final data = challengeDoc.data();
        if (data != null) {
          completed =
              (data['completed'] as List<dynamic>?)
                  ?.map((e) => e == true)
                  .toList() ??
              completed;
          currentPoints = data['pointsEarned'] ?? 0;
        }
      }

      // Already completed -> nothing to do
      if (completed[challengeIndex] == true) {
        return {'success': false, 'message': 'Challenge already completed'};
      }

      // Mark as completed
      completed[challengeIndex] = true;
      final newPointsEarned = currentPoints + points;

      // Check if all challenges are now completed
      final allCompleted = completed.every((c) => c);

      // NO BONUS POINTS - Award only the challenge points
      int bonusPoints = 0;
      // Removed: Bonus points for completing all challenges
      // Users expect: 2 challenges × 5 points = 10 total (no bonus)

      // 2. Update user challenge progress
      await _firestore.collection('user_challenges').doc('$uid-$today').set({
        'completed': completed,
        'pointsEarned': newPointsEarned,
        'userId': uid,
        'date': today,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3. Get current user data
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};
      final currentEcoPoints = userData['ecoPoints'] ?? 0;
      final currentStreak = userData['streak'] ?? 0;
      final lastCompletedDate = userData['lastChallengeDate'] as String?;
      int updatedStreak = currentStreak;

      // Calculate streak based on consecutive days
      if (allCompleted) {
        final yesterday = DateFormat(
          'yyyy-MM-dd',
        ).format(DateTime.now().subtract(const Duration(days: 1)));

        if (lastCompletedDate == null) {
          // First time completing challenges
          updatedStreak = 1;
        } else if (lastCompletedDate == yesterday) {
          // Consecutive day - increment streak
          updatedStreak = currentStreak + 1;
        } else if (lastCompletedDate == today) {
          // Already completed today - keep current streak
          updatedStreak = currentStreak;
        } else {
          // Missed a day - reset streak to 1
          updatedStreak = 1;
          debugPrint(
            'Streak reset: Last completion was on $lastCompletedDate, today is $today',
          );
        }

        // Award streak milestone bonuses
        if (updatedStreak == 10 ||
            updatedStreak == 30 ||
            updatedStreak == 100 ||
            updatedStreak == 200) {
          await checkStreakBonus(updatedStreak);
        }

        // Trigger milestone notification for TikTok-style engagement
        if (updatedStreak == 7 ||
            updatedStreak == 14 ||
            updatedStreak == 30 ||
            updatedStreak == 50 ||
            updatedStreak == 100 ||
            updatedStreak == 200) {
          // Import and call StreakNotificationManager
          // This will be called from the UI layer after challenge completion
          debugPrint('🎉 Milestone reached: $updatedStreak days!');
        }
      }

      // 4. Award eco points using addEcoPoints to update all systems
      // (all-time, monthly, weekly, and point_history)
      // Note: Don't use activityType to avoid daily limit restriction
      // Each challenge has its own completion tracking
      await addEcoPoints(
        points: points + bonusPoints,
        reason: 'Daily challenge completed',
        activityType:
            null, // No activity limit - challenges track their own completion
      );

      // 5. Update user's streak and lastChallengeDate
      final updateData = <String, dynamic>{
        'streak': updatedStreak,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Only update lastChallengeDate if all challenges completed
      if (allCompleted) {
        updateData['lastChallengeDate'] = today;
      }

      await _firestore
          .collection('users')
          .doc(uid)
          .set(updateData, SetOptions(merge: true));

      debugPrint(
        'Challenge completed successfully: +$points points${bonusPoints > 0 ? ' (+$bonusPoints bonus)' : ''}',
      );

      return {
        'success': true,
        'pointsEarned': newPointsEarned,
        'totalEcoPoints': currentEcoPoints + points + bonusPoints,
        'streak': updatedStreak,
        'allCompleted': allCompleted,
        'completed': completed,
        'bonusPoints': bonusPoints,
      };
    } catch (e) {
      debugPrint('Error completing challenge: $e');
      rethrow;
    }
  }

  // ===============================================
  // 🎯 ECO POINTS REWARD SYSTEM 🎯
  // ===============================================

  /// Check if user has reached daily or weekly limit for a specific activity
  /// Returns true if user can still perform the activity, false if limit reached
  Future<bool> checkActivityLimit({
    required String activityType,
    required int dailyLimit,
    required int weeklyLimit,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final uid = user.uid;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDate = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    );

    try {
      // Query point history for this activity type
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('point_history')
          .where('activityType', isEqualTo: activityType)
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(weekStartDate),
          )
          .get();

      int dailyCount = 0;
      int weeklyCount = 0;

      for (var doc in snapshot.docs) {
        final timestamp = (doc.data()['timestamp'] as Timestamp).toDate();
        weeklyCount++;

        if (timestamp.isAfter(todayStart)) {
          dailyCount++;
        }
      }

      // Check limits
      if (dailyCount >= dailyLimit) {
        debugPrint(
          '⚠️ Daily limit reached for $activityType: $dailyCount/$dailyLimit',
        );
        return false;
      }

      if (weeklyCount >= weeklyLimit) {
        debugPrint(
          '⚠️ Weekly limit reached for $activityType: $weeklyCount/$weeklyLimit',
        );
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error checking activity limit: $e');
      return true; // Allow on error to not block users
    }
  }

  /// Private wrapper for checkActivityLimit (used internally by addEcoPoints)
  Future<bool> _checkActivityLimit(
    String activityType,
    int dailyLimit,
    int weeklyLimit,
  ) async {
    return checkActivityLimit(
      activityType: activityType,
      dailyLimit: dailyLimit,
      weeklyLimit: weeklyLimit,
    );
  }

  /// Award eco points to the current user for various actions.
  ///
  /// Point values (Updated System):
  /// - View daily eco tip: 3 points (Daily: 1, Weekly: 7)
  /// - Complete daily challenge: 20 points (Daily: 1, Weekly: 7)
  /// - Daily streak bonus: 10 points (Daily: 1, Weekly: 7)
  /// - Scan product: 5 points (Daily: 10, Weekly: 50)
  /// - First-time scan bonus: 5 points (Daily: 5, Weekly: 20)
  /// - Add new product: 30 points (Daily: 3, Weekly: 10)
  /// - Dispose/recycle: 10 points (Daily: 5, Weekly: 20)
  /// - Verified disposal bonus: 5 points (Daily: 5, Weekly: 20)
  /// - Weekly goal: 30 points, Monthly goal: 50 points
  /// - Daily cap: ~120 points, Weekly cap: ~700 points
  ///
  /// This method awards points to ALL THREE categories simultaneously:
  /// - Weekly eco points (resets every week)
  /// - Monthly eco points (resets every month)
  /// - Overall eco points (never resets, cumulative total)
  Future<void> addEcoPoints({
    required int points,
    required String reason,
    bool updateMonthly = true,
    String? activityType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('Cannot add points: No user signed in');
      return;
    }

    // Check activity limits if activityType is specified
    if (activityType != null) {
      final limits = _getActivityLimits(activityType);
      if (limits != null) {
        final canPerform = await _checkActivityLimit(
          activityType,
          limits['daily']!,
          limits['weekly']!,
        );

        if (!canPerform) {
          throw Exception(
            'Activity limit reached for $activityType. '
            'Daily limit: ${limits['daily']}, Weekly limit: ${limits['weekly']}',
          );
        }
      }
    }

    final uid = user.uid;
    final now = DateTime.now();
    final monthKey = DateFormat('yyyy-MM').format(now);
    // Week key format: Year-WeekNumber (e.g., "2025-01" for first week of 2025)
    final weekNumber =
        ((now.difference(DateTime(now.year, 1, 1)).inDays) / 7).floor() + 1;
    final weekKey = '${now.year}-${weekNumber.toString().padLeft(2, '0')}';

    try {
      // 1. Update OVERALL eco points (never resets, used for leaderboard/ranks)
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final currentOverallPoints = userDoc.data()?['ecoPoints'] ?? 0;
      final currentAvailablePoints = userDoc.data()?['availablePoints'] ?? 0;
      final newOverallPoints = currentOverallPoints + points;
      final newAvailablePoints = currentAvailablePoints + points;

      await _firestore.collection('users').doc(uid).set({
        'ecoPoints': newOverallPoints, // Total earned (for leaderboard/ranks)
        'availablePoints':
            newAvailablePoints, // Spendable points (for redemptions)
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. Update MONTHLY points (resets every month)
      int currentMonthlyPoints = 0;
      if (updateMonthly) {
        final monthlyDoc = await _firestore
            .collection('users')
            .doc(uid)
            .collection('monthly_points')
            .doc(monthKey)
            .get();

        currentMonthlyPoints = monthlyDoc.data()?['points'] ?? 0;

        await _firestore
            .collection('users')
            .doc(uid)
            .collection('monthly_points')
            .doc(monthKey)
            .set({
              'points': currentMonthlyPoints + points,
              'goal': 500,
              'month': monthKey,
              'updatedAt': FieldValue.serverTimestamp(),
              'createdAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }

      // 3. Update WEEKLY points (resets every week)
      final weeklyDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('weekly_points')
          .doc(weekKey)
          .get();

      final currentWeeklyPoints = weeklyDoc.data()?['points'] ?? 0;

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('weekly_points')
          .doc(weekKey)
          .set({
            'points': currentWeeklyPoints + points,
            'week': weekKey,
            'year': now.year,
            'weekNumber': weekNumber,
            'updatedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // 4. Log the point award in history (for tracking and daily/weekly limits)
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('point_history')
          .add({
            'points': points,
            'reason': reason,
            'activityType': activityType ?? 'general',
            'timestamp': FieldValue.serverTimestamp(),
            'newOverallTotal': newOverallPoints,
            'weekKey': weekKey,
            'monthKey': monthKey,
          });

      debugPrint(
        '✅ Awarded $points points for: $reason\n'
        '   Overall: $newOverallPoints | Weekly: ${currentWeeklyPoints + points} | Monthly: ${currentMonthlyPoints + points}',
      );
    } catch (e) {
      debugPrint('❌ Error adding eco points: $e');
    }
  }

  /// Check and award streak bonuses based on consecutive days
  /// Updated: 10 points for all milestone streaks (7, 14, 30, 50, 100, 200 days)
  Future<void> checkStreakBonus(int currentStreak) async {
    // Award bonus points at milestone streaks
    if (currentStreak == 7) {
      await addEcoPoints(
        points: 10,
        reason: '7-day streak bonus! 🔥',
        activityType: 'daily_streak_bonus',
      );
    } else if (currentStreak == 14) {
      await addEcoPoints(
        points: 10,
        reason: '14-day streak bonus! 🔥',
        activityType: 'daily_streak_bonus',
      );
    } else if (currentStreak == 30) {
      await addEcoPoints(
        points: 10,
        reason: '30-day streak bonus! 🔥',
        activityType: 'daily_streak_bonus',
      );
    } else if (currentStreak == 50) {
      await addEcoPoints(
        points: 10,
        reason: '50-day streak bonus! 🔥',
        activityType: 'daily_streak_bonus',
      );
    } else if (currentStreak == 100) {
      await addEcoPoints(
        points: 10,
        reason: '100-day streak bonus! 🔥',
        activityType: 'daily_streak_bonus',
      );
    } else if (currentStreak == 200) {
      await addEcoPoints(
        points: 10,
        reason: '200-day streak bonus! 🔥',
        activityType: 'daily_streak_bonus',
      );
    }
  }

  // ===============================================
  // 🔔 FIRESTORE - NOTIFICATIONS (From Version 2) 🔔
  // ===============================================

  Future<void> sendUserNotification(String message) async {
    final uid = _auth.currentUser!.uid;

    await _firestore.collection('notifications').add({
      'userId': uid,
      'message': message,
      'timestamp': Timestamp.now(),
      'isRead': false,
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getUserNotifications() {
    final uid = _auth.currentUser!.uid;
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).update({
      'isRead': true,
    });
  }

  // ===============================================
  // 📦 ACTIVITY LIMITS & HELPERS
  // ===============================================

  /// Get activity limits for different activity types
  /// Returns null if no limits are defined for the activity
  Map<String, int>? _getActivityLimits(String activityType) {
    switch (activityType) {
      case 'scan_product':
        return {'daily': 10, 'weekly': 50};
      case 'add_new_product':
        return {'daily': 3, 'weekly': 10};
      case 'first_time_scan':
        return {'daily': 5, 'weekly': 20};
      case 'dispose_product':
      case 'verified_disposal':
        return {'daily': 5, 'weekly': 20};
      case 'complete_daily_challenge':
      case 'daily_streak_bonus':
      case 'view_daily_tip':
        return {'daily': 1, 'weekly': 7};
      default:
        return null; // No limits for other activities
    }
  }
}
