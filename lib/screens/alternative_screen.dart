// AlternativeScreen - History display only
// For generating alternatives for newly scanned products, use BetterAlternativeScreen
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ecopilot/widgets/app_drawer.dart';
import 'package:ecopilot/widgets/bottom_navigation.dart';
import 'package:ecopilot/utils/constants.dart';
import 'home_screen.dart';
import 'scan_screen.dart';
import 'disposal_guidance_screen.dart';
import 'profile_screen.dart';
import 'product_wishlist_screen.dart';
import 'eco_assistant_screen.dart';

const Map<String, Color> _kEcoScoreColors = {
  'A+': Color(0xFF1DB954),
  'A': kResultCardGreen,
  'B': kDiscoverMoreGreen,
  'C': kPrimaryYellow,
  'D': kRankSustainabilityHero,
  'E': kWarningRed,
};

// ========================
// Data Models
// ========================

class AlternativeProduct {
  final String id;
  final String name;
  final String ecoScore;
  final String materialType;
  final String benefit;
  final String whereToBuy;
  final String carbonSavings;
  final String imagePath;
  final String buyLink;
  final String shortDescription;
  final String category;
  final double? price;
  final String? brand;
  final double? rating;
  final String? externalSource;

  AlternativeProduct({
    String? id,
    required this.name,
    required this.ecoScore,
    required this.materialType,
    required this.benefit,
    required this.whereToBuy,
    required this.carbonSavings,
    required this.imagePath,
    required this.buyLink,
    required this.shortDescription,
    this.category = '',
    this.price,
    this.brand,
    this.rating,
    this.externalSource,
  }) : id = id ?? _generateUniqueId(name, ecoScore, materialType, brand);

  // Generate consistent unique ID based on product properties
  static String _generateUniqueId(
    String name,
    String ecoScore,
    String materialType,
    String? brand,
  ) {
    final components = '${name}_${ecoScore}_${materialType}_${brand ?? ""}';
    return components.hashCode.abs().toString();
  }

  Map<String, dynamic> toFirestore({bool includeTimestamp = false}) {
    final data = {
      'name': name,
      'ecoScore': ecoScore,
      'materialType': materialType,
      'benefit': benefit,
      'whereToBuy': whereToBuy,
      'carbonSavings': carbonSavings,
      'imagePath': imagePath,
      'buyLink': buyLink,
      'shortDescription': shortDescription,
      'category': category,
      'price': price,
      'brand': brand,
      'rating': rating,
      'externalSource': externalSource,
    };

    if (includeTimestamp) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }

    return data;
  }

  factory AlternativeProduct.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AlternativeProduct(
      id: doc.id,
      name: data['name'] ?? '',
      ecoScore: data['ecoScore'] ?? 'N/A',
      materialType: data['materialType'] ?? '',
      benefit: data['benefit'] ?? '',
      whereToBuy: data['whereToBuy'] ?? '',
      carbonSavings: data['carbonSavings'] ?? '',
      imagePath: data['imagePath'] ?? '',
      buyLink: data['buyLink'] ?? '',
      shortDescription: data['shortDescription'] ?? '',
      category: data['category'] ?? '',
      price: data['price']?.toDouble(),
      brand: data['brand'],
      rating: data['rating']?.toDouble(),
      externalSource: data['externalSource'],
    );
  }
}

class ScannedProductWithAlternatives {
  final String productName;
  final String productBarcode;
  final String productCategory;
  final Timestamp timestamp;
  final List<AlternativeProduct> alternatives;

  ScannedProductWithAlternatives({
    required this.productName,
    required this.productBarcode,
    required this.productCategory,
    required this.timestamp,
    required this.alternatives,
  });
}

// ========================
// UI Components
// ========================

