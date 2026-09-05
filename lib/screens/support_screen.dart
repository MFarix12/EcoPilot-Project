// lib/home/support_screen.dart

import 'package:ecopilot/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/constants.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  // Functional Methods

  /// Open email client for contact/bug report
  Future<void> _contactUs() async {
    final user = FirebaseAuth.instance.currentUser;
    final userEmail = user?.email ?? 'Not logged in';

    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@ecopilot.com',
      query:
          'subject=EcoPilot Support Request&body=Hi EcoPilot Team,%0D%0A%0D%0AUser: $userEmail%0D%0A%0D%0APlease describe your issue or question:%0D%0A%0D%0A',
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open email client. Please email support@ecopilot.com',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Report a bug with detailed template
  Future<void> _reportBug() async {
    final user = FirebaseAuth.instance.currentUser;
    final userEmail = user?.email ?? 'Not logged in';

    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'bugs@ecopilot.com',
      query:
          'subject=Bug Report - EcoPilot App&body=Bug Report%0D%0A%0D%0AUser: $userEmail%0D%0A%0D%0ASteps to reproduce:%0D%0A1. %0D%0A2. %0D%0A3. %0D%0A%0D%0AExpected behavior:%0D%0A%0D%0AActual behavior:%0D%0A%0D%0ADevice info:%0D%0A',
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open email client'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Show FAQ screen
  void _showFAQ() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FAQScreen()),
    );
  }

  /// Show feature request form
  void _showFeatureRequest() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FeatureRequestSheet(),
    );
  }

  /// Rate the app on store
  Future<void> _rateApp() async {
    // For Android
    const playStoreUrl =
        'https://play.google.com/store/apps/details?id=com.ecopilot.app';

    // For iOS (if needed)
    // const appStoreUrl = 'https://apps.apple.com/app/idYOUR_APP_ID';

    final Uri url = Uri.parse(playStoreUrl);

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      // Show in-app rating dialog as fallback
      if (mounted) {
        _showInAppRatingDialog();
      }
    }
  }

  /// Show in-app rating dialog
  void _showInAppRatingDialog() {
    int rating = 0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rate EcoPilot'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('How would you rate your experience?'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < rating ? Icons.star : Icons.star_border,
                      color: kPrimaryYellow,
                      size: 32,
                    ),
                    onPressed: () {
                      setDialogState(() {
                        rating = index + 1;
                      });
                    },
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: rating > 0
                  ? () async {
                      Navigator.pop(context);
                      await _submitRating(rating);
                    }
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: kPrimaryGreen),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  /// Submit rating to Firebase
  Future<void> _submitRating(int rating) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('app_ratings')
          .doc(user.uid)
          .set({
            'rating': rating,
            'userId': user.uid,
            'email': user.email,
            'timestamp': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Thank you for your $rating-star rating!'),
            backgroundColor: kPrimaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting rating: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Show video tutorials
  void _showVideoTutorials() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VideoTutorialsScreen()),
    );
  }

  /// Open community forum
  Future<void> _openCommunityForum() async {
    const forumUrl = 'https://community.ecopilot.com';
    final Uri url = Uri.parse(forumUrl);

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open community forum'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Copy email to clipboard
  void _copyEmail() {
    Clipboard.setData(const ClipboardData(text: 'support@ecopilot.com'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Email copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Open website
  Future<void> _openWebsite() async {
    const websiteUrl = 'https://www.ecopilot.com';
    final Uri url = Uri.parse(websiteUrl);

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open website'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: CustomScrollView(
        slivers: [
          // Hero Header with Gradient
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: kPrimaryGreen,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                    colors: [kPrimaryGreen, kPrimaryGreen.withOpacity(0.8)],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: 40),
                      Icon(Icons.support_agent, size: 80, color: Colors.white),
                      SizedBox(height: 12),
                      Text(
                        'Support Center',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'We\'re here to help you on your eco-journey',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 14),
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

                  // Quick Help Card
                  _buildQuickHelpCard(),

                  const SizedBox(height: 24),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text(
                      'How can we help?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Support Options with modern cards
                  _buildSupportOption(
                    icon: Icons.forum_rounded,
                    title: 'Contact Us',
                    subtitle: 'Send us a message or report a bug',
                    color: Colors.blue,
                    onTap: _contactUs,
                  ),

                  _buildSupportOption(
                    icon: Icons.bug_report_rounded,
                    title: 'Report a Bug',
                    subtitle: 'Help us fix issues in the app',
                    color: Colors.red,
                    onTap: _reportBug,
                  ),

                  _buildSupportOption(
                    icon: Icons.help_outline_rounded,
                    title: 'FAQ',
                    subtitle: 'Find answers to common questions',
                    color: Colors.orange,
                    onTap: _showFAQ,
                  ),

                  _buildSupportOption(
                    icon: Icons.lightbulb_outline_rounded,
                    title: 'Suggest a Feature',
                    subtitle: 'Help us improve EcoPilot',
                    color: Colors.purple,
                    onTap: _showFeatureRequest,
                  ),

                  _buildSupportOption(
                    icon: Icons.star_outline_rounded,
                    title: 'Rate EcoPilot',
                    subtitle: 'Love the app? Leave us a review!',
                    color: Colors.amber,
                    onTap: _rateApp,
                  ),

                  _buildSupportOption(
                    icon: Icons.video_library_rounded,
                    title: 'Video Tutorials',
                    subtitle: 'Learn how to use EcoPilot features',
                    color: Colors.teal,
                    onTap: _showVideoTutorials,
                  ),

                  _buildSupportOption(
                    icon: Icons.people_rounded,
                    title: 'Community Forum',
                    subtitle: 'Connect with other eco-warriors',
                    color: Colors.indigo,
                    onTap: _openCommunityForum,
                  ),

                  const SizedBox(height: 24),

                  // Contact Information Card
                  _buildContactCard(),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickHelpCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kPrimaryYellow.withOpacity(0.3),
            kPrimaryYellow.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.tips_and_updates,
              color: Colors.orange,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Tip',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Most questions can be answered in our FAQ section',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.black26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: kPrimaryGreen, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Contact Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildContactRow(
            Icons.email_outlined,
            'support@ecopilot.com',
            onTap: _copyEmail,
          ),
          const SizedBox(height: 8),
          _buildContactRow(
            Icons.language,
            'www.ecopilot.com',
            onTap: _openWebsite,
          ),
          const SizedBox(height: 8),
          _buildContactRow(Icons.access_time, 'Mon-Fri, 9AM-5PM'),
        ],
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String text, {VoidCallback? onTap}) {
    final row = Row(
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: onTap != null ? kPrimaryGreen : Colors.black54,
              decoration: onTap != null ? TextDecoration.underline : null,
            ),
          ),
        ),
        if (onTap != null)
          const Icon(Icons.touch_app, size: 16, color: Colors.black26),
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: row,
        ),
      );
    }
    return row;
  }
}

