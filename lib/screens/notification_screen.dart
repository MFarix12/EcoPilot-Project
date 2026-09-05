import 'dart:convert';

import 'package:ecopilot/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/streak_notification_manager.dart';
import '../services/fcm_service.dart';
import '../utils/constants.dart';

// Notification categories used by the app
enum NotificationCategory {
  dailyChallenge,
  ecoTip,
  milestone,
  scanInsight,
  localAlert,
}

extension NotificationCategoryExt on NotificationCategory {
  String get id => toString().split('.').last;
  String get displayName {
    switch (this) {
      case NotificationCategory.dailyChallenge:
        return 'Daily Challenge';
      case NotificationCategory.ecoTip:
        return 'Eco Tip';
      case NotificationCategory.milestone:
        return 'Milestone';
      case NotificationCategory.scanInsight:
        return 'Scan Insight';
      case NotificationCategory.localAlert:
        return 'Local Alert';
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationCategory.dailyChallenge:
        return Icons.flag;
      case NotificationCategory.ecoTip:
        return Icons.lightbulb;
      case NotificationCategory.milestone:
        return Icons.emoji_events;
      case NotificationCategory.scanInsight:
        return Icons.qr_code_scanner;
      case NotificationCategory.localAlert:
        return Icons.location_on;
    }
  }

  Color get color {
    switch (this) {
      case NotificationCategory.dailyChallenge:
        return Colors.orangeAccent;
      case NotificationCategory.ecoTip:
        return Colors.green;
      case NotificationCategory.milestone:
        return Colors.amber;
      case NotificationCategory.scanInsight:
        return Colors.teal;
      case NotificationCategory.localAlert:
        return Colors.indigo;
    }
  }
}

// Simple model for a notification
class AppNotification {
  final String id;
  final NotificationCategory category;
  final String title;
  final String body;
  final DateTime time;
  bool read;
  final Map<String, dynamic>? data; // optional extra payload

  AppNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.time,
    this.read = false,
    this.data,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        category: NotificationCategory.values.firstWhere(
          (e) => e.id == json['category'],
        ),
        title: json['title'] as String,
        body: json['body'] as String,
        time: DateTime.parse(json['time'] as String),
        read: json['read'] as bool? ?? false,
        data: json['data'] == null
            ? null
            : Map<String, dynamic>.from(json['data'] as Map),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category.id,
    'title': title,
    'body': body,
    'time': time.toIso8601String(),
    'read': read,
    'data': data,
  };
}

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  static const String _prefsKey = 'app_notifications_v1';

  // IDs used for scheduled local notifications
  static const int _dailyChallengeNotifId = 1000;
  static const int _ecoTipNotifId = 1001;

  bool _dailyScheduled = false;
  bool _ecoTipScheduled = false;

  // Streak notification states
  Map<String, bool> _streakNotifStatus = {};
  bool _fcmInitialized = false;

  List<AppNotification> _notifications = [];
  NotificationCategory? _filter; // null = all
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _initSchedules();
    _initStreakNotifications();
    _initFCM();
  }

  Future<void> _initSchedules() async {
    try {
      final d = await NotificationService().isScheduled(_dailyChallengeNotifId);
      final e = await NotificationService().isScheduled(_ecoTipNotifId);
      setState(() {
        _dailyScheduled = d;
        _ecoTipScheduled = e;
      });
    } catch (err) {
      if (kDebugMode) debugPrint('initSchedules err: $err');
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final List parsed = jsonDecode(raw) as List;
        _notifications = parsed
            .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (e) {
        debugPrint('Failed to parse notifications: $e');
        _notifications = [];
      }
    } else {
      _notifications = [];
    }
    // Keep newest first
    _notifications.sort((a, b) => b.time.compareTo(a.time));
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_notifications.map((n) => n.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
  }

  Future<void> _remove(String id) async {
    setState(() {
      _notifications.removeWhere((n) => n.id == id);
    });
    await _save();
  }

  Future<void> _markRead(String id, {bool read = true}) async {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx == -1) return;
    setState(() {
      _notifications[idx].read = read;
    });
    await _save();
  }

  // Initialize streak notifications
  Future<void> _initStreakNotifications() async {
    try {
      _streakNotifStatus = await StreakNotificationManager()
          .getNotificationStatus();
      setState(() {});
      debugPrint('✅ Streak notification status loaded');
    } catch (e) {
      debugPrint('❌ Failed to load streak notification status: $e');
    }
  }

  // Initialize FCM
  Future<void> _initFCM() async {
    try {
      await FCMService().initialize();
      setState(() {
        _fcmInitialized = FCMService().isInitialized;
      });
      debugPrint('✅ FCM initialized in notification screen');
    } catch (e) {
      debugPrint('❌ Failed to initialize FCM: $e');
    }
  }

  // Toggle specific streak notification
  Future<void> _toggleStreakNotification(String type) async {
    try {
      final currentStatus = _streakNotifStatus[type] ?? false;

      if (currentStatus) {
        await StreakNotificationManager().cancelNotification(type);
      } else {
        switch (type) {
          case 'morning':
            await StreakNotificationManager().scheduleMorningEncouragement();
            break;
          case 'midday':
            await StreakNotificationManager().scheduleMidDayReminder();
            break;
          case 'evening':
            await StreakNotificationManager().scheduleEveningWarning();
            break;
          case 'lastchance':
            await StreakNotificationManager().scheduleLastChanceReminder();
            break;
        }
      }

      await _initStreakNotifications(); // Refresh status

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentStatus
                ? 'Streak reminder disabled'
                : 'Streak reminder enabled',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to toggle notification: $e')),
      );
    }
  }

  Future<void> _toggleDailySchedule() async {
    try {
      if (_dailyScheduled) {
        await NotificationService().cancel(_dailyChallengeNotifId);
        setState(() => _dailyScheduled = false);
      } else {
        await NotificationService().scheduleDaily(
          id: _dailyChallengeNotifId,
          title: 'Today\'s Eco Challenge',
          color: kPrimaryGreen,
          body:
              '🌞 Good morning! Complete today\'s challenge and earn +20 EcoPoints.',
          hour: 8,
          minute: 0,
        );
        setState(() => _dailyScheduled = true);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Schedule failed: $e')));
    }
  }

  Future<void> _toggleEcoTipSchedule() async {
    try {
      if (_ecoTipScheduled) {
        await NotificationService().cancel(_ecoTipNotifId);
        setState(() => _ecoTipScheduled = false);
      } else {
        await NotificationService().scheduleDaily(
          id: _ecoTipNotifId,
          title: 'Eco Tip',
          color: Colors.white,
          body:
              '♻️ Eco Tip: Switch to reusable water bottles to cut down on waste.',
          hour: 12,
          minute: 0,
        );
        setState(() => _ecoTipScheduled = true);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Schedule failed: $e')));
    }
  }

  List<AppNotification> get _visible => _filter == null
      ? _notifications
      : _notifications.where((n) => n.category == _filter).toList();

  int get _unreadCount => _notifications.where((n) => !n.read).length;

  void _showDetails(AppNotification n) {
    // mark read when opened
    _markRead(n.id, read: true);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(n.category.icon, color: n.category.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    n.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  _formatTime(n.time),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(n.body, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _markRead(n.id, read: false);
                  },
                  child: const Text('Mark Unread'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    // Navigate based on category or payload
                    if (n.category == NotificationCategory.scanInsight &&
                        n.data != null &&
                        n.data!['productId'] != null) {
                      // Example: navigate to product details (app-specific)
                      // Navigator.of(context).pushNamed('/product', arguments: n.data!['productId']);
                    }
                  },
                  child: const Text('View'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${t.month}/${t.day}/${t.year}';
  }

  Widget _buildFilterChips() {
    final categories = <NotificationCategory?>[
      null,
      ...NotificationCategory.values,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: categories.map((c) {
          final selected = c == _filter;
          final label = c == null ? 'All' : c.displayName;
          final icon = c == null ? Icons.view_list : c.icon;
          final color = c == null ? kPrimaryGreen : c.color;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              avatar: Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : color,
              ),
              selected: selected,
              selectedColor: color,
              backgroundColor: Colors.white,
              checkmarkColor: Colors.white,
              elevation: selected ? 4 : 0,
              shadowColor: color.withOpacity(0.3),
              side: BorderSide(
                color: selected ? color : Colors.grey.shade300,
                width: 1,
              ),
              onSelected: (_) => setState(() => _filter = c),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // Hero Header with Gradient
                SliverAppBar(
                  expandedHeight: 180,
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
                  actions: [
                    IconButton(
                      tooltip: 'Mark all read',
                      icon: const Icon(
                        Icons.mark_email_read,
                        color: Colors.white,
                      ),
                      onPressed: () async {
                        setState(() {
                          for (var n in _notifications) {
                            n.read = true;
                          }
                        });
                        await _save();
                      },
                    ),
                    IconButton(
                      tooltip: 'Clear all',
                      icon: const Icon(
                        Icons.delete_forever,
                        color: Colors.white,
                      ),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            title: const Text('Clear all notifications?'),
                            content: const Text(
                              'This will permanently remove all notifications.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Clear'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          setState(() => _notifications.clear());
                          await _save();
                        }
                      },
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            kPrimaryGreen,
                            kPrimaryGreen.withOpacity(0.8),
                          ],
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
                            const Icon(
                              Icons.notifications_active,
                              size: 60,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Notifications',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$_unreadCount Unread',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Filter Chips
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      _buildFilterChips(),
                      const SizedBox(height: 2),

                      // Scheduling controls with modern design
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 4.0,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildScheduleButton(
                                icon: Icons.flag,
                                label: _dailyScheduled
                                    ? 'Challenge ON'
                                    : 'Challenge OFF',
                                isActive: _dailyScheduled,
                                onPressed: _toggleDailySchedule,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildScheduleButton(
                                icon: Icons.lightbulb,
                                label: _ecoTipScheduled
                                    ? 'Tips ON'
                                    : 'Tips OFF',
                                isActive: _ecoTipScheduled,
                                onPressed: _toggleEcoTipSchedule,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),

                      // Streak Reminders Section
                      _buildStreakRemindersSection(),
                    ],
                  ),
                ),

                // Notification List or Empty State
                _visible.isEmpty
                    ? SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.notifications_none,
                                size: 80,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No notifications yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Check back later for updates',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.all(16.0),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final n = _visible[index];
                            return _buildNotificationCard(n);
                          }, childCount: _visible.length),
                        ),
                      ),
              ],
            ),
    );
  }

  Widget _buildScheduleButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isActive ? kPrimaryGreen : Colors.grey,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isActive ? kPrimaryGreen : Colors.grey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(AppNotification n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: n.read ? Colors.transparent : kPrimaryGreen.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Dismissible(
        key: Key(n.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (_) => _remove(n.id),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showDetails(n),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: n.category.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      n.category.icon,
                      color: n.category.color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                n.title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: n.read
                                      ? FontWeight.w600
                                      : FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            if (!n.read)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: kPrimaryGreen,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          n.body,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: n.category.color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                n.category.displayName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: n.category.color,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _formatTime(n.time),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black38,
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
      ),
    );
  }

  /// Build streak reminders section with toggles
  Widget _buildStreakRemindersSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.local_fire_department,
                  color: Colors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Streak Reminders',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              if (_fcmInitialized)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: kPrimaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.cloud_done, size: 14, color: kPrimaryGreen),
                      SizedBox(width: 4),
                      Text(
                        'Cloud',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: kPrimaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Stay engaged like TikTok! Get reminders to maintain your streak',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(16),
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
              children: [
                _buildStreakReminderToggle(
                  icon: Icons.wb_sunny,
                  title: 'Morning Boost',
                  subtitle: '8:00 AM - Start your day right',
                  type: 'morning',
                  color: Colors.amber,
                ),
                const Divider(height: 16),
                _buildStreakReminderToggle(
                  icon: Icons.notifications_active,
                  title: 'Mid-Day Check',
                  subtitle: '12:00 PM - Keep momentum going',
                  type: 'midday',
                  color: Colors.blue,
                ),
                const Divider(height: 16),
                _buildStreakReminderToggle(
                  icon: Icons.warning_amber,
                  title: 'Evening Warning',
                  subtitle: '6:00 PM - Streak at risk alert',
                  type: 'evening',
                  color: Colors.orange,
                ),
                const Divider(height: 16),
                _buildStreakReminderToggle(
                  icon: Icons.alarm,
                  title: 'Last Chance',
                  subtitle: '10:00 PM - Final reminder',
                  type: 'lastchance',
                  color: Colors.red,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build individual streak reminder toggle
  Widget _buildStreakReminderToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required String type,
    required Color color,
  }) {
    final isEnabled = _streakNotifStatus[type] ?? false;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        Switch(
          value: isEnabled,
          activeThumbColor: kPrimaryGreen,
          onChanged: (value) => _toggleStreakNotification(type),
        ),
      ],
    );
  }
}
