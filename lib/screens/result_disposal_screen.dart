import 'package:flutter/material.dart';
import 'package:ecopilot/models/product_analysis_data.dart';
import 'package:ecopilot/utils/constants.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ecopilot/auth/firebase_service.dart';
import 'package:ecopilot/screens/disposal_guidance_screen.dart';

class ResultDisposalScreen extends StatelessWidget {
  final ProductAnalysisData analysisData;
  const ResultDisposalScreen({super.key, required this.analysisData});

  List<String> _disposalStepsAsList() {
    if (analysisData.disposalMethod.trim().isEmpty ||
        analysisData.disposalMethod == 'N/A') {
      return [];
    }
    return analysisData.disposalMethod
        .split(RegExp(r"\r?\n"))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Color _scoreColor(String score) {
    final ecoScoreColors = {
      'A': kResultCardGreen,
      'B': kDiscoverMoreGreen,
      'C': kPrimaryYellow,
      'D': kRankSustainabilityHero,
      'E': kWarningRed,
    };
    final firstChar = score.isNotEmpty ? score[0].toUpperCase() : 'N';
    return ecoScoreColors[firstChar] ?? Colors.grey.shade600;
  }

  Future<void> _openMaps(String query) async {
    final Uri uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );
    if (!await launchUrl(uri)) {
      // ignore: avoid_print
      print('Could not launch $uri');
    }
  }

  @override
  Widget build(BuildContext context) {
    final disposalSteps = analysisData.disposalMethod
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: CustomScrollView(
        slivers: [
          // Hero Image Section with Product Name Overlay
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: kPrimaryGreen,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Product Image
                  if (analysisData.imageUrl != null &&
                      analysisData.imageUrl!.isNotEmpty)
                    Image.network(
                      analysisData.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade300,
                        child: Icon(
                          Icons.image_not_supported,
                          size: 80,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    )
                  else if (analysisData.imageFile != null)
                    Image.file(analysisData.imageFile!, fit: BoxFit.cover)
                  else
                    Container(
                      color: Colors.grey.shade200,
                      child: const Icon(
                        Icons.recycling,
                        size: 100,
                        color: kPrimaryGreen,
                      ),
                    ),
                  // Gradient overlay for better text visibility
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                  // Product Name and Category Badge
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product Name
                        Text(
                          analysisData.productName,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black45,
                                offset: Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Category Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimaryGreen,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.category,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                analysisData.category,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Eco Score Badge (Circular - Bottom Right)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            analysisData.ecoScore,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: _scoreColor(analysisData.ecoScore),
                            ),
                          ),
                          Text(
                            'ECO SCORE',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Material Composition Card (Blue)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFBBDEFB),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.inventory_2_outlined,
                            color: Color(0xFF1976D2),
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Material Composition',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                analysisData.packagingType,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1565C0),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Disposal Steps Section
                  Row(
                    children: [
                      const Icon(
                        Icons.playlist_add_check_rounded,
                        color: kPrimaryGreen,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Disposal Steps',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (disposalSteps.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Center(
                        child: Text(
                          'No disposal steps available',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    )
                  else
                    ...disposalSteps.asMap().entries.map((entry) {
                      final index = entry.key;
                      final step = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.grey.shade200,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: kPrimaryGreen,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                step,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.black87,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 24),

                  // Recycling Center Section
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.orange,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Nearby Recycling Center',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200, width: 1),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: kPrimaryGreen.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.place,
                                color: kPrimaryGreen,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    analysisData.nearbyCenter != 'N/A' &&
                                            analysisData.nearbyCenter.isNotEmpty
                                        ? analysisData.nearbyCenter
                                        : 'Find Recycling Center',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    analysisData.nearbyCenter != 'N/A' &&
                                            analysisData.nearbyCenter.isNotEmpty
                                        ? 'Tap to navigate'
                                        : 'Search for nearby centers',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () => _openMaps(
                              analysisData.nearbyCenter != 'N/A' &&
                                      analysisData.nearbyCenter.isNotEmpty
                                  ? analysisData.nearbyCenter
                                  : '${analysisData.productName} recycling center',
                            ),
                            icon: const Icon(
                              Icons.navigation,
                              color: Colors.white,
                              size: 20,
                            ),
                            label: const Text(
                              'Open in Maps',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryGreen,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Eco Tips
                  if (analysisData.tips.isNotEmpty &&
                      analysisData.tips != 'N/A')
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.amber.shade200,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.lightbulb,
                              color: Colors.amber.shade700,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Eco Tips',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  analysisData.tips,
                                  style: TextStyle(
                                    color: Colors.grey.shade800,
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
        ],
      ),
      // Bottom Done button
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: _DoneButton(
            analysisData: analysisData,
            disposalStepsList: _disposalStepsAsList(),
          ),
        ),
      ),
    );
  }
}

class _DoneButton extends StatefulWidget {
  final ProductAnalysisData analysisData;
  final List<String> disposalStepsList;

  const _DoneButton({
    required this.analysisData,
    required this.disposalStepsList,
  });

  @override
  State<_DoneButton> createState() => _DoneButtonState();
}

class _DoneButtonState extends State<_DoneButton> {
  bool _isSaving = false;

  Future<void> _onDonePressed() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final analysisText = widget.analysisData.disposalMethod.isNotEmpty
          ? widget.analysisData.disposalMethod
          : (widget.analysisData.tips.isNotEmpty
                ? widget.analysisData.tips
                : 'Disposal scan');

      await FirebaseService().saveUserScan(
        analysis: analysisText,
        productName: widget.analysisData.productName,
        ecoScore: widget.analysisData.ecoScore,
        carbonFootprint: widget.analysisData.carbonFootprint,
        imageUrl: widget.analysisData.imageUrl,
        category: widget.analysisData.category,
        ingredients: widget.analysisData.ingredients,
        packagingType: widget.analysisData.packagingType,
        disposalSteps: widget.disposalStepsList.isNotEmpty
            ? widget.disposalStepsList
            : null,
        tips: widget.analysisData.tips,
        nearbyCenter: widget.analysisData.nearbyCenter,
        isDisposal: true,
        containsMicroplastics: widget.analysisData.containsMicroplastics,
        palmOilDerivative: widget.analysisData.palmOilDerivative,
        crueltyFree: widget.analysisData.crueltyFree,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved to Recent Disposal')));

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DisposalGuidanceScreen()),
      );
    } catch (e) {
      debugPrint('Failed to save disposal scan: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _onDonePressed,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.check_circle, color: Colors.white, size: 24),
        label: Text(
          _isSaving ? 'Saving...' : 'Done',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimaryGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
          shadowColor: kPrimaryGreen.withOpacity(0.4),
        ),
      ),
    );
  }
}