class EcoScoreBadge extends StatelessWidget {
  final String score;
  const EcoScoreBadge({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final color = _kEcoScoreColors[score] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Eco: $score',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class AlternativeProductCard extends StatelessWidget {
  final AlternativeProduct product;
  final VoidCallback? onTap;
  final VoidCallback? onBuyNow;
  final VoidCallback? onAddToWishlist;
  final bool isInWishlist;

  const AlternativeProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onBuyNow,
    this.onAddToWishlist,
    this.isInWishlist = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Image
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey.shade200,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: product.imagePath.isNotEmpty
                            ? (product.imagePath.startsWith('http')
                                  ? Image.network(
                                      product.imagePath,
                                      width: 110,
                                      height: 110,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return Center(
                                          child: SizedBox(
                                            width: 35,
                                            height: 35,
                                            child: CircularProgressIndicator(
                                              value:
                                                  loadingProgress
                                                          .expectedTotalBytes !=
                                                      null
                                                  ? loadingProgress
                                                            .cumulativeBytesLoaded /
                                                        loadingProgress
                                                            .expectedTotalBytes!
                                                  : null,
                                              strokeWidth: 2.5,
                                              color: kPrimaryGreen,
                                            ),
                                          ),
                                        );
                                      },
                                      errorBuilder: (ctx, err, st) =>
                                          _buildPlaceholder(),
                                    )
                                  : Image.asset(
                                      product.imagePath,
                                      width: 110,
                                      height: 110,
                                      fit: BoxFit.cover,
                                      errorBuilder: (ctx, err, st) =>
                                          _buildPlaceholder(),
                                    ))
                            : _buildPlaceholder(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Product Name
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),

                          // Eco Score & Rating
                          Row(
                            children: [
                              EcoScoreBadge(score: product.ecoScore),
                              if (product.rating != null) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.star,
                                  size: 14,
                                  color: Colors.amber.shade700,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  product.rating!.toStringAsFixed(1),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              IconButton(
                                icon: Icon(
                                  isInWishlist
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isInWishlist
                                      ? Colors.red
                                      : Colors.grey,
                                  size: 22,
                                ),
                                onPressed: onAddToWishlist,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // Price
                          if (product.price != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.blue.shade200,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.attach_money,
                                    size: 16,
                                    color: Colors.blue.shade700,
                                  ),
                                  Text(
                                    'RM ${product.price!.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Material Type & Carbon Savings
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(
                      icon: Icons.inventory_2_outlined,
                      label: product.materialType,
                      color: Colors.purple,
                    ),
                    _buildInfoChip(
                      icon: Icons.eco,
                      label: product.carbonSavings,
                      color: kPrimaryGreen,
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Benefit
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kPrimaryGreen.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: kPrimaryGreen, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          product.benefit,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Buy Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onBuyNow,
                    icon: const Icon(Icons.shopping_cart, size: 18),
                    label: Text(
                      'Buy Now - ${product.whereToBuy}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: kPrimaryGreen.withOpacity(0.05),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.eco, size: 42, color: kPrimaryGreen.withOpacity(0.4)),
          const SizedBox(height: 6),
          Text(
            'Eco Product',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ========================
// Main Screen
// ========================

class AlternativeScreen extends StatefulWidget {
  const AlternativeScreen({super.key});

  @override
  State<AlternativeScreen> createState() => _AlternativeScreenState();
}

class _AlternativeScreenState extends State<AlternativeScreen> {
  bool _loading = true;
  List<AlternativeProduct> _loadedAlternatives = [];
  Set<String> _wishlist = {};
  List<ScannedProductWithAlternatives> _recentScans = [];
  final Map<String, ScannedProductWithAlternatives> _alternativeToScanMap = {};
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategory;
  String _searchQuery = '';
  String _userName = 'User';

  // Banner variables
  final PageController _bannerController = PageController();
  int _currentBannerIndex = 0;
  final List<Map<String, String>> _banners = [
    {
      'title': '🌿 Sustainable Choices',
      'subtitle': 'Discover eco-friendly alternatives',
      'gradient': 'green',
    },
    {
      'title': '💚 Health & Planet',
      'subtitle': 'Better for you, better for Earth',
      'gradient': 'blue',
    },
    {
      'title': '♻️ Zero Waste Living',
      'subtitle': 'Reduce plastic, embrace sustainability',
      'gradient': 'teal',
    },
  ];

  final int _selectedIndex = 1;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadWishlist();
    _loadRecentlyViewed();
    _loadAllRecentAlternatives();
    _startBannerAutoSlide();
  }

  Future<void> _loadUserName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          setState(() {
            _userName = userDoc.data()?['name'] ?? 'User';
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading user name: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bannerController.dispose();
    super.dispose();
  }

  // ========================
  // Data Loading Methods
  // ========================

  Future<void> _loadWishlist() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('wishlist')
          .get();

      setState(() {
        _wishlist = snapshot.docs.map((doc) => doc.id).toSet();
      });
    } catch (e) {
      debugPrint('Error loading wishlist: $e');
    }
  }

  Future<void> _loadRecentlyViewed() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('recentlyViewed')
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();

      final scans = <ScannedProductWithAlternatives>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final altData = data['alternatives'] as List<dynamic>?;

        if (altData != null) {
          final alternatives = altData.map((alt) {
            final name = alt['name'] ?? '';
            final ecoScore = alt['ecoScore'] ?? 'N/A';
            final materialType = alt['materialType'] ?? '';
            final brand = alt['brand'];
            return AlternativeProduct(
              id: AlternativeProduct._generateUniqueId(
                name,
                ecoScore,
                materialType,
                brand,
              ),
              name: name,
              ecoScore: ecoScore,
              materialType: materialType,
              benefit: alt['benefit'] ?? '',
              whereToBuy: alt['whereToBuy'] ?? '',
              carbonSavings: alt['carbonSavings'] ?? '',
              imagePath: alt['imagePath'] ?? '',
              buyLink: alt['buyLink'] ?? '',
              shortDescription: alt['shortDescription'] ?? '',
              category: alt['category'] ?? '',
              price: alt['price']?.toDouble(),
              brand: brand,
              rating: alt['rating']?.toDouble(),
            );
          }).toList();

          scans.add(
            ScannedProductWithAlternatives(
              productName: data['productName'] ?? 'Unknown Product',
              productBarcode: data['barcode'] ?? '',
              productCategory: data['category'] ?? '',
              timestamp: data['timestamp'] ?? Timestamp.now(),
              alternatives: alternatives,
            ),
          );
        }
      }

      setState(() {
        _recentScans = scans;
      });
    } catch (e) {
      debugPrint('Error loading recently viewed: $e');
    }
  }

  Future<void> _loadAllRecentAlternatives() async {
    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('recentlyViewed')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      final allAlternatives = <AlternativeProduct>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final altData = data['alternatives'] as List<dynamic>?;

        if (altData != null) {
          for (var alt in altData) {
            final name = alt['name'] ?? '';
            final ecoScore = alt['ecoScore'] ?? 'N/A';
            final materialType = alt['materialType'] ?? '';
            final brand = alt['brand'];
            allAlternatives.add(
              AlternativeProduct(
                id: AlternativeProduct._generateUniqueId(
                  name,
                  ecoScore,
                  materialType,
                  brand,
                ),
                name: name,
                ecoScore: ecoScore,
                materialType: materialType,
                benefit: alt['benefit'] ?? '',
                whereToBuy: alt['whereToBuy'] ?? '',
                carbonSavings: alt['carbonSavings'] ?? '',
                imagePath: alt['imagePath'] ?? '',
                buyLink: alt['buyLink'] ?? '',
                shortDescription: alt['shortDescription'] ?? '',
                category: alt['category'] ?? '',
                price: alt['price']?.toDouble(),
                brand: brand,
                rating: alt['rating']?.toDouble(),
              ),
            );
          }
        }
      }

      setState(() {
        _loadedAlternatives = allAlternatives;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading alternatives: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleWishlist(AlternativeProduct product) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final wishlistRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('wishlist')
          .doc(product.id);

      if (_wishlist.contains(product.id)) {
        await wishlistRef.delete();
        setState(() => _wishlist.remove(product.id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Removed from wishlist')),
          );
        }
      } else {
        await wishlistRef.set(product.toFirestore(includeTimestamp: true));
        setState(() => _wishlist.add(product.id));
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Added to wishlist')));
        }
      }
    } catch (e) {
      debugPrint('Error toggling wishlist: $e');
    }
  }

  // ========================
  // Helper Methods
  // ========================

  int _ecoRank(String score) {
    const ranks = {'A+': 6, 'A': 5, 'B': 4, 'C': 3, 'D': 2, 'E': 1};
    return ranks[score] ?? 0;
  }

  String _extractGenericProductType(String productName) {
    final lower = productName.toLowerCase();
    if (lower.contains('bottle')) return 'bottle';
    if (lower.contains('bag')) return 'bag';
    if (lower.contains('cup')) return 'cup';
    if (lower.contains('straw')) return 'straw';
    if (lower.contains('container')) return 'container';
    if (lower.contains('wrap')) return 'wrap';
    return 'product';
  }

  List<AlternativeProduct> _computeAlternatives() {
    var filtered = _loadedAlternatives.where((alt) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          alt.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          alt.category.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCategory =
          _selectedCategory == null ||
          _selectedCategory == 'All' ||
          alt.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    filtered.sort(
      (a, b) => _ecoRank(b.ecoScore).compareTo(_ecoRank(a.ecoScore)),
    );
    return filtered;
  }

  Future<void> _openBuyLink(String url) async {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No purchase link available')),
      );
      return;
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open link')));
      }
    }
  }

  void _startBannerAutoSlide() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted || !_bannerController.hasClients) return false;

