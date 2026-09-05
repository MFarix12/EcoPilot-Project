// lib/home/setting_screen.dart

import 'package:ecopilot/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../../utils/constants.dart';
import '../../utils/theme_provider.dart';
import 'profile_screen.dart';
import 'notification_screen.dart';
import 'support_screen.dart';
import 'package:ecopilot/screens/profile_screen.dart'
    as ps
    show ChangePasswordScreen;

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  bool _darkMode = false;
  bool _locationServices = true;
  bool _dailyTips = true;
  bool _pushNotifications = true;
  bool _emailNotifications = false;
  bool _autoScan = false;
  bool _soundEffects = true;
  bool _hapticFeedback = true;
  bool _biometricLogin = false;
  String _language = 'English (US)';
  String _defaultCenter = 'Tanjung Malim Center';
  String _imageQuality = 'High';
  int _cacheSize = 0; // In MB
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _calculateCacheSize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync dark mode state with theme provider
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    if (_darkMode != themeProvider.isDarkMode) {
      setState(() {
        _darkMode = themeProvider.isDarkMode;
      });
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _darkMode = prefs.getBool('dark_mode') ?? false;
      _locationServices = prefs.getBool('location_services') ?? true;
      _dailyTips = prefs.getBool('daily_tips') ?? true;
      _pushNotifications = prefs.getBool('push_notifications') ?? true;
      _emailNotifications = prefs.getBool('email_notifications') ?? false;
      _autoScan = prefs.getBool('auto_scan') ?? false;
      _soundEffects = prefs.getBool('sound_effects') ?? true;
      _hapticFeedback = prefs.getBool('haptic_feedback') ?? true;
      _biometricLogin = prefs.getBool('biometric_login') ?? false;
      _language = prefs.getString('language') ?? 'English (US)';
      _defaultCenter =
          prefs.getString('default_center') ?? 'Tanjung Malim Center';
      _imageQuality = prefs.getString('image_quality') ?? 'High';
    });
  }

  Future<void> _calculateCacheSize() async {
    // Simulate cache calculation
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _cacheSize = prefs.getInt('cache_size') ?? 0;
    });
  }

  Future<void> _setBoolPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _setStringPref(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  // New functional methods

  Future<void> _requestLocationPermission() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Location services enabled 📍'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _scheduleDailyTips() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Daily tips scheduled! You\'ll receive eco-tips daily 💡',
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _requestNotificationPermission() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Push notifications enabled 🔔'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<bool> _setupBiometric(bool enable) async {
    if (enable) {
      // Show dialog to confirm biometric setup
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable Biometric Login'),
          content: const Text(
            'Use your fingerprint or face ID to log in securely.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: kPrimaryGreen),
              child: const Text('Enable'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric login enabled 👆')),
        );
        return true;
      }
      return false;
    } else {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Biometric login disabled')));
      return true;
    }
  }

  Future<void> _configureAutoLock() async {
    final options = [
      '1 minute',
      '5 minutes',
      '15 minutes',
      '30 minutes',
      'Never',
    ];
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Auto-Lock Timer'),
        children: options
            .map(
              (option) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, option),
                child: Text(option),
              ),
            )
            .toList(),
      ),
    );

    if (selected != null && mounted) {
      await _setStringPref('auto_lock', selected);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Auto-lock set to: $selected')));
    }
  }

  Future<void> _chooseImageQuality() async {
    final qualities = ['Low', 'Medium', 'High', 'Ultra'];
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Image Quality for Scanning'),
        children: qualities
            .map(
              (q) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, q),
                child: Row(
                  children: [
                    if (q == _imageQuality)
                      Icon(Icons.check, color: kPrimaryGreen, size: 20),
                    if (q == _imageQuality) const SizedBox(width: 8),
                    Text(q),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );

    if (selected != null) {
      setState(() => _imageQuality = selected);
      await _setStringPref('image_quality', selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image quality set to: $selected')),
      );
    }
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Cache'),
        content: Text('This will free up $_cacheSize MB of storage.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _loading = true);

      // Simulate cache clearing
      await Future.delayed(const Duration(seconds: 2));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('cache_size', 0);

      setState(() {
        _cacheSize = 0;
        _loading = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared successfully! ✓')),
      );
    }
  }

  Future<void> _downloadUserData() async {
    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Not logged in');
      }

      // Fetch user data from Firestore
      // ignore: unused_local_variable
      final userData = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      // Show dialog with data summary
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Your Data'),
          content: SingleChildScrollView(
            child: Text(
              'Email: ${user.email}\n'
              'User ID: ${user.uid}\n'
              'Data collected:\n'
              '- Scan history\n'
              '- Disposal records\n'
              '- Eco score progress\n\n'
              'Full data export will be sent to your email within 24 hours.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Data export request sent! Check your email.',
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: kPrimaryGreen),
              child: const Text('Request Export'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch data: ${e.toString()}')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _clearScanHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Scan History'),
        content: const Text(
          'This will permanently delete all your scan history. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear History'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          // Delete scan history from Firestore
          final batch = FirebaseFirestore.instance.batch();
          final scans = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('scans')
              .get();

          for (var doc in scans.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();

          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Scan history cleared')));
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  Future<void> _manageCookies() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manage Cookies'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Essential Cookies: Always On'),
            SizedBox(height: 8),
            Text(
              'These cookies are necessary for the app to function properly.',
            ),
            SizedBox(height: 16),
            Text('Analytics Cookies: Optional'),
            SizedBox(height: 8),
            Text('Help us improve by sharing anonymous usage data.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _dataCollectionSettings() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _DataCollectionScreen()),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone. All your data will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _deleteAccount();
    }
  }

  Future<void> _deleteAccount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Delete user data from Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete();

      // Delete auth account
      await user.delete();

      if (!mounted) return;
      // Navigate to login screen
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting account: ${e.toString()}')),
      );
    }
  }

  Future<void> _reportBug() async {
    final email = Uri.encodeComponent('support@ecopilot.com');
    final subject = Uri.encodeComponent('Bug Report - EcoPilot App');
    final body = Uri.encodeComponent(
      'Please describe the bug:\n\n'
      'Steps to reproduce:\n1. \n2. \n3. \n\n'
      'Expected behavior:\n\n'
      'Actual behavior:\n\n'
      'Device info: ${DateTime.now()}',
    );
    final url = Uri.parse('mailto:$email?subject=$subject&body=$body');

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open email client')),
      );
    }
  }

  Future<void> _rateApp() async {
    // Open app store/play store
    const playStoreUrl =
        'https://play.google.com/store/apps/details?id=com.ecopilot.app';
    final url = Uri.parse(playStoreUrl);

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rate EcoPilot'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('How would you rate your experience?'),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star, color: Colors.amber, size: 32),
                  Icon(Icons.star, color: Colors.amber, size: 32),
                  Icon(Icons.star, color: Colors.amber, size: 32),
                  Icon(Icons.star, color: Colors.amber, size: 32),
                  Icon(Icons.star, color: Colors.amber, size: 32),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Thank you for your feedback!')),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: kPrimaryGreen),
              child: const Text('Submit'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _contactUs() async {
    final email = Uri.encodeComponent('support@ecopilot.com');
    final subject = Uri.encodeComponent('Contact - EcoPilot App');
    final url = Uri.parse('mailto:$email?subject=$subject');

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Contact Us'),
          content: const Text(
            'Email: support@ecopilot.com\n'
            'Phone: +60 12-345 6789\n'
            'Hours: Mon-Fri, 9AM-6PM',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  void _showLicenses() {
    showLicensePage(
      context: context,
      applicationName: 'EcoPilot',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.eco, size: 48, color: kPrimaryGreen),
      applicationLegalese: '© 2025 EcoPilot. All rights reserved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canPop = Navigator.of(context).canPop();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // Hero Header with Gradient
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: isDark ? theme.cardColor : kPrimaryGreen,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: theme.colorScheme.onPrimary),
              onPressed: () {
                if (canPop) {
                  Navigator.of(context).pop();
                } else {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                  );
                }
              },
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [theme.cardColor, theme.cardColor.withOpacity(0.8)]
                        : [kPrimaryGreen, kPrimaryGreen.withOpacity(0.8)],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Icon(
                        Icons.settings_rounded,
                        size: 80,
                        color: theme.colorScheme.onPrimary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Settings',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Customize your EcoPilot experience',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  _buildSettingsSection(
                    title: 'Account',
                    icon: Icons.person_outline,
                    items: [
                      _buildSettingsItem(
                        Icons.edit_outlined,
                        'Edit Profile',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen(),
                            ),
                          );
                        },
                      ),
                      _buildSettingsItem(
                        Icons.lock_outline,
                        'Change Password',
                        color: Colors.orange,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ps.ChangePasswordScreen(),
                            ),
                          );
                        },
                      ),
                      _buildSettingsSwitch(
                        'Dark Mode',
                        Icons.dark_mode_outlined,
                        value: _darkMode,
                        color: Colors.indigo,
                        onChanged: (v) async {
                          setState(() => _darkMode = v);

                          // Update theme provider for instant theme switch
                          final themeProvider = Provider.of<ThemeProvider>(
                            context,
                            listen: false,
                          );
                          await themeProvider.setThemeMode(
                            v ? ThemeMode.dark : ThemeMode.light,
                          );

                          // Also save to shared preferences for backward compatibility
                          await _setBoolPref('dark_mode', v);

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                v
                                    ? '🌙 Dark mode enabled'
                                    : '☀️ Light mode enabled',
                              ),
                              duration: const Duration(seconds: 2),
                              backgroundColor: kPrimaryGreen,
                            ),
                          );
                        },
                      ),
                      _buildSettingsSwitch(
                        'Location Services',
                        Icons.location_on_outlined,
                        value: _locationServices,
                        color: Colors.red,
                        onChanged: (v) async {
                          setState(() => _locationServices = v);
                          await _setBoolPref('location_services', v);
                          if (v) {
                            _requestLocationPermission();
                          }
                        },
                      ),
                      _buildSettingsSwitch(
                        'Receive Daily Tips',
                        Icons.lightbulb_outline,
                        value: _dailyTips,
                        color: Colors.amber,
                        onChanged: (v) async {
                          setState(() => _dailyTips = v);
                          await _setBoolPref('daily_tips', v);
                          if (v) {
                            _scheduleDailyTips();
                          }
                        },
                      ),
                      _buildSettingsSwitch(
                        'Auto-Scan Mode',
                        Icons.qr_code_scanner,
                        value: _autoScan,
                        color: Colors.purple,
                        onChanged: (v) async {
                          setState(() => _autoScan = v);
                          await _setBoolPref('auto_scan', v);
                        },
                      ),
                      _buildSettingsSwitch(
                        'Sound Effects',
                        Icons.volume_up_outlined,
                        value: _soundEffects,
                        color: Colors.orange,
                        onChanged: (v) async {
                          setState(() => _soundEffects = v);
                          await _setBoolPref('sound_effects', v);
                          if (v) {
                            HapticFeedback.lightImpact();
                          }
                        },
                      ),
                      _buildSettingsSwitch(
                        'Haptic Feedback',
                        Icons.vibration,
                        value: _hapticFeedback,
                        color: Colors.deepPurple,
                        onChanged: (v) async {
                          setState(() => _hapticFeedback = v);
                          await _setBoolPref('haptic_feedback', v);
                          if (v) {
                            HapticFeedback.mediumImpact();
                          }
                        },
                      ),
                    ],
                  ),

                  _buildSettingsSection(
                    title: 'Notifications',
                    icon: Icons.notifications_outlined,
                    items: [
                      _buildSettingsSwitch(
                        'Push Notifications',
                        Icons.notifications_active_outlined,
                        value: _pushNotifications,
                        color: Colors.blue,
                        onChanged: (v) async {
                          setState(() => _pushNotifications = v);
                          await _setBoolPref('push_notifications', v);
                          if (v) {
                            _requestNotificationPermission();
                          }
                        },
                      ),
                      _buildSettingsSwitch(
                        'Email Notifications',
                        Icons.email_outlined,
                        value: _emailNotifications,
                        color: Colors.teal,
                        onChanged: (v) async {
                          setState(() => _emailNotifications = v);
                          await _setBoolPref('email_notifications', v);
                        },
                      ),
                      _buildSettingsItem(
                        Icons.settings_outlined,
                        'Manage Notifications',
                        color: Colors.indigo,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const NotificationScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  _buildSettingsSection(
                    title: 'Security',
                    icon: Icons.security,
                    items: [
                      _buildSettingsSwitch(
                        'Biometric Login',
                        Icons.fingerprint,
                        value: _biometricLogin,
                        color: Colors.green,
                        onChanged: (v) async {
                          final success = await _setupBiometric(v);
                          if (success) {
                            setState(() => _biometricLogin = v);
                            await _setBoolPref('biometric_login', v);
                          }
                        },
                      ),
                      _buildSettingsItem(
                        Icons.lock_clock,
                        'Auto-Lock',
                        subtitle: 'After 5 minutes of inactivity',
                        color: Colors.deepOrange,
                        onTap: _configureAutoLock,
                      ),
                    ],
                  ),

                  _buildSettingsSection(
                    title: 'Disposal & Scanning',
                    icon: Icons.recycling,
                    items: [
                      _buildSettingsItem(
                        Icons.place_outlined,
                        'Default Recycling Center',
                        subtitle: _defaultCenter,
                        color: kPrimaryGreen,
                        onTap: _chooseDefaultCenter,
                      ),
                      _buildSettingsItem(
                        Icons.translate,
                        'Set Language',
                        subtitle: _language,
                        color: Colors.teal,
                        onTap: _chooseLanguage,
                      ),
                    ],
                  ),

                  _buildSettingsSection(
                    title: 'Storage & Data',
                    icon: Icons.storage,
                    items: [
                      _buildSettingsItem(
                        Icons.photo_library_outlined,
                        'Image Quality',
                        subtitle: _imageQuality,
                        color: Colors.cyan,
                        onTap: _chooseImageQuality,
                      ),
                      _buildSettingsItem(
                        Icons.folder_outlined,
                        'Cache Size',
                        subtitle: '$_cacheSize MB',
                        color: Colors.brown,
                        trailing: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: _clearCache,
                      ),
                      _buildSettingsItem(
                        Icons.download_outlined,
                        'Download My Data',
                        subtitle: 'Export your EcoPilot data',
                        color: Colors.lightBlue,
                        onTap: _downloadUserData,
                      ),
                    ],
                  ),

                  _buildSettingsSection(
                    title: 'Data & Privacy',
                    icon: Icons.privacy_tip_outlined,
                    items: [
                      _buildSettingsItem(
                        Icons.history,
                        'Clear Scan History',
                        color: Colors.orange,
                        onTap: _clearScanHistory,
                      ),
                      _buildSettingsItem(
                        Icons.cookie_outlined,
                        'Manage Cookies',
                        color: Colors.brown,
                        onTap: _manageCookies,
                      ),
                      _buildSettingsItem(
                        Icons.shield_outlined,
                        'Data Collection Settings',
                        subtitle: 'Control what data we collect',
                        color: Colors.blueGrey,
                        onTap: _dataCollectionSettings,
                      ),
                      _buildSettingsItem(
                        Icons.delete_forever,
                        'Delete Account',
                        color: Colors.red,
                        onTap: _confirmDeleteAccount,
                      ),
                    ],
                  ),

                  _buildSettingsSection(
                    title: 'Support & Feedback',
                    icon: Icons.help_outline,
                    items: [
                      _buildSettingsItem(
                        Icons.help_center_outlined,
                        'Help Center',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SupportScreen(),
                            ),
                          );
                        },
                      ),
                      _buildSettingsItem(
                        Icons.bug_report_outlined,
                        'Report a Bug',
                        color: Colors.red,
                        onTap: _reportBug,
                      ),
                      _buildSettingsItem(
                        Icons.star_outline,
                        'Rate Us',
                        subtitle: 'Share your feedback',
                        color: Colors.amber,
                        onTap: _rateApp,
                      ),
                      _buildSettingsItem(
                        Icons.email_outlined,
                        'Contact Us',
                        color: Colors.green,
                        onTap: _contactUs,
                      ),
                    ],
                  ),

                  _buildSettingsSection(
                    title: 'Legal & Info',
                    icon: Icons.info_outline,
                    items: [
                      _buildSettingsItem(
                        Icons.policy_outlined,
                        'Privacy Policy',
                        color: Colors.purple,
                        onTap: () => _openInfo('Privacy Policy', _privacyText),
                      ),
                      _buildSettingsItem(
                        Icons.description_outlined,
                        'Terms of Service',
                        color: Colors.deepOrange,
                        onTap: () => _openInfo('Terms of Service', _termsText),
                      ),
                      _buildSettingsItem(
                        Icons.gavel,
                        'Licenses',
                        subtitle: 'Open source licenses',
                        color: Colors.indigo,
                        onTap: _showLicenses,
                      ),
                      _buildSettingsItem(
                        Icons.info_outlined,
                        'About EcoPilot',
                        subtitle: 'Version 1.0.0',
                        color: Colors.blueGrey,
                        onTap: () {
                          showAboutDialog(
                            context: context,
                            applicationName: 'EcoPilot',
                            applicationVersion: '1.0.0',
                            applicationIcon: const Icon(
                              Icons.eco,
                              size: 48,
                              color: kPrimaryGreen,
                            ),
                            applicationLegalese:
                                '© 2025 EcoPilot. All rights reserved.',
                          );
                        },
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

  Widget _buildSettingsSection({
    required String title,
    required IconData icon,
    required List<Widget> items,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: kPrimaryGreen, size: 22),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withOpacity(0.3)
                    : Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(children: items),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // Settings Item with navigation/action
  Widget _buildSettingsItem(
    IconData icon,
    String title, {
    String? subtitle,
    required Color color,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  // Settings Item with a switch
  Widget _buildSettingsSwitch(
    String title,
    IconData icon, {
    bool value = false,
    required Color color,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: kPrimaryGreen,
          ),
        ],
      ),
    );
  }

  Future<void> _chooseLanguage() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose language'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('English (US)'),
            child: const Text('English (US)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('Bahasa Melayu'),
            child: const Text('Bahasa Melayu'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('中文'),
            child: const Text('中文'),
          ),
        ],
      ),
    );

    if (selected != null) {
      if (!mounted) return;
      setState(() => _language = selected);
      await _setStringPref('language', selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Language saved. Restart app to apply.')),
      );
    }
  }

  Future<void> _chooseDefaultCenter() async {
    final centers = [
      'Tanjung Malim Center',
      'Kuala Lumpur Center',
      'Penang Center',
    ];
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Default Recycling Center'),
        children: centers
            .map(
              (c) => SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(c),
                child: Text(c),
              ),
            )
            .toList(),
      ),
    );

    if (selected != null) {
      if (!mounted) return;
      setState(() => _defaultCenter = selected);
      await _setStringPref('default_center', selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Default recycling center saved.')),
      );
    }
  }

  void _openInfo(String title, String content) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _InfoScreen(title: title, content: content),
      ),
    );
  }

  static const String _privacyText =
      'This is the privacy policy placeholder. Replace with real content.';
  static const String _termsText =
      'These are the terms of service placeholder. Replace with real content.';
}