// FAQ Screen
class FAQScreen extends StatefulWidget {
  const FAQScreen({super.key});

  @override
  State<FAQScreen> createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> {
  int? _expandedIndex;

  final List<Map<String, String>> _faqs = [
    {
      'question': 'How do I scan a product?',
      'answer':
          'Tap the green scan button on the home screen, then point your camera at the product barcode or QR code. The app will automatically detect and analyze the product.',
    },
    {
      'question': 'What does the Eco Score mean?',
      'answer':
          'The Eco Score rates products from A+ (most eco-friendly) to E (least eco-friendly) based on factors like material sustainability, carbon footprint, recyclability, and manufacturing practices.',
    },
    {
      'question': 'How accurate are the alternative suggestions?',
      'answer':
          'Our AI-powered system uses Gemini 2.5 Pro and a comprehensive database to suggest alternatives. We consider eco-scores, materials, pricing, and availability to provide the best recommendations.',
    },
    {
      'question': 'Can I save products to my wishlist?',
      'answer':
          'Yes! When viewing alternatives, tap the heart icon to add products to your wishlist. You can access your saved items from your profile.',
    },
    {
      'question': 'How do I find recycling centers near me?',
      'answer':
          'Go to the Recycling Centers screen from the main menu. The app will show nearby centers based on your location. You can filter by material type and see operating hours.',
    },
    {
      'question': 'What is carbon savings?',
      'answer':
          'Carbon savings shows the environmental impact difference between your scanned product and eco-friendly alternatives. It\'s measured in CO2 equivalents.',
    },
    {
      'question': 'How do I earn eco points?',
      'answer':
          'Earn points by scanning products, choosing eco-friendly alternatives, visiting recycling centers, and completing daily eco-challenges. Check the leaderboard to see your progress!',
    },
    {
      'question': 'Is my data secure?',
      'answer':
          'Yes! We use Firebase security and encryption for all user data. You can manage your privacy settings and delete your data anytime from Settings > Data & Privacy.',
    },
    {
      'question': 'Can I use the app offline?',
      'answer':
          'Basic scanning works offline using cached data, but features like AI alternatives, real-time prices, and leaderboard require an internet connection.',
    },
    {
      'question': 'How do I delete my account?',
      'answer':
          'Go to Settings > Data & Privacy > Delete Account. Please note this action is permanent and will delete all your data including scan history, wishlist, and eco points.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Frequently Asked Questions'),
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _faqs.length,
        itemBuilder: (context, index) {
          final faq = _faqs[index];
          final isExpanded = _expandedIndex == index;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
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
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kPrimaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isExpanded ? Icons.question_answer : Icons.help_outline,
                    color: kPrimaryGreen,
                  ),
                ),
                title: Text(
                  faq['question']!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                trailing: Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: kPrimaryGreen,
                ),
                onExpansionChanged: (expanded) {
                  setState(() {
                    _expandedIndex = expanded ? index : null;
                  });
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
                    child: Text(
                      faq['answer']!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// Feature Request Sheet
class FeatureRequestSheet extends StatefulWidget {
  const FeatureRequestSheet({super.key});

  @override
  State<FeatureRequestSheet> createState() => _FeatureRequestSheetState();
}

class _FeatureRequestSheetState extends State<FeatureRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _category = 'Feature Enhancement';
  bool _submitting = false;

  final List<String> _categories = [
    'Feature Enhancement',
    'New Feature',
    'UI/UX Improvement',
    'Performance',
    'Other',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance.collection('feature_requests').add({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'category': _category,
        'userId': user?.uid,
        'userEmail': user?.email,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'votes': 0,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Thank you! Your feature request has been submitted.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.lightbulb,
                        color: Colors.purple,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Suggest a Feature',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Feature Title',
                    hintText: 'Brief description of your idea',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.title),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.category),
                  ),
                  items: _categories.map((cat) {
                    return DropdownMenuItem(value: cat, child: Text(cat));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _category = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    hintText: 'Explain your feature idea in detail',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.description),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a description';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submitRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text(
                            'Submit Feature Request',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
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
}

// Video Tutorials Screen
class VideoTutorialsScreen extends StatelessWidget {
  const VideoTutorialsScreen({super.key});

  final List<Map<String, dynamic>> _tutorials = const [
    {
      'title': 'Getting Started with EcoPilot',
      'duration': '2:30',
      'thumbnail': Icons.play_circle_outline,
      'url': 'https://www.youtube.com/watch?v=example1',
    },
    {
      'title': 'How to Scan Products',
      'duration': '1:45',
      'thumbnail': Icons.qr_code_scanner,
      'url': 'https://www.youtube.com/watch?v=example2',
    },
    {
      'title': 'Understanding Eco Scores',
      'duration': '3:15',
      'thumbnail': Icons.eco,
      'url': 'https://www.youtube.com/watch?v=example3',
    },
    {
      'title': 'Finding Eco-Friendly Alternatives',
      'duration': '2:00',
      'thumbnail': Icons.compare_arrows,
      'url': 'https://www.youtube.com/watch?v=example4',
    },
    {
      'title': 'Using the Wishlist Feature',
      'duration': '1:30',
      'thumbnail': Icons.favorite,
      'url': 'https://www.youtube.com/watch?v=example5',
    },
    {
      'title': 'Locating Recycling Centers',
      'duration': '2:45',
      'thumbnail': Icons.location_on,
      'url': 'https://www.youtube.com/watch?v=example6',
    },
  ];

  Future<void> _openVideo(BuildContext context, String url) async {
    final Uri videoUrl = Uri.parse(url);

    if (await canLaunchUrl(videoUrl)) {
      await launchUrl(videoUrl, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open video'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Video Tutorials'),
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tutorials.length,
        itemBuilder: (context, index) {
          final tutorial = _tutorials[index];

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
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
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openVideo(context, tutorial['url']),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              kPrimaryGreen.withOpacity(0.2),
                              kPrimaryGreen.withOpacity(0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          tutorial['thumbnail'],
                          size: 40,
                          color: kPrimaryGreen,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tutorial['title'],
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  tutorial['duration'],
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.play_arrow,
                        color: kPrimaryGreen,
                        size: 32,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
