import 'package:flutter/material.dart';
import 'package:ecopilot/models/product_analysis_data.dart';
import 'package:ecopilot/screens/better_alternative_screen.dart';

/// Wrapper screen that shows alternatives for a specific scanned product
/// Redirects to BetterAlternativeScreen for generation
class NewAlternativeScreen extends StatelessWidget {
  final ProductAnalysisData? scannedProduct;

  const NewAlternativeScreen({super.key, this.scannedProduct});

  @override
  Widget build(BuildContext context) {
    if (scannedProduct == null) {
      // If no product, go back
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop();
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return BetterAlternativeScreen(scannedProduct: scannedProduct!);
  }
}
