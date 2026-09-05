// Better Alternative Screen - Shows alternatives for newly scanned product
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../services/generative_service.dart';
import '../models/product_analysis_data.dart';
import 'package:ecopilot/utils/constants.dart';
import 'alternative_screen.dart';

// Re-export shared classes from alternative_screen.dart
export 'alternative_screen.dart'
    show AlternativeProduct, EcoScoreBadge, ScannedProductWithAlternatives;

// Import eco score colors
const Map<String, Color> _kEcoScoreColors = {
  'A+': Color(0xFF1DB954),
  'A': kResultCardGreen,
  'B': kDiscoverMoreGreen,
  'C': kPrimaryYellow,
  'D': kRankSustainabilityHero,
  'E': kWarningRed,
};

class BetterAlternativeScreen extends StatefulWidget {
  final ProductAnalysisData scannedProduct;

  const BetterAlternativeScreen({super.key, required this.scannedProduct});

  @override
  State<BetterAlternativeScreen> createState() =>
      _BetterAlternativeScreenState();
}

class _BetterAlternativeScreenState extends State<BetterAlternativeScreen> {
  bool _loading = false;
  List<AlternativeProduct> _loadedAlternatives = [];
  Set<String> _wishlist = {};
  String _dataSource = '';

  int _ecoRank(String s) {
    final score = s.toUpperCase().trim();
    if (score.startsWith('A+')) return 0;
    if (score.startsWith('A')) return 1;
    if (score.startsWith('B')) return 2;
    if (score.startsWith('C')) return 3;
    if (score.startsWith('D')) return 4;
    if (score.startsWith('E')) return 5;
    return 99;
  }