      final nextPage = (_currentBannerIndex + 1) % _banners.length;
      _bannerController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      return true;
    });
  }

  List<Map<String, dynamic>> _getEcoProducts() {
    return [
      {
        'name': 'Bamboo Toothbrush',
        'benefit': 'Biodegradable & plastic-free',
        'ecoScore': 'A+',
        'badge': 'ECO',
        'color': const Color(0xFF4CAF50),
      },
      {
        'name': 'Reusable Water Bottle',
        'benefit': 'Reduces plastic waste',
        'ecoScore': 'A+',
        'badge': 'HEALTH',
        'color': const Color(0xFF2196F3),
      },
      {
        'name': 'Organic Cotton Bag',
        'benefit': 'Natural & sustainable',
        'ecoScore': 'A',
        'badge': 'ECO',
        'color': const Color(0xFF8BC34A),
      },
      {
        'name': 'Stainless Steel Straw',
        'benefit': 'Durable & reusable',
        'ecoScore': 'A+',
        'badge': 'ZERO WASTE',
        'color': const Color(0xFF00BCD4),
      },
      {
        'name': 'Natural Soap Bar',
        'benefit': 'Chemical-free',
        'ecoScore': 'A',
        'badge': 'HEALTH',
        'color': const Color(0xFF9C27B0),
      },
      {
        'name': 'Beeswax Food Wrap',
        'benefit': 'Replaces plastic wrap',
        'ecoScore': 'A+',
        'badge': 'ZERO WASTE',
        'color': const Color(0xFFFF9800),
      },
    ];
  }

  // ========================
  // UI Build Methods
  // ========================

  @override
  Widget build(BuildContext context) {
    final alternatives = _computeAlternatives();
    final categories = [
      'All',
      ..._loadedAlternatives.map((e) => e.category).toSet(),
    ];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Alternatives',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Wishlist button with badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.favorite_border, size: 28),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProductWishlistScreen(),
                    ),
                  );
                },
              ),
              if (_wishlist.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      _wishlist.length > 9 ? '9+' : '${_wishlist.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimaryGreen))
          : RefreshIndicator(
              onRefresh: () async {
                await _loadAllRecentAlternatives();
                await _loadRecentlyViewed();
              },
              color: kPrimaryGreen,
              child: CustomScrollView(
                slivers: [
                  // Banner
                  SliverToBoxAdapter(
                    child: Container(
                      height: 140,
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: PageView.builder(
                        controller: _bannerController,
                        onPageChanged: (index) {
                          setState(() => _currentBannerIndex = index);
                        },
                        itemCount: _banners.length,
                        itemBuilder: (context, index) {
                          final banner = _banners[index];
                          final gradientType = banner['gradient'] ?? 'green';

                          List<Color> gradientColors;
                          if (gradientType == 'green') {
                            gradientColors = [
                              const Color(0xFF4CAF50),
                              const Color(0xFF2E7D32),
                            ];
                          } else if (gradientType == 'blue') {
                            gradientColors = [
                              const Color(0xFF2196F3),
                              const Color(0xFF1565C0),
                            ];
                          } else {
                            gradientColors = [
                              const Color(0xFF00BCD4),
                              const Color(0xFF00838F),
                            ];
                          }

                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: gradientColors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: gradientColors[0].withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  banner['title']!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  banner['subtitle']!,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.95),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // Search Bar
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: Colors.grey.shade600,
                              size: 22,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear,
                                      color: Colors.grey.shade600,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                          ),
                          onChanged: (value) {
                            setState(() => _searchQuery = value);
                          },
                        ),
                      ),
                    ),
                  ),

                  // Eco Products Slider
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
                          child: Text(
                            'Eco-Friendly Products',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _getEcoProducts().length,
                            itemBuilder: (context, index) {
                              final product = _getEcoProducts()[index];
                              return Container(
                                width: 160,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      product['color'] as Color,
                                      (product['color'] as Color).withOpacity(
                                        0.7,
                                      ),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (product['color'] as Color)
                                          .withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          product['badge'] as String,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        product['name'] as String,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          height: 1.2,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        product['benefit'] as String,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 12,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.eco,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            product['ecoScore'] as String,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),

                  // Category Filter
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
                          child: Text(
                            'Categories',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Container(
                          height: 42,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: categories.length,
                            itemBuilder: (context, index) {
                              final category = categories[index];
                              final isSelected =
                                  _selectedCategory == category ||
                                  (_selectedCategory == null &&
                                      category == 'All');

                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(category),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    setState(() {
                                      _selectedCategory = selected
                                          ? category
                                          : 'All';
                                      if (_selectedCategory == 'All') {
                                        _selectedCategory = null;
                                      }
                                    });
                                  },
                                  backgroundColor: Colors.grey.shade100,
                                  selectedColor: kPrimaryGreen,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Search Results Section (shown when searching)
                  if (_searchQuery.isNotEmpty)
                    _buildSearchResultsSection()
                  else
                  // Your Recent Alternative Products Section (shown when not searching)
                  if (_recentScans.isNotEmpty)
                    _buildRecentAlternativesSection(),
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
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildSearchResultsSection() {
    final alternatives = _computeAlternatives();

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Search Results (${alternatives.length})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          if (alternatives.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No products found',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try different keywords',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: alternatives.map((product) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: _buildRecentVerticalCard(product),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildRecentAlternativesSection() {
    // Get recent alternative products from scans and track their parent products
    final recentAlternatives = <AlternativeProduct>[];
    _alternativeToScanMap.clear();

    for (var scan in _recentScans.take(10)) {
      for (var alt in scan.alternatives) {
        // Apply category filter
        final matchesCategory =
            _selectedCategory == null ||
            _selectedCategory == 'All' ||
            alt.category == _selectedCategory;

        if (matchesCategory) {
          recentAlternatives.add(alt);
          _alternativeToScanMap[alt.id] = scan;
        }
      }
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Text(
                  'Your Recent Alternative Products',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {},
                  child: Text(
                    'See all',
                    style: TextStyle(
                      fontSize: 13,
                      color: kPrimaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: recentAlternatives.take(10).map((product) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: _buildRecentVerticalCard(product),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCompactProductCard(AlternativeProduct product) {
    final isInWishlist = _wishlist.contains(product.id);

    return GestureDetector(
      onTap: () => _showProductDetailPopup(product),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            Stack(
              children: [
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                    child: product.imagePath.isNotEmpty
                        ? (product.imagePath.startsWith('http')
                              ? Image.network(
                                  product.imagePath,
                                  width: double.infinity,
                                  height: 120,
                                  fit: BoxFit.cover,
                                  errorBuilder: (ctx, err, st) =>
                                      _buildCompactPlaceholder(),
                                )
                              : Image.asset(
                                  product.imagePath,
                                  width: double.infinity,
                                  height: 120,
                                  fit: BoxFit.cover,
                                  errorBuilder: (ctx, err, st) =>
                                      _buildCompactPlaceholder(),
                                ))
                        : _buildCompactPlaceholder(),
                  ),
                ),
                // Eco Score Badge
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _kEcoScoreColors[product.ecoScore] ?? Colors.grey,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      product.ecoScore,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                // Wishlist button
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        isInWishlist ? Icons.favorite : Icons.favorite_border,
                        color: isInWishlist ? Colors.red : Colors.grey.shade600,
                        size: 18,
                      ),
                      onPressed: () => _toggleWishlist(product),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ),
              ],
            ),
            // Product Details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Name
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Brand Name
                    if (product.brand != null && product.brand!.isNotEmpty)
                      Text(
                        product.brand!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const Spacer(),
                    // Price and Rating
                    Row(
                      children: [
                        if (product.price != null)
                          Expanded(
                            child: Text(
                              'RM ${product.price!.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: kPrimaryGreen,
                              ),
                            ),
                          ),
                        if (product.rating != null) ...[
                          Icon(
                            Icons.star,
                            size: 14,
                            color: Colors.amber.shade700,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            product.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentVerticalCard(AlternativeProduct product) {
    final isInWishlist = _wishlist.contains(product.id);

    return GestureDetector(
      onTap: () => _showProductDetailPopup(product),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: kPrimaryGreen.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: product.imagePath.isNotEmpty
                      ? (product.imagePath.startsWith('http')
                            ? Image.network(
                                product.imagePath,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildCompactPlaceholder(),
                              )
                            : Image.asset(
                                product.imagePath,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildCompactPlaceholder(),
                              ))
                      : _buildCompactPlaceholder(),
                ),
              ),
              const SizedBox(width: 12),
              // Product Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Eco Score Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            _kEcoScoreColors[product.ecoScore] ?? Colors.grey,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        product.ecoScore,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Product Name
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Brand Name
                    if (product.brand != null && product.brand!.isNotEmpty)
                      Text(
                        product.brand!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 8),
                    // Price and Rating Row
                    Row(
                      children: [
                        if (product.price != null)
                          Expanded(
                            child: Text(
                              'RM ${product.price!.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: kPrimaryGreen,
                              ),
                            ),
                          ),
                        if (product.rating != null) ...[
                          Icon(
                            Icons.star,
                            size: 14,
                            color: Colors.amber.shade700,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            product.rating!.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Wishlist button
              IconButton(
                icon: Icon(
                  isInWishlist ? Icons.favorite : Icons.favorite_border,
                  color: isInWishlist ? Colors.red : Colors.grey.shade400,
                  size: 22,
                ),
                onPressed: () => _toggleWishlist(product),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProductComparison(
    ScannedProductWithAlternatives scanData,
    AlternativeProduct alternative,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            // Header
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kPrimaryGreen, kPrimaryGreen.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryGreen.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.compare_arrows,
                    color: Colors.white,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Product Comparison',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Make informed eco-conscious decisions',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            // Comparison content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildComparisonRow(
                      'Eco Score',
                      scanData.productName,
                      'N/A', // Scanned product doesn't have eco score stored
                      alternative.name,
                      alternative.ecoScore,
                      Icons.eco,
                      kPrimaryGreen,
                      highlightBetter: true,
                    ),
                    const SizedBox(height: 16),
                    _buildComparisonRow(
                      'Carbon Footprint',
                      scanData.productName,
                      'Standard',
                      alternative.name,
                      alternative.carbonSavings.isNotEmpty
                          ? alternative.carbonSavings
                          : 'Lower emissions',
                      Icons.cloud_outlined,
                      const Color(0xFF2196F3),
                    ),
                    const SizedBox(height: 16),
                    _buildComparisonRow(
                      'Price',
                      scanData.productName,
                      'Market price',
                      alternative.name,
                      alternative.price != null
                          ? 'RM ${alternative.price!.toStringAsFixed(2)}'
                          : 'Comparable',
                      Icons.attach_money,
                      const Color(0xFFFF9800),
                    ),
                    const SizedBox(height: 16),
                    _buildComparisonRow(
                      'Packaging',
                      scanData.productName,
                      'Conventional',
                      alternative.name,
                      alternative.materialType.isNotEmpty
                          ? alternative.materialType
                          : 'Eco-friendly',
                      Icons.inventory_2_outlined,
                      const Color(0xFF9C27B0),
                    ),
                    const SizedBox(height: 16),
                    _buildComparisonRow(
                      'Key Benefits',
                      scanData.productName,
                      scanData.productCategory,
                      alternative.name,
                      alternative.shortDescription.isNotEmpty
                          ? alternative.shortDescription
                          : 'More sustainable',
                      Icons.star_outline,
                      const Color(0xFF4CAF50),
                    ),
                    const SizedBox(height: 24),
                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _openBuyLink(alternative.buyLink);
                            },
                            icon: const Icon(Icons.shopping_cart, size: 20),
                            label: const Text(
                              'Buy Alternative',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, size: 20),
                            label: const Text(
                              'Close',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey.shade700,
                              side: BorderSide(
                                color: Colors.grey.shade300,
                                width: 2,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
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
      ),
    );
  }

  Widget _buildComparisonRow(
    String label,
    String scannedProductName,
    String scannedValue,
    String altProductName,
    String altValue,
    IconData icon,
    Color accentColor, {
    bool highlightBetter = false,
  }) {
    bool altIsBetter = false;
    if (highlightBetter && label == 'Eco Score') {
      altIsBetter =
          _ecoRank(altValue) < _ecoRank('C'); // Assume scanned is average
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: accentColor, size: 24),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),
          // Comparison content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Scanned product
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Original',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        scannedProductName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        scannedValue,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Alternative product
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: altIsBetter
                              ? kPrimaryGreen.withOpacity(0.15)
                              : accentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Alternative',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: altIsBetter
                                    ? kPrimaryGreen
                                    : accentColor,
                              ),
                            ),
                            if (altIsBetter) const SizedBox(width: 4),
                            if (altIsBetter)
                              Icon(
                                Icons.check_circle,
                                size: 14,
                                color: kPrimaryGreen,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        altProductName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: altIsBetter ? kPrimaryGreen : Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        altValue,
                        style: TextStyle(
                          fontSize: 14,
                          color: altIsBetter
                              ? kPrimaryGreen
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
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

  void _showProductDetailPopup(AlternativeProduct product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            // Drag Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Product Image
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: kPrimaryGreen.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: product.imagePath.isNotEmpty
                            ? (product.imagePath.startsWith('http')
                                  ? Image.network(
                                      product.imagePath,
                                      fit: BoxFit.cover,
                                      errorBuilder: (ctx, err, st) =>
                                          _buildCompactPlaceholder(),
                                    )
                                  : Image.asset(
                                      product.imagePath,
                                      fit: BoxFit.cover,
                                      errorBuilder: (ctx, err, st) =>
                                          _buildCompactPlaceholder(),
                                    ))
                            : _buildCompactPlaceholder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Product Name
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    // Eco Score Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            _kEcoScoreColors[product.ecoScore] ?? Colors.grey,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Eco: ${product.ecoScore}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Material Type
                    if (product.materialType.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.inventory_2,
                                color: Colors.blue.shade700,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Material',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    product.materialType,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Description
                    if (product.benefit.isNotEmpty ||
                        product.shortDescription.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.description,
                                color: Colors.purple.shade700,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Description',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    product.shortDescription.isNotEmpty
                                        ? product.shortDescription
                                        : product.benefit,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _openBuyLink(product.buyLink);
                            },
                            icon: const Icon(Icons.shopping_cart, size: 20),
                            label: const Text(
                              'Buy Now',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              final scanData =
                                  _alternativeToScanMap[product.id];
                              if (scanData != null) {
                                _showProductComparison(scanData, product);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Cannot compare - original product data not found',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: Icon(
                              Icons.compare_arrows,
                              size: 20,
                              color: kPrimaryGreen,
                            ),
                            label: Text(
                              'Compare',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: kPrimaryGreen,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: kPrimaryGreen, width: 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
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
      ),
    );
  }

  Widget _buildCompactPlaceholder() {
    return Container(
      color: kPrimaryGreen.withOpacity(0.05),
      child: Center(
        child: Icon(Icons.eco, size: 40, color: kPrimaryGreen.withOpacity(0.3)),
      ),
    );
  }

  Widget _buildGridProductCard(AlternativeProduct product) {
    final isInWishlist = _wishlist.contains(product.id);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Image
          Stack(
            children: [
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  child: product.imagePath.isNotEmpty
                      ? (product.imagePath.startsWith('http')
                            ? Image.network(
                                product.imagePath,
                                width: double.infinity,
                                height: 160,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, st) =>
                                    _buildCompactPlaceholder(),
                              )
                            : Image.asset(
                                product.imagePath,
                                width: double.infinity,
                                height: 160,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, st) =>
                                    _buildCompactPlaceholder(),
                              ))
                      : _buildCompactPlaceholder(),
                ),
              ),
              // Wishlist button
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      isInWishlist ? Icons.favorite : Icons.favorite_border,
                      color: isInWishlist ? Colors.red : Colors.grey.shade600,
                      size: 20,
                    ),
                    onPressed: () => _toggleWishlist(product),
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
                ),
              ),
            ],
          ),
          // Product Details
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      if (product.price != null)
                        Expanded(
                          child: Text(
                            'RM ${product.price!.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: kPrimaryGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 16,
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
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Widget _buildBottomNavigationBar() {
    return AppBottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) {
        if (index == _selectedIndex) return;

        switch (index) {
          case 0:
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
            break;
          case 1:
            // Current screen (Alternative)
            break;
          case 2:
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ScanScreen()),
            );
            break;
          case 3:
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const DisposalGuidanceScreen(),
              ),
            );
            break;
          case 4:
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ProfileScreen()),
            );
            break;
        }
      },
    );
  }
}
