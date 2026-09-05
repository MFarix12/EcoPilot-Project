import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:ecopilot/utils/constants.dart';
import 'package:ecopilot/utils/cloudinary_config.dart';
import 'package:ecopilot/services/cloudinary_service.dart';
import 'package:ecopilot/models/product_analysis_data.dart';
import 'package:ecopilot/auth/firebase_service.dart';
import 'package:ecopilot/screens/result_disposal_screen.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  bool _torchOn = false;
  String? _scannedBarcode;

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  Future<void> _initScanner() async {
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    try {
      await _controller!.toggleTorch();
      setState(() {
        _torchOn = !_torchOn;
      });
    } catch (e) {
      debugPrint('Error toggling flash: $e');
    }
  }

  Future<void> _handleBarcode(String barcode) async {
    if (_isProcessing || barcode.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _scannedBarcode = barcode;
    });

    try {
      // Try Open Food Facts first
      Map<String, dynamic>? productData = await _fetchFromOpenFoodFacts(
        barcode,
      );

      // If not found, try Open Beauty Facts
      if (productData == null || productData.isEmpty) {
        productData = await _fetchFromOpenBeautyFacts(barcode);
      }

      if (productData != null && productData.isNotEmpty) {
        // Product found, now analyze with Gemini
        await _analyzeWithGemini(productData, barcode);
      } else {
        // Product not found in databases
        if (mounted) {
          _showProductNotFoundDialog(barcode);
        }
      }
    } catch (e) {
      debugPrint('Error processing barcode: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchFromOpenFoodFacts(String barcode) async {
    try {
      final url =
          'https://world.openfoodfacts.org/api/v2/product/$barcode.json';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 1 && data['product'] != null) {
          final product = data['product'];
          return {
            'name': product['product_name'] ?? 'Unknown Product',
            'brand': product['brands'] ?? '',
            'category': product['categories'] ?? 'Food & Beverages',
            'ingredients': product['ingredients_text'] ?? '',
            'packaging':
                product['packaging'] ?? product['packaging_text'] ?? '',
            'image_url':
                product['image_url'] ?? product['image_front_url'] ?? '',
            'barcode': barcode,
            'source': 'Open Food Facts',
          };
        }
      }
    } catch (e) {
      debugPrint('Error fetching from Open Food Facts: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _fetchFromOpenBeautyFacts(
    String barcode,
  ) async {
    try {
      final url =
          'https://world.openbeautyfacts.org/api/v2/product/$barcode.json';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 1 && data['product'] != null) {
          final product = data['product'];
          return {
            'name': product['product_name'] ?? 'Unknown Product',
            'brand': product['brands'] ?? '',
            'category': product['categories'] ?? 'Personal Care',
            'ingredients': product['ingredients_text'] ?? '',
            'packaging':
                product['packaging'] ?? product['packaging_text'] ?? '',
            'image_url':
                product['image_url'] ?? product['image_front_url'] ?? '',
            'barcode': barcode,
            'source': 'Open Beauty Facts',
          };
        }
      }
    } catch (e) {
      debugPrint('Error fetching from Open Beauty Facts: $e');
    }
    return null;
  }

  Future<void> _analyzeWithGemini(
    Map<String, dynamic> productData,
    String barcode,
  ) async {
    final geminiApiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

    if (geminiApiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gemini API key not configured. Please check your .env file.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final model = GenerativeModel(
        model:'models/gemini-2.5-pro', // Fast processing for barcode-scanned products with existing data
        apiKey: geminiApiKey,
      );

      // Escape special characters in ingredients and packaging
      final ingredientsText = (productData['ingredients'] ?? '')
          .toString()
          .replaceAll('"', '\\"')
          .replaceAll('\n', ' ');
      final packagingText = (productData['packaging'] ?? '')
          .toString()
          .replaceAll('"', '\\"')
          .replaceAll('\n', ' ');

      final prompt =
          '''
You are an expert environmental analyst. Analyze this product and provide COMPLETE eco-friendly disposal guidance.

PRODUCT INFORMATION:
- Product Name: ${productData['name']}
- Brand: ${productData['brand']}
- Category: ${productData['category']}
- Ingredients: $ingredientsText
- Packaging: $packagingText
- Barcode: $barcode

CRITICAL REQUIREMENTS:
1. You MUST analyze the actual product information provided above
2. Evaluate the packaging materials to determine recyclability
3. Consider the ingredients for environmental impact
4. Provide specific, actionable disposal steps (minimum 5 steps)
5. Generate relevant eco-tips based on THIS specific product (minimum 4 tips)
6. Calculate an accurate eco-score (A=excellent, B=good, C=average, D=poor, E=very poor)
7. Estimate carbon footprint based on product type and packaging

Return ONLY a valid JSON object (no markdown, no code blocks, no backticks) with this EXACT structure:
{
  "product_name": "exact product name from data",
  "category": "Food & Beverages (F&B)",
  "packaging_type": "detailed description of packaging materials (e.g., 'Plastic wrapper, cardboard box')",
  "ingredients": "list of key ingredients or 'N/A' if not applicable",
  "eco_score": "single letter A, B, C, D, or E based on environmental impact",
  "carbon_footprint": "estimated value with unit (e.g., '0.8 kg CO2e', '120g CO2e')",
  "disposal_steps": [
    "Detailed step 1",
    "Detailed step 2",
    "Detailed step 3",
    "Detailed step 4",
    "Detailed step 5"
  ],
  "nearby_center": "type of facility (e.g., 'Local recycling center', 'Specialized e-waste facility')",
  "tips": [
    "Specific eco tip 1 for this product",
    "Specific eco tip 2 for this product",
    "Specific eco tip 3 for this product",
    "Specific eco tip 4 for this product"
  ],
  "contains_microplastics": true or false,
  "palm_oil_derivative": true or false,
  "cruelty_free": true or false
}

VALIDATION RULES:
- eco_score must be exactly ONE letter: A, B, C, D, or E
- disposal_steps must contain at least 5 clear, actionable steps
- tips must contain at least 4 practical eco-tips specific to this product
- carbon_footprint must include a number and unit
- All boolean fields must be true or false (not strings)

Return ONLY the JSON object. No explanatory text before or after.
''';

      final content = [Content.text(prompt)];

      // Show analyzing dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Analyzing product with AI...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final response = await model.generateContent(content);
      final outputText = response.text ?? '';

      // Close analyzing dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      debugPrint('Gemini raw response: $outputText');

      // Parse JSON response with multiple strategies
      Map<String, dynamic>? analysisData;

      // Strategy 1: Direct decode
      try {
        final decoded = json.decode(outputText);
        if (decoded is Map<String, dynamic>) {
          analysisData = decoded;
          debugPrint('Strategy 1 successful: Direct JSON decode');
        }
      } catch (e) {
        debugPrint('Strategy 1 failed: $e');
      }

      // Strategy 2: Remove markdown code blocks
      if (analysisData == null) {
        try {
          String cleanedText = outputText
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();
          final decoded = json.decode(cleanedText);
          if (decoded is Map<String, dynamic>) {
            analysisData = decoded;
            debugPrint('Strategy 2 successful: Removed markdown');
          }
        } catch (e) {
          debugPrint('Strategy 2 failed: $e');
        }
      }

      // Strategy 3: Extract JSON between { and }
      if (analysisData == null) {
        try {
          final jsonStart = outputText.indexOf('{');
          final jsonEnd = outputText.lastIndexOf('}');
          if (jsonStart >= 0 && jsonEnd > jsonStart) {
            final jsonStr = outputText.substring(jsonStart, jsonEnd + 1);
            final decoded = json.decode(jsonStr);
            if (decoded is Map<String, dynamic>) {
              analysisData = decoded;
              debugPrint('Strategy 3 successful: Extracted JSON');
            }
          }
        } catch (e) {
          debugPrint('Strategy 3 failed: $e');
        }
      }

      // Validate the analysis data
      if (analysisData != null) {
        // Check required fields
        final hasDisposalSteps =
            analysisData['disposal_steps'] != null &&
            analysisData['disposal_steps'] is List &&
            (analysisData['disposal_steps'] as List).isNotEmpty;

        final hasValidEcoScore =
            analysisData['eco_score'] != null &&
            RegExp(r'^[A-E]$').hasMatch(analysisData['eco_score'].toString());

        if (!hasDisposalSteps) {
          debugPrint('Validation failed: Missing or empty disposal_steps');
          analysisData = null;
        } else if (!hasValidEcoScore) {
          debugPrint('Validation failed: Invalid eco_score (must be A-E)');
          // Fix the eco_score if possible
          if (analysisData['eco_score'] != null) {
            final scoreStr = analysisData['eco_score'].toString().toUpperCase();
            if (scoreStr.isNotEmpty && 'ABCDE'.contains(scoreStr[0])) {
              analysisData['eco_score'] = scoreStr[0];
            } else {
              analysisData['eco_score'] = 'C'; // Default to average
            }
          }
        }
      }

      if (analysisData != null) {
        debugPrint('✅ Gemini analysis successful with complete data');
        // Merge product data with Gemini analysis (Gemini data takes priority)
        final mergedData = {
          ...productData,
          ...analysisData,
          'image_url': productData['image_url'],
        };
        await _saveAndNavigate(mergedData, outputText);
      } else {
        debugPrint('❌ Failed to get valid analysis from Gemini');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'AI analysis failed. Please try again or scan a different product.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          Navigator.of(context).pop(); // Return to previous screen
        }
      }
    } catch (e) {
      debugPrint('Gemini analysis error: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close analyzing dialog if open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error analyzing product: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.of(context).pop(); // Return to previous screen
      }
    }
  }

  Future<void> _saveAndNavigate(
    Map<String, dynamic> data,
    String? aiOutput,
  ) async {
    try {
      // Upload image to Cloudinary if available
      String? cloudinaryImageUrl;
      final sourceImageUrl = data['image_url'] ?? '';

      if (sourceImageUrl.isNotEmpty && isCloudinaryConfigured) {
        try {
          // Download image from Open Food Facts/Open Beauty Facts
          final imageResponse = await http.get(Uri.parse(sourceImageUrl));

          if (imageResponse.statusCode == 200) {
            final imageBytes = imageResponse.bodyBytes;
            final barcode =
                data['barcode'] ??
                DateTime.now().millisecondsSinceEpoch.toString();

            // Upload to Cloudinary
            cloudinaryImageUrl = await CloudinaryService.uploadImageBytes(
              imageBytes,
              filename: 'barcode_$barcode.jpg',
              cloudName: kCloudinaryCloudName,
              uploadPreset: kCloudinaryUploadPreset,
            );

            debugPrint('Image uploaded to Cloudinary: $cloudinaryImageUrl');
          }
        } catch (e) {
          debugPrint('Error uploading to Cloudinary: $e');
          // Fallback to original image URL
          cloudinaryImageUrl = sourceImageUrl;
        }
      } else if (sourceImageUrl.isNotEmpty) {
        // Cloudinary not configured, use original URL
        cloudinaryImageUrl = sourceImageUrl;
      }

      // Create ProductAnalysisData from the merged data
      final analysisData = ProductAnalysisData(
        productName: data['product_name'] ?? data['name'] ?? 'Unknown Product',
        category: data['category'] ?? 'General',
        ingredients: data['ingredients'] ?? '',
        ecoScore: data['eco_score'] ?? data['ecoScore'] ?? 'N/A',
        carbonFootprint:
            data['carbon_footprint'] ?? data['carbonFootprint'] ?? 'N/A',
        packagingType: data['packaging_type'] ?? data['packaging'] ?? 'Unknown',
        disposalMethod: (data['disposal_steps'] is List)
            ? (data['disposal_steps'] as List).join('\n')
            : (data['disposal_steps'] ?? ''),
        tips: (data['tips'] is List)
            ? (data['tips'] as List).join('\n')
            : (data['tips'] ?? ''),
        nearbyCenter: data['nearby_center'] ?? data['nearbyCenter'] ?? '',
        imageUrl: cloudinaryImageUrl ?? '', // Use Cloudinary URL
        containsMicroplastics:
            data['contains_microplastics'] ??
            data['containsMicroplastics'] ??
            false,
        palmOilDerivative:
            data['palm_oil_derivative'] ?? data['palmOilDerivative'] ?? false,
        crueltyFree: data['cruelty_free'] ?? data['crueltyFree'] ?? false,
      );

      // Save to Firestore using FirebaseService (handles all collections)
      await FirebaseService().saveUserScan(
        analysis: aiOutput ?? 'Scanned from ${data['source'] ?? 'barcode'}',
        productName: analysisData.productName,
        ecoScore: analysisData.ecoScore,
        carbonFootprint: analysisData.carbonFootprint,
        imageUrl: analysisData.imageUrl, // Cloudinary URL
        category: analysisData.category,
        ingredients: analysisData.ingredients,
        packagingType: analysisData.packagingType,
        disposalSteps: analysisData.disposalMethod
            .split('\n')
            .where((s) => s.trim().isNotEmpty)
            .toList(),
        tips: analysisData.tips,
        nearbyCenter: analysisData.nearbyCenter,
        isDisposal: true,
        containsMicroplastics: analysisData.containsMicroplastics,
        palmOilDerivative: analysisData.palmOilDerivative,
        crueltyFree: analysisData.crueltyFree,
      );

      debugPrint('Product saved successfully to Firestore');

      if (mounted) {
        // Navigate to result screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ResultDisposalScreen(analysisData: analysisData),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving product: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Failed to save product data. Please check your internet connection and try again.',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                _saveAndNavigate(data, aiOutput);
              },
            ),
          ),
        );
      }
    }
  }

  void _showProductNotFoundDialog(String barcode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Product Not Found'),
        content: Text(
          'The product with barcode "$barcode" was not found in Open Food Facts or Open Beauty Facts databases.\n\nPlease try scanning a different product or use the camera to capture a product photo instead.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _scannedBarcode = null;
              });
            },
            child: const Text('Try Again'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Go back to previous screen
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'Scan Barcode',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Camera Scanner
          if (_controller != null)
            MobileScanner(
              controller: _controller!,
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty && !_isProcessing) {
                  final barcode = barcodes.first;
                  if (barcode.rawValue != null) {
                    _handleBarcode(barcode.rawValue!);
                  }
                }
              },
            ),

          // Scanning overlay
          if (!_isProcessing)
            Center(
              child: Container(
                width: 300,
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: kPrimaryGreen, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Stack(
                  children: [
                    // Corner accents
                    ...List.generate(4, (index) {
                      return Positioned(
                        top: index < 2 ? 0 : null,
                        bottom: index >= 2 ? 0 : null,
                        left: index % 2 == 0 ? 0 : null,
                        right: index % 2 == 1 ? 0 : null,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: kPrimaryGreen,
                            borderRadius: BorderRadius.only(
                              topLeft: index == 0
                                  ? const Radius.circular(17)
                                  : Radius.zero,
                              topRight: index == 1
                                  ? const Radius.circular(17)
                                  : Radius.zero,
                              bottomLeft: index == 2
                                  ? const Radius.circular(17)
                                  : Radius.zero,
                              bottomRight: index == 3
                                  ? const Radius.circular(17)
                                  : Radius.zero,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

          // Instruction text
          if (!_isProcessing)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Position barcode within the frame',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // Flash toggle button
          if (!_isProcessing)
            Positioned(
              top: 20,
              right: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    _torchOn ? Icons.flash_on : Icons.flash_off,
                    color: _torchOn ? kPrimaryYellow : Colors.white,
                  ),
                  onPressed: _toggleFlash,
                ),
              ),
            ),

          // Processing overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.8),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(kPrimaryGreen),
                      strokeWidth: 4,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Processing Barcode',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_scannedBarcode != null)
                            Text(
                              _scannedBarcode!,
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 14,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            'Searching databases...',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