class _InfoScreen extends StatelessWidget {
  final String title;
  final String content;
  const _InfoScreen({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: theme.brightness == Brightness.dark
            ? theme.cardColor
            : kPrimaryGreen,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Text(
            content,
            style: TextStyle(
              fontSize: 16,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _DataCollectionScreen extends StatefulWidget {
  const _DataCollectionScreen();

  @override
  State<_DataCollectionScreen> createState() => _DataCollectionScreenState();
}

class _DataCollectionScreenState extends State<_DataCollectionScreen> {
  bool _collectUsageData = true;
  bool _collectCrashReports = true;
  bool _collectLocationData = false;
  bool _personalization = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Collection'),
        backgroundColor: isDark ? theme.cardColor : kPrimaryGreen,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choose what data you share with us',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We respect your privacy. Control what information you share to help us improve EcoPilot.',
            style: TextStyle(color: theme.textTheme.bodyMedium?.color),
          ),
          const SizedBox(height: 24),
          _buildDataSwitch(
            'Usage Analytics',
            'Help us improve by sharing anonymous usage data',
            Icons.analytics_outlined,
            _collectUsageData,
            (v) => setState(() => _collectUsageData = v),
          ),
          _buildDataSwitch(
            'Crash Reports',
            'Automatically send crash reports to fix bugs',
            Icons.bug_report_outlined,
            _collectCrashReports,
            (v) => setState(() => _collectCrashReports = v),
          ),
          _buildDataSwitch(
            'Location Data',
            'Share your location for nearby recycling centers',
            Icons.location_on_outlined,
            _collectLocationData,
            (v) => setState(() => _collectLocationData = v),
          ),
          _buildDataSwitch(
            'Personalization',
            'Use my data to personalize recommendations',
            Icons.person_outline,
            _personalization,
            (v) => setState(() => _personalization = v),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'All data is encrypted and stored securely. We never sell your data.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSwitch(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: kPrimaryGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: kPrimaryGreen),
        ),
        value: value,
        onChanged: onChanged,
        activeThumbColor: kPrimaryGreen,
      ),
    );
  }
}