  /// Extracts generic product type from full product name
  String _extractGenericProductType(String fullProductName) {
    if (fullProductName.isEmpty) return fullProductName;

    final patternsToRemove = [
      RegExp(
        r'\b\d+\s*(ml|l|g|kg|oz|lb|pack|pcs|pieces?)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(twin|triple|double|single|multi)\s*pack\b',
        caseSensitive: false,
      ),
      RegExp(r'\b\d+x\d+\b', caseSensitive: false),
      RegExp(r"\b\d+'?\b", caseSensitive: false),
      RegExp(
        r'\b(red|blue|green|yellow|black|white|pink|purple|orange|brown|grey|gray|silver|gold)\b',
        caseSensitive: false,
      ),
      RegExp(r'\b[A-Z0-9]{2,}-?[A-Z0-9]{2,}\b'),
      RegExp(r'\bmodel\s+[A-Z0-9]+\b', caseSensitive: false),
      RegExp(
        r'\b(new|latest|improved|advanced|premium|deluxe|special|limited|edition|pro|plus|max|ultra|super|mega|extra)\b',
        caseSensitive: false,
      ),
      RegExp(r'\s+with\s+.*$', caseSensitive: false),
      RegExp(r'\s+for\s+.*$', caseSensitive: false),
    ];

    final commonBrands = [
      'Colgate',
      'Oral-B',
      'Sensodyne',
      'Dove',
      'Lux',
      'Pantene',
      'Coca-Cola',
      'Pepsi',
      'Nestle',
      'Samsung',
      'Apple',
      'Nike',
      'Adidas',
    ];

    String result = fullProductName;

    for (final brand in commonBrands) {
      result = result.replaceAll(
        RegExp(r'\b' + RegExp.escape(brand) + r'\b', caseSensitive: false),
        '',
      );
    }

    for (final pattern in patternsToRemove) {
      result = result.replaceAll(pattern, '');
    }

    result = result
        .replaceAll(RegExp(r'[\s,\-\_\/\(\)\[\]\{\}]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');

    if (result.isEmpty || result.length < 3) {
      final words = fullProductName.split(RegExp(r'\s+'));
      for (int i = words.length - 1; i >= 0; i--) {
        final word = words[i].replaceAll(RegExp(r'[^a-zA-Z]'), '');
        if (word.length >= 3 && !RegExp(r'^\d+$').hasMatch(word)) {
          return word;
        }
      }
      return fullProductName;
    }

    return result;
  }

  Future<void> _loadWishlist() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('wishlist')
          .get();

      setState(() {
        _wishlist = doc.docs.map((d) => d.id).toSet();
      });
    } catch (e) {
      debugPrint('Error loading wishlist: $e');
    }
  }

  Future<void> _toggleWishlist(AlternativeProduct product) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login to use wishlist')),
        );
        return;
      }

      final wishlistRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('wishlist')
          .doc(product.id);

      if (_wishlist.contains(product.id)) {
        await wishlistRef.delete();
        setState(() => _wishlist.remove(product.id));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Removed from wishlist')));
      } else {
        await wishlistRef.set(product.toFirestore(includeTimestamp: true));
        setState(() => _wishlist.add(product.id));
        _loadWishlist();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Added to wishlist 💚')));
      }
    } catch (e) {
      debugPrint('Error toggling wishlist: $e');
    }
  }

  Future<void> _saveScannedProductWithAlternatives() async {
    if (_loadedAlternatives.isEmpty) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final scanId =
          '${DateTime.now().millisecondsSinceEpoch}_${widget.scannedProduct.productName.hashCode.abs()}';

      // Save to recentlyViewed collection so it appears in AlternativeScreen
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('recentlyViewed')
          .doc(scanId)
          .set({
            'productName': widget.scannedProduct.productName,
            'category': widget.scannedProduct.category,
            'ecoScore': widget.scannedProduct.ecoScore,
            'packagingType': widget.scannedProduct.packagingType,
            'ingredients': widget.scannedProduct.ingredients,
            'imageUrl': widget.scannedProduct.imageUrl,
            'alternativesCount': _loadedAlternatives.length,
            'alternatives': _loadedAlternatives
                .map((a) => a.toFirestore(includeTimestamp: false))
                .toList(),
            'timestamp': FieldValue.serverTimestamp(),
          });

      debugPrint(
        '✅ Saved to recently viewed with ${_loadedAlternatives.length} alternatives',
      );
    } catch (e) {
      debugPrint('Error saving to recently viewed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadWishlist();
    _generateAlternatives();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _generateAlternatives() async {
    final genericProductType = _extractGenericProductType(
      widget.scannedProduct.productName,
    );

    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('🔄 GENERATING ALTERNATIVES');
    debugPrint('   Original: ${widget.scannedProduct.productName}');
    debugPrint('   Generic Type: $genericProductType');
    debugPrint('   Category: ${widget.scannedProduct.category}');
    debugPrint('═══════════════════════════════════════════════════');

    setState(() => _loading = true);

    // Try Firestore cache first
    bool firestoreSuccess = await _tryFirestoreAlternatives();
    if (firestoreSuccess) {
      debugPrint('✅ Using cached Firestore alternatives');
      await _saveScannedProductWithAlternatives();
      setState(() => _loading = false);
      return;
    }

    // Try Gemini AI
    bool geminiSuccess = await _tryGeminiAlternatives();
    if (geminiSuccess) {
      debugPrint('✅ Using Gemini AI alternatives');
      await _saveScannedProductWithAlternatives();
      setState(() => _loading = false);
      return;
    }

    // Try Cloudinary
    await _loadAlternativesFromCloudinary();

    if (_loadedAlternatives.isNotEmpty) {
      debugPrint('✅ Using Cloudinary alternatives');
      await _saveScannedProductWithAlternatives();
    } else {
      debugPrint('❌ No alternatives available');
      _dataSource = 'No Data Available';
    }

    setState(() => _loading = false);
  }

  Future<bool> _tryGeminiAlternatives({int retryCount = 0}) async {
    const maxRetries = 2;

    try {
      debugPrint(
        '🤖 Trying Gemini AI (Attempt ${retryCount + 1}/${maxRetries + 1})',
      );

      final genericProductType = _extractGenericProductType(
        widget.scannedProduct.productName,
      );

      final prompt =
          '''
You are an expert eco-product recommender with access to current e-commerce data in Malaysia.

SCANNED PRODUCT ANALYSIS:
━━━━━━━━━━━━━━━━━━━━━━━━━━
Original Product: ${widget.scannedProduct.productName}
Generic Product Type: $genericProductType
Category: ${widget.scannedProduct.category}
Current Eco Score: ${widget.scannedProduct.ecoScore}
Packaging Type: ${widget.scannedProduct.packagingType}
Ingredients/Materials: ${widget.scannedProduct.ingredients}
━━━━━━━━━━━━━━━━━━━━━━━━━━

TASK: Find 5-8 REAL eco-friendly alternatives for "$genericProductType" available on Shopee or Lazada Malaysia.

✅ REQUIREMENTS:
1. Better eco score than "${widget.scannedProduct.ecoScore}"
2. Same product type as "$genericProductType"
3. Same category as "${widget.scannedProduct.category}"
4. REAL product names (no generic examples)
5. Currently available in Malaysia
6. MUST include valid product image URLs

📋 OUTPUT FORMAT (JSON ARRAY ONLY - NO MARKDOWN):
[
  {
    "name": "Exact Product Name",
    "ecoScore": "A+",
    "category": "${widget.scannedProduct.category}",
    "material": "Packaging material",
    "shortDescription": "Why more sustainable",
    "buyUrl": "https://shopee.com.my/search?keyword=product",
    "imageUrl": "https://valid-image-url.jpg",
    "carbonSavings": "Environmental benefit",
    "price": 35.50,
    "brand": "Brand Name",
    "rating": 4.5
  }
]

🖼️ IMAGE REQUIREMENTS (CRITICAL - EVERY PRODUCT MUST HAVE AN IMAGE):
- Priority 1: Real product images from Shopee Malaysia (e.g., https://cf.shopee.com.my/file/...)
- Priority 2: Real product images from Lazada Malaysia (e.g., https://my-live.slatic.net/...)
- Priority 3: Brand official website product images
- Priority 4: High-quality Unsplash photos: https://images.unsplash.com/photo-{id}?w=800&q=80
- Format: Direct image URLs ending in .jpg, .png, .webp, .jpeg
- Quality: Minimum 600x600px, preferably 800x800px or higher
- ABSOLUTELY NO PLACEHOLDER TEXT like "N/A", "placeholder", or empty strings
- MUST be accessible public URLs without authentication

⚠️ CRITICAL RULES:
- Return ONLY JSON array (no markdown, no code blocks)
- All products MUST be real, currently available products in Malaysia
- EVERY product MUST have a valid, working imageUrl field
- Include 5-8 alternatives minimum
- Double-check that all imageUrl values are actual URLs, not empty or "N/A"
- If you cannot find a real product image, use a relevant Unsplash URL
''';

      final text = await GenerativeService.generateResponse(prompt);

      if (text.isEmpty || text.startsWith('__')) {
        debugPrint('❌ Gemini returned empty/error response');
        return false;
      }

      // Extract JSON
      String jsonText = text.trim();
      final first = jsonText.indexOf('[');
      final last = jsonText.lastIndexOf(']');
      if (first >= 0 && last > first) {
        jsonText = jsonText.substring(first, last + 1);
      }

      final decoded = jsonDecode(jsonText);

      if (decoded is! List || decoded.isEmpty) {
        debugPrint('❌ Invalid JSON format');
        return false;
      }

      final List<AlternativeProduct> generated = [];
      int itemIndex = 0;

      for (final item in decoded) {
        if (item is! Map) continue;

        final name = (item['name'] ?? '').toString();
        if (name.isEmpty) continue;

        final uniqueId =
            '${DateTime.now().millisecondsSinceEpoch}_${itemIndex}_${name.hashCode.abs()}';
        itemIndex++;

        // Get image URL, with fallback to Unsplash if empty or invalid
        String imageUrl = (item['imageUrl'] ?? '').toString().trim();

        // Validate image URL - check if it's empty, placeholder text, or not a URL
        final isInvalidUrl =
            imageUrl.isEmpty ||
            imageUrl == 'N/A' ||
            imageUrl.toLowerCase() == 'placeholder' ||
            !imageUrl.startsWith('http');

        if (isInvalidUrl) {
          debugPrint(
            '⚠️ Invalid/missing image for "$name", fetching from Unsplash...',
          );
          imageUrl = await _fetchUnsplashImage(
            name,
            widget.scannedProduct.category,
          );
          debugPrint('✅ Using Unsplash image: ${imageUrl.substring(0, 50)}...');
        } else {
          debugPrint(
            '✅ Using provided image for "$name": ${imageUrl.substring(0, 50)}...',
          );
        }

        generated.add(
          AlternativeProduct(
            id: uniqueId,
            name: name,
            ecoScore: (item['ecoScore'] ?? 'A').toString(),
            materialType: (item['material'] ?? '').toString(),
            category: (item['category'] ?? widget.scannedProduct.category)
                .toString(),
            benefit: '',
            whereToBuy: '',
            carbonSavings: (item['carbonSavings'] ?? '').toString(),
            imagePath: imageUrl,
            buyLink: (item['buyUrl'] ?? '').toString(),
            shortDescription: (item['shortDescription'] ?? '').toString(),
            price: _parsePrice(item['price']),
            brand: (item['brand'] ?? '').toString().isEmpty
                ? null
                : (item['brand'] ?? '').toString(),
            rating: _parseRating(item['rating']),
            externalSource: 'gemini',
          ),
        );
      }

      if (generated.isNotEmpty) {
        await _saveAlternativesToFirestore(generated);

        setState(() {
          _loadedAlternatives = generated;
          _dataSource = 'Gemini AI';
        });
        return true;
      }
    } catch (e) {
      debugPrint('❌ Gemini failed (Attempt ${retryCount + 1}): $e');

      if (retryCount < maxRetries) {
        final delaySeconds = (retryCount + 1) * 2;
        debugPrint('⏳ Retrying in $delaySeconds seconds...');
        await Future.delayed(Duration(seconds: delaySeconds));
        return _tryGeminiAlternatives(retryCount: retryCount + 1);
      }
    }
    return false;
  }

  Future<bool> _tryFirestoreAlternatives() async {
    try {
      final genericProductType = _extractGenericProductType(
        widget.scannedProduct.productName,
      );

      final productKey = genericProductType
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .trim();

      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('alternative_products')
          .where('sourceProductKey', isEqualTo: productKey)
          .limit(10)
          .get();

      if (querySnapshot.docs.isEmpty) {
        querySnapshot = await FirebaseFirestore.instance
            .collection('alternative_products')
            .where('category', isEqualTo: widget.scannedProduct.category)
            .orderBy('ecoScore')
            .limit(10)
            .get();
      }

      if (querySnapshot.docs.isEmpty) return false;

      final List<AlternativeProduct> fetched = [];
      for (final doc in querySnapshot.docs) {
        try {
          fetched.add(AlternativeProduct.fromFirestore(doc));
        } catch (e) {
          debugPrint('Error parsing document: $e');
        }
      }

      if (fetched.isNotEmpty) {
        final scannedRank = _ecoRank(widget.scannedProduct.ecoScore);
        final better = fetched
            .where((a) => _ecoRank(a.ecoScore) < scannedRank)
            .toList();

        setState(() {
          _loadedAlternatives = better.isNotEmpty ? better : fetched;
          _dataSource = 'Firestore Cache';
        });
        return true;
      }
    } catch (e) {
      debugPrint('Firestore fetch failed: $e');
    }
    return false;
  }

  Future<void> _saveAlternativesToFirestore(
    List<AlternativeProduct> alternatives,
  ) async {
    try {
      final genericProductType = _extractGenericProductType(
        widget.scannedProduct.productName,
      );

      final productKey = genericProductType
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .trim();

      final batch = FirebaseFirestore.instance.batch();

      for (final alt in alternatives) {
        final docRef = FirebaseFirestore.instance
            .collection('alternative_products')
            .doc(alt.id);

        batch.set(docRef, {
          ...alt.toFirestore(includeTimestamp: false),
          'sourceProductName': widget.scannedProduct.productName,
          'sourceGenericType': genericProductType,
          'sourceProductKey': productKey,
          'sourceCategory': widget.scannedProduct.category,
          'sourceEcoScore': widget.scannedProduct.ecoScore,
          'generatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      debugPrint('✅ Saved alternatives to Firestore');
    } catch (e) {
      debugPrint('❌ Failed to save alternatives: $e');
    }
  }

  double? _parsePrice(dynamic price) {
    if (price == null) return null;
    if (price is num) return price.toDouble();
    if (price is String) {
      final cleaned = price.replaceAll(RegExp(r'[^\d.]'), '');
      return double.tryParse(cleaned);
    }
    return null;
  }

  double? _parseRating(dynamic rating) {
    if (rating == null) return null;
    if (rating is num) return rating.toDouble().clamp(0.0, 5.0);
    if (rating is String) {
      return double.tryParse(rating)?.clamp(0.0, 5.0);
    }
    return null;
  }

  /// Fetch a fallback image from Unsplash if product has no image
  Future<String> _fetchUnsplashImage(
    String productName,
    String category,
  ) async {
    try {
      // Create search query from product name and category
      final searchTerms = <String>[];

      // Extract meaningful words from product name
      final cleanName = productName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
          .split(' ')
          .where((word) => word.length > 3)
          .take(2)
          .join(' ');

      if (cleanName.isNotEmpty) searchTerms.add(cleanName);
      if (category.isNotEmpty && category != 'N/A') {
        searchTerms.add(category.toLowerCase());
      }

      // Build query for Unsplash with eco-friendly context
      final query = Uri.encodeComponent(searchTerms.join(' '));

      // Use Unsplash Source API with specific dimensions and quality
      // This provides random photos matching the search terms
      final url =
          'https://source.unsplash.com/800x800/?$query,product,sustainable';

      debugPrint('🖼️ Fetching Unsplash image for: ${searchTerms.join(' ')}');
      return url;
    } catch (e) {
      debugPrint('Error fetching Unsplash image: $e');
      // Return a default eco-friendly placeholder URL
      return 'https://source.unsplash.com/800x800/?eco,sustainable,product';
    }
  }

  Future<void> _loadAlternativesFromCloudinary() async {
    final base = dotenv.env['CLOUDINARY_BASE_URL'] ?? '';
    if (base.isEmpty) return;

    final List<AlternativeProduct> fetched = [];

    String slug(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .trim();

    final candidates = <String>[];
    if (widget.scannedProduct.category.isNotEmpty &&
        widget.scannedProduct.category != 'N/A') {
      candidates.add('$base/${slug(widget.scannedProduct.category)}.json');
    }
    candidates.add('$base/alternatives.json');

    for (final url in candidates) {
      try {
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode != 200) continue;

        final decoded = jsonDecode(resp.body);
        if (decoded is List) {
          int itemIndex = 0;
          for (final item in decoded) {
            if (item is Map) {
              final uniqueId =
                  '${DateTime.now().millisecondsSinceEpoch}_${itemIndex}_${item['name'].hashCode.abs()}';
              itemIndex++;

              final productName = item['name'] ?? '';

              // Get image URL, with fallback to Unsplash if empty or invalid
              String imageUrl = (item['imagePath'] ?? '').toString().trim();

              // Validate image URL
              final isInvalidUrl =
                  imageUrl.isEmpty ||
                  imageUrl == 'N/A' ||
                  imageUrl.toLowerCase() == 'placeholder' ||
                  !imageUrl.startsWith('http');

              if (isInvalidUrl) {
                debugPrint(
                  '⚠️ Invalid/missing image for "$productName", fetching from Unsplash...',
                );
                imageUrl = await _fetchUnsplashImage(
                  productName,
                  item['category'] ?? widget.scannedProduct.category,
                );
                debugPrint('✅ Using Unsplash fallback image');
              }

              fetched.add(
                AlternativeProduct(
                  id: uniqueId,
                  name: productName,
                  ecoScore: item['ecoScore'] ?? 'N/A',
                  materialType: item['materialType'] ?? '',
                  benefit: item['benefit'] ?? '',
                  whereToBuy: item['whereToBuy'] ?? '',
                  carbonSavings: item['carbonSavings'] ?? '',
                  imagePath: imageUrl,
                  buyLink: item['buyLink'] ?? '',
                  shortDescription: item['shortDescription'] ?? '',
                  category: item['category'] ?? '',
                  price: _parsePrice(item['price']),
                  brand: item['brand'],
                  rating: _parseRating(item['rating']),
                  externalSource: 'cloudinary',
                ),
              );
            }
          }
        }
        if (fetched.isNotEmpty) break;
      } catch (e) {
        continue;
      }
    }

    if (fetched.isNotEmpty) {
      final sRank = _ecoRank(widget.scannedProduct.ecoScore);
      final better = fetched
          .where((a) => _ecoRank(a.ecoScore) < sRank)
          .toList();
      setState(() {
        _loadedAlternatives = better.isNotEmpty ? better : fetched;
        _dataSource = 'Cloudinary';
      });
    }
  }

  List<AlternativeProduct> _computeAlternatives() {
    var alternatives = List<AlternativeProduct>.from(_loadedAlternatives);

    alternatives.sort((a, b) {
      final aEcoRank = _ecoRank(a.ecoScore);
      final bEcoRank = _ecoRank(b.ecoScore);
      if (aEcoRank != bEcoRank) return aEcoRank.compareTo(bEcoRank);

      final aNameLength = a.name.length;
      final bNameLength = b.name.length;
      if (aNameLength != bNameLength) return aNameLength.compareTo(bNameLength);

      if (a.price == null && b.price != null) return 1;
      if (a.price != null && b.price == null) return -1;
      if (a.price != null && b.price != null) {
        return a.price!.compareTo(b.price!);
      }

      return 0;
    });

    return alternatives;
  }

  Future<void> _openBuyLink(String url) async {
    if (url.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No buy link available')));
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      Clipboard.setData(ClipboardData(text: url));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid link copied to clipboard')),
      );
      return;
    }

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied to clipboard')),
        );
      }
    } catch (e) {
      Clipboard.setData(ClipboardData(text: url));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open link — copied to clipboard'),
        ),
      );
    }
  }

  void _showComparison(AlternativeProduct alternative) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
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
                    blurRadius: 15,
                    offset: const Offset(0, 5),
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
                  const SizedBox(height: 8),
                  Text(
                    'Scanned vs Eco-Friendly Alternative',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildComparisonRow(
                      'Eco Score',
                      widget.scannedProduct.ecoScore,
                      alternative.ecoScore,
                      Icons.eco,
                      kPrimaryGreen,
                      highlightBetter: true,
                    ),
                    const SizedBox(height: 16),
                    _buildComparisonRow(
                      'Carbon Footprint',
                      'Standard emissions',
                      alternative.carbonSavings.isNotEmpty
                          ? alternative.carbonSavings
                          : 'Reduced emissions',
                      Icons.cloud_outlined,
                      const Color(0xFF2196F3),
                    ),
                    const SizedBox(height: 16),
                    _buildComparisonRow(
                      'Price',
                      'Market price',
                      alternative.price != null
                          ? 'RM ${alternative.price!.toStringAsFixed(2)}'
                          : 'Comparable',
                      Icons.attach_money,
                      const Color(0xFFFF9800),
                    ),
                    const SizedBox(height: 16),
                    _buildComparisonRow(
                      'Packaging',
                      widget.scannedProduct.packagingType.isNotEmpty
                          ? widget.scannedProduct.packagingType
                          : 'Conventional',
                      alternative.materialType.isNotEmpty
                          ? alternative.materialType
                          : 'Eco-friendly',
                      Icons.inventory_2_outlined,
                      const Color(0xFF9C27B0),
                    ),
                    const SizedBox(height: 16),
                    _buildComparisonRow(
                      'Ingredients',
                      widget.scannedProduct.ingredients.isNotEmpty
                          ? widget.scannedProduct.ingredients
                          : 'Standard ingredients',
                      alternative.shortDescription.isNotEmpty
                          ? alternative.shortDescription
                          : alternative.benefit.isNotEmpty
                          ? alternative.benefit
                          : 'Natural & sustainable',
                      Icons.science_outlined,
                      const Color(0xFF4CAF50),
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
    String scannedValue,
    String altValue,
    IconData icon,
    Color accentColor, {
    bool highlightBetter = false,
  }) {
    bool altIsBetter = false;
    if (highlightBetter && label == 'Eco Score') {
      altIsBetter = _ecoRank(altValue) < _ecoRank(scannedValue);
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scanned',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        scannedValue,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alternative',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              altValue,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: altIsBetter
                                    ? kPrimaryGreen
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          if (altIsBetter) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.check_circle,
                              color: kPrimaryGreen,
                              size: 16,
                            ),
                          ],
                        ],
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

  Widget _buildProductRowCard(AlternativeProduct product) {
    final isInWishlist = _wishlist.contains(product.id);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Show product details
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Image
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200, width: 1),
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: product.imagePath.isNotEmpty
                            ? Image.network(
                                product.imagePath,
                                width: 110,
                                height: 110,
                                fit: BoxFit.cover,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Center(
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
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                kPrimaryGreen,
                                              ),
                                        ),
                                      );
                                    },
                                errorBuilder: (_, __, ___) => Center(
                                  child: Icon(
                                    Icons.eco,
                                    size: 40,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              )
                            : Center(
                                child: Icon(
                                  Icons.eco,
                                  size: 40,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                _kEcoScoreColors[product.ecoScore] ??
                                Colors.grey,
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
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Product Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (product.shortDescription.isNotEmpty)
                        Text(
                          product.shortDescription,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (product.price != null)
                            Text(
                              'RM ${product.price!.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: kPrimaryGreen,
                              ),
                            )
                          else if (product.carbonSavings.isNotEmpty)
                            Expanded(
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.eco,
                                    size: 14,
                                    color: kPrimaryGreen,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      product.carbonSavings,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _toggleWishlist(product),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isInWishlist
                                    ? Colors.red.shade50
                                    : Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isInWishlist
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 18,
                                color: isInWishlist
                                    ? Colors.red
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    kPrimaryGreen,
                                    kPrimaryGreen.withOpacity(0.85),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: kPrimaryGreen.withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: () => _openBuyLink(product.buyLink),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 11,
                                  ),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  'Buy Now',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: kPrimaryGreen.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: kPrimaryGreen.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: IconButton(
                              onPressed: () => _showComparison(product),
                              icon: Icon(
                                Icons.compare_arrows,
                                size: 20,
                                color: kPrimaryGreen,
                              ),
                              padding: const EdgeInsets.all(10),
                              constraints: const BoxConstraints(),
                              tooltip: 'Compare',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alternatives = _computeAlternatives();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Better Alternatives',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(20),
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
                        color: kPrimaryGreen.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: kPrimaryGreen,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.eco,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Eco-Friendly Alternatives',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_loadedAlternatives.length} better options found',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.shopping_bag_outlined,
                                color: kPrimaryGreen,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.scannedProduct.productName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_dataSource.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kPrimaryGreen,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _dataSource,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_loading)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: kPrimaryGreen.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: CircularProgressIndicator(
                              color: kPrimaryGreen,
                              strokeWidth: 3,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Finding eco-friendly alternatives',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Searching for better options...',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!_loading && alternatives.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final product = alternatives[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildProductRowCard(product),
                        );
                      }, childCount: alternatives.length),
                    ),
                  ),
                if (!_loading && alternatives.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.all(32),
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.grey.shade200,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.eco_outlined,
                                size: 60,
                                color: Colors.grey.shade400,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'No alternatives found',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'We couldn\'t find eco-friendly alternatives\nfor this product at the moment',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
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
          if (!_loading && alternatives.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withOpacity(0.8), Colors.white],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 15,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kPrimaryGreen, kPrimaryGreen.withOpacity(0.85)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: kPrimaryGreen.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.check_circle,
                              color: Colors.white,
                              size: 22,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Done',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
