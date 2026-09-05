import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ecopilot/utils/constants.dart';
import 'package:ecopilot/screens/disposal_guidance_screen.dart';

class RecentDisposalScreen extends StatefulWidget {
  const RecentDisposalScreen({super.key});

  @override
  State<RecentDisposalScreen> createState() => _RecentDisposalScreenState();
}

class _RecentDisposalScreenState extends State<RecentDisposalScreen> {
  // UI listens to Firestore snapshots; no local state required.
  // The previous manual loader is replaced by a real-time snapshot listener
  // inside the build method so the UI updates automatically after saving.

  Widget _buildRecentProductTile(Map<String, dynamic> product) {
    final String name = product['name'] ?? 'Scanned product';
    final String category = product['category'] ?? 'N/A';
    final String material = product['material'] ?? 'Unknown';
    final String imageUrl = product['imageUrl'] ?? '';
    final dynamic createdAt = product['createdAt'];

    // Get eco score as string (letter grade: A, B, C, D, E)
    final dynamic rawEcoScore = product['eco_score'] ?? product['ecoScore'];
    String ecoScoreGrade = 'N/A';

    if (rawEcoScore != null) {
      final scoreStr = rawEcoScore.toString().trim().toUpperCase();
      // If it's already a letter grade, use it
      if (scoreStr.length == 1 && 'ABCDE'.contains(scoreStr)) {
        ecoScoreGrade = scoreStr;
      } else if (scoreStr != 'N/A' && scoreStr.isNotEmpty) {
        // If it's a number, convert to grade
        final scoreNum = int.tryParse(scoreStr);
        if (scoreNum != null) {
          if (scoreNum >= 80) {
            ecoScoreGrade = 'A';
          } else if (scoreNum >= 60) {
            ecoScoreGrade = 'B';
          } else if (scoreNum >= 40) {
            ecoScoreGrade = 'C';
          } else if (scoreNum >= 20) {
            ecoScoreGrade = 'D';
          } else if (scoreNum > 0) {
            ecoScoreGrade = 'E';
          }
        } else {
          // Use first character if it's a valid grade letter
          final firstChar = scoreStr.isNotEmpty ? scoreStr[0] : '';
          if ('ABCDE'.contains(firstChar)) {
            ecoScoreGrade = firstChar;
          }
        }
      }
    }

    // Format date/time
    String formattedDateTime = 'Recently';
    if (createdAt != null) {
      DateTime dt;
      if (createdAt is Timestamp) {
        dt = createdAt.toDate();
      } else if (createdAt is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
      } else {
        dt = DateTime.now();
      }
      formattedDateTime =
          '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }

    // Get eco score color based on grade
    Color getEcoScoreColor(String grade) {
      final ecoScoreColors = {
        'A': kResultCardGreen,
        'B': kDiscoverMoreGreen,
        'C': kPrimaryYellow,
        'D': kRankSustainabilityHero,
        'E': kWarningRed,
        'N/A': Colors.grey.shade600,
      };
      return ecoScoreColors[grade] ?? Colors.grey.shade600;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.grey.shade50],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: kPrimaryGreen.withOpacity(0.15),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: kPrimaryGreen.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      DisposalGuidanceScreen(productId: product['id']),
                ),
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Product Image with Hero animation
                  Hero(
                    tag: 'disposal_${product['id']}',
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            kPrimaryGreen.withOpacity(0.05),
                            kPrimaryGreen.withOpacity(0.02),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: imageUrl.isNotEmpty
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            kPrimaryGreen.withOpacity(0.2),
                                            kPrimaryGreen.withOpacity(0.1),
                                          ],
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.delete_sweep_outlined,
                                        color: kPrimaryGreen.withOpacity(0.6),
                                        size: 40,
                                      ),
                                    ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      kPrimaryGreen.withOpacity(0.2),
                                      kPrimaryGreen.withOpacity(0.1),
                                    ],
                                  ),
                                ),
                                child: Icon(
                                  Icons.delete_sweep_outlined,
                                  color: kPrimaryGreen.withOpacity(0.6),
                                  size: 40,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Product Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Product Name with better typography
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        // Category Badge with modern design
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                kPrimaryGreen.withOpacity(0.15),
                                kPrimaryGreen.withOpacity(0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: kPrimaryGreen.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.category_outlined,
                                size: 12,
                                color: kPrimaryGreen,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  category,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: kPrimaryGreen,
                                    letterSpacing: 0.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Material Info
                        Row(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 14,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                material,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Date/Time with icon
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_outlined,
                              size: 14,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formattedDateTime,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Eco Score Badge - Elegant design
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          getEcoScoreColor(ecoScoreGrade),
                          getEcoScoreColor(ecoScoreGrade).withOpacity(0.8),
                        ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: getEcoScoreColor(
                            ecoScoreGrade,
                          ).withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          ecoScoreGrade,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'ECO',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withOpacity(0.95),
                            letterSpacing: 1,
                          ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryGreen,
      appBar: AppBar(
        title: const Text(
          'Recent Disposal',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: kPrimaryGreen,
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        // The main content area with a rounded white background
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(25),
            topRight: Radius.circular(25),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x0F1DB954), Colors.white],
          ),
        ),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          // Listen to the user's per-user scans collection where isDisposal==true.
          // Many save paths (saveUserScan) write to `users/{uid}/scans`.
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser?.uid ?? 'anonymous')
              .collection('scans')
              .where('isDisposal', isEqualTo: true)
              .limit(50)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            kPrimaryGreen.withOpacity(0.1),
                            kPrimaryGreen.withOpacity(0.05),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.delete_sweep_outlined,
                        size: 80,
                        color: kPrimaryGreen,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'No Disposal History',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Text(
                        'Start scanning products to get disposal guidance and track your eco-friendly actions!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade600,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // Map documents to UI items and normalize fields saved under
            // different keys by various save flows. This handles records
            // written by `saveUserScan` (users/{uid}/scans) and similar writers.
            final rawItems = snapshot.data!.docs.map((doc) {
              final data = doc.data();
              final name =
                  data['product_name'] ?? data['name'] ?? 'Scanned product';
              final category = data['category'] ?? 'N/A';
              final material =
                  data['material'] ?? data['packaging'] ?? 'Unknown';
              final imageUrl =
                  (data['image_url'] ?? data['imageUrl'] ?? data['image'] ?? '')
                      ?.toString() ??
                  '';
              final createdAt =
                  data['createdAt'] ??
                  data['timestamp'] ??
                  data['scannedAt'];

              // Extract eco_score from multiple possible field names
              final ecoScore = data['eco_score'] ?? data['ecoScore'] ?? 'N/A';

              return {
                'id': doc.id,
                'name': name,
                'category': category,
                'material': material,
                'imageUrl': imageUrl.isNotEmpty
                    ? imageUrl
                    : 'https://placehold.co/100x120/A8D8B9/212121?text=Product',
                'createdAt': createdAt,
                'eco_score': ecoScore, // Add eco_score to the map
                'ecoScore': ecoScore, // Add both variations for compatibility
              };
            }).toList();

            // Deduplicate entries client-side. Multiple save paths may write
            // separate documents representing the same scanned product. Use
            // a stable key (name + imageUrl) and keep the most recent item.
            int millisFrom(dynamic ts) {
              if (ts == null) return 0;
              if (ts is Timestamp) return ts.millisecondsSinceEpoch;
              if (ts is int) return ts;
              if (ts is String) return int.tryParse(ts) ?? 0;
              return 0;
            }

            final Map<String, Map<String, dynamic>> unique = {};
            for (final item in rawItems) {
              final key = '${item['name'] ?? ''}::${item['imageUrl'] ?? ''}';
              if (!unique.containsKey(key)) {
                unique[key] = Map<String, dynamic>.from(item);
              } else {
                // Keep the most recent by createdAt
                final existing = unique[key]!;
                if (millisFrom(item['createdAt']) >
                    millisFrom(existing['createdAt'])) {
                  unique[key] = Map<String, dynamic>.from(item);
                }
              }
            }

            final items = unique.values.toList();

            // Sort client-side by timestamp if present (descending)
            items.sort(
              (a, b) => millisFrom(
                b['createdAt'],
              ).compareTo(millisFrom(a['createdAt'])),
            );

            return ListView.builder(
              padding: const EdgeInsets.only(top: 20, bottom: 20),
              itemCount: items.length,
              itemBuilder: (context, index) {
                return _buildRecentProductTile(items[index]);
              },
            );
          },
        ),
      ),
    );
  }
}
