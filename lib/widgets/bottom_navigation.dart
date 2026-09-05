import 'package:flutter/material.dart';
import 'package:ecopilot/utils/constants.dart' as constants;

/// Reusable bottom navigation bar for the app.
///
/// Usage:
/// AppBottomNavigationBar(
///   currentIndex: currentIndex,
///   onTap: (i) { /* navigate */ },
/// )
class AppBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: currentIndex,
      selectedItemColor: constants.kPrimaryGreen,
      unselectedItemColor: Colors.grey,
      onTap: onTap,
      items: const <BottomNavigationBarItem>[
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.shopping_cart),label: 'Alternative',),
        BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner),label: 'Scan',),
        BottomNavigationBarItem(icon: Icon(Icons.delete_sweep),label: 'Dispose',),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }
}
