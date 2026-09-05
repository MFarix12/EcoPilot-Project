// lib/screens/onboarding/onboarding_screen.dart

import 'package:flutter/material.dart';
import 'dart:math';
import '../../utils/constants.dart';
import 'package:ecopilot/utils/color_extensions.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController(viewportFraction: 1);
  int _currentPage = 0;

  final List<Map<String, String>> _pages = [
    {
      'title': 'Scan Any Product',
      'image': 'assets/onboarding_eco_product.png',
      'price':
          r'Instantly scan products to see their Eco-Score and environmental impact',
    },
    {
      'title': 'Discover Eco Friendly',
      'image': 'assets/onboarding_eco_product_2.png',
      'price':
          r'Find greener alternatives to make smarter, sustainable choices',
    },
    {
      'title': 'Track & Improve',
      'image': 'assets/onboarding_eco_product_3.png',
      'price': r'Track your progress and grow your positive impact every day',
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kPrimaryGreen,
              kPrimaryGreen.withOpacity(0.8),
              Colors.teal.shade700,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Clean Header with Logo
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: colorWithOpacity(Colors.black, 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/ecopilot_logo_white.png',
                        width: 40,
                        height: 40,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'EcoPilot',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

              // // Page Indicator Dots at Top
              // Row(
              //   mainAxisAlignment: MainAxisAlignment.center,
              //   children: List.generate(
              //     _pages.length,
              //     (i) => _buildDot(i == _currentPage),
              //   ),
              // ),

              const SizedBox(height: 20),

              // PageView Content
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (idx) => setState(() => _currentPage = idx),
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    final double imageDim = min(
                      screenSize.width * 0.65,
                      screenSize.height * 0.35,
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Title
                          Text(
                            page['title'] ?? '',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),

                          const SizedBox(height: 40),

                          // Image Container with Modern Design
                          Container(
                            width: imageDim,
                            height: imageDim,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: colorWithOpacity(Colors.black, 0.2),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(30),
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Image.asset(
                                  page['image'] ?? '',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Center(
                                        child: Icon(
                                          Icons.eco,
                                          size: imageDim * 0.4,
                                          color: kPrimaryGreen,
                                        ),
                                      ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 40),

                          // Description
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: colorWithOpacity(Colors.white, 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: colorWithOpacity(Colors.white, 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              page['price'] ?? '',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Bottom CTA Button
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
                child: Column(
                  children: [
                    // Page Indicator Dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _pages.length,
                        (i) => _buildDot(i == _currentPage),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Get Started Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacementNamed('/auth');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryYellow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 8,
                          shadowColor: colorWithOpacity(kPrimaryYellow, 0.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Text(
                              'Get Started',
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.black87,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Skip Text
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacementNamed('/auth');
                      },
                      child: Text(
                        'Skip for now',
                        style: TextStyle(
                          color: colorWithOpacity(Colors.white, 0.8),
                          fontSize: 16,
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
    );
  }

  Widget _buildDot(bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 6),
      width: active ? 32 : 10,
      height: 10,
      decoration: BoxDecoration(
        color: active ? kPrimaryYellow : colorWithOpacity(Colors.white, 0.4),
        borderRadius: BorderRadius.circular(8),
        boxShadow: active
            ? [
                BoxShadow(
                  color: colorWithOpacity(kPrimaryYellow, 0.5),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}
