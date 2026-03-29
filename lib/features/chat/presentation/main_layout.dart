import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/channel_repository.dart';
import '../../auth/data/auth_repository.dart';
import 'chat_screen.dart';
import '../../../core/theme/theme_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../auth/domain/app_user.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_settings/app_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // ---> ADDED: For time formatting

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

// --- NEW HELPER: DYNAMIC PASTEL BACKGROUND COLORS ---
Color _getAvatarBackgroundColor(String text) {
  if (text.isEmpty) return const Color(0xFFE0E0E0);

  // A beautiful palette of soft pastel colors mimicking the reference image
  final List<Color> colors = [
    const Color(0xFFFFE0B2), // Soft Orange
    const Color(0xFFB3E5FC), // Soft Light Blue
    const Color(0xFFD1C4E9), // Soft Purple
    const Color(0xFFFFCDD2), // Soft Pink/Red
    const Color(0xFFC8E6C9), // Soft Green
    const Color(0xFFFFF9C4), // Soft Yellow
    const Color(0xFFCFD8DC), // Soft Blue Grey
  ];

  // Consistently returns the same color for the same text/emoji
  return colors[text.hashCode.abs() % colors.length];
}

// Helper function to format timestamps like WhatsApp
String _formatLastMessageTime(DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  final difference = now.difference(time);

  if (difference.inDays == 0 && now.day == time.day) {
    final hour = time.hour > 12
        ? time.hour - 12
        : (time.hour == 0 ? 12 : time.hour);
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  } else if (difference.inDays == 1 ||
      (difference.inDays == 0 && now.day != time.day)) {
    return 'Yesterday';
  } else if (difference.inDays < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[time.weekday - 1];
  } else {
    return '${time.day}/${time.month}/${time.year.toString().substring(2)}';
  }
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  int _currentIndex = 0;
  // 1. ADD THE PAGE CONTROLLER
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Helper method for smooth sliding
  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic, // Smooth, modern easing
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      // 2. REPLACE INDEXEDSTACK WITH PAGEVIEW
      body: PageView(
        controller: _pageController,
        physics:
            const NeverScrollableScrollPhysics(), // Disables swipe-to-change so it only changes via taps
        children: const [
          AllChatsTab(),
          DirectMessagesTab(),
          MeetsTab(), // <--- NEW 3rd TAB
          ProfileSettingsTab(), // Now the 4th tab
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 8,
                ), // Slightly tighter to fit 4 items
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(
                        0.15,
                      ), // Adjusted for dynamic light/dark mode
                      blurRadius: 20,
                      spreadRadius: -4,
                      offset: const Offset(0, 12), // Pulled center for 4 items
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NavBarItem(
                      icon: Icons.chat_bubble_outline,
                      label: 'All',
                      isSelected: _currentIndex == 0,
                      onTap: () => _onTabTapped(0),
                    ),
                    const SizedBox(width: 4),
                    _NavBarItem(
                      icon: Icons.alternate_email,
                      label: 'DMs',
                      isSelected: _currentIndex == 1,
                      onTap: () => _onTabTapped(1),
                    ),
                    const SizedBox(width: 4),
                    // ---> NEW MEETS BUTTON <---
                    _NavBarItem(
                      icon: Icons.video_camera_front_outlined,
                      label: 'Meets',
                      isSelected: _currentIndex == 2,
                      onTap: () => _onTabTapped(2),
                    ),
                    const SizedBox(width: 4),
                    _NavBarItem(
                      icon: Icons.person_outline,
                      label: 'Me',
                      isSelected: _currentIndex == 3,
                      onTap: () => _onTabTapped(3),
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
}

// ==========================================
// NEW: CALL LOGS PROVIDER
// Fetches all messages across the entire app that are video calls
// ==========================================
final callLogsProvider = StreamProvider<List<dynamic>>((ref) {
  return FirebaseFirestore.instance
      .collectionGroup('messages')
      .where('type', whereIn: ['meet_link', 'agora_call'])
      .orderBy('createdAt', descending: true)
      .limit(50) // Keep it optimized
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data; // Returning raw map for easy parsing in the UI
        }).toList(),
      );
});

// ==========================================
// UPDATED TAB: MEETS & CALLS
// ==========================================
class MeetsTab extends ConsumerWidget {
  const MeetsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callLogsAsync = ref.watch(callLogsProvider);
    final currentUserId = ref.watch(authStateProvider).value?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Call History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: callLogsAsync.when(
        data: (logs) {
          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.video_call,
                    size: 80,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No recent calls',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a video meeting directly\nfrom any chat room.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              final isAgora = log['type'] == 'agora_call';
              final isActive = log['isCallActive'] ?? true;
              final isHost = log['senderId'] == currentUserId;

              final DateTime? time = (log['createdAt'] as Timestamp?)?.toDate();
              final timeString = time != null
                  ? DateFormat('MMM d, h:mm a').format(time)
                  : '';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isActive
                      ? (isAgora
                            ? Colors.green.withOpacity(0.1)
                            : Colors.blue.withOpacity(0.1))
                      : Colors.grey.withOpacity(0.1),
                  child: Icon(
                    isActive
                        ? (isAgora
                              ? Icons.phone_in_talk
                              : Icons.video_camera_back)
                        : Icons.call_end,
                    color: isActive
                        ? (isAgora ? Colors.green : Colors.blue)
                        : Colors.grey,
                  ),
                ),
                title: Text(
                  isAgora ? 'In-App Video Call' : 'Google Meet',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  isActive
                      ? 'Active Now • Initiated at $timeString'
                      : 'Ended • $timeString',
                  style: TextStyle(
                    color: isActive ? Colors.green : Colors.grey,
                  ),
                ),
                trailing: isActive && isHost
                    ? const Icon(Icons.arrow_forward_ios, size: 16)
                    : null,
                onTap: () {
                  // You can add logic here to jump into the specific chat channel later!
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              'Error loading call logs: $e\n\n(If this is your first time, check your console for the Firestore Index link!)',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// SHARED UI HELPER: CHANNEL TILE (Squarish Unread)
// ==========================================
Widget buildSharedChannelTile({
  required BuildContext context,
  required WidgetRef ref,
  required dynamic channel,
  required String? currentUserId,
}) {
  String displayTitle = channel.name;
  String? displayImage = channel.photoURL;

  bool hasUnread = false;
  if (currentUserId != null) {
    if (channel.lastMessageSenderId != null &&
        channel.lastMessageSenderId != currentUserId &&
        !channel.lastMessageReadBy.contains(currentUserId)) {
      hasUnread = true;
    }
  }

  if (channel.type == 'dm') {
    final names = channel.name.split(', ');
    final myName = ref.watch(authStateProvider).value?.displayName ?? "";

    if (names.length >= 2) {
      displayTitle =
          names[0].trim().toLowerCase() == myName.trim().toLowerCase()
          ? names[1]
          : names[0];
    }
  }

  // Determine what string to hash for the color
  String colorSeedText = channel.type == 'dm' ? displayTitle : channel.emoji;
  Color dynamicBgColor = _getAvatarBackgroundColor(colorSeedText);

  return ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),

    // ---> NEW SQUARISH AVATAR <---
    leading: Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: dynamicBgColor, // Automatically sets soft background
        borderRadius: BorderRadius.circular(14), // Rounded square look
        image: (displayImage != null && displayImage.isNotEmpty)
            ? DecorationImage(
                image: NetworkImage(displayImage),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: (displayImage == null || displayImage.isEmpty)
          ? Text(
              channel.type == 'dm'
                  ? displayTitle[0].toUpperCase()
                  : channel.emoji,
              style: TextStyle(
                fontSize: channel.type == 'dm' ? 20 : 26, // Larger if emoji
                fontWeight: FontWeight.bold,
                color: Colors.black87, // High contrast on pastel
              ),
            )
          : null,
    ),

    title: Text(
      displayTitle,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),

    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Text(
        channel.lastMessageText.isEmpty
            ? 'Tap to chat'
            : channel.lastMessageText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          // ---> CHANGED: Now matches your app's dynamic theme perfectly
          color: hasUnread
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade600,
          fontSize: 14,
          fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    ),

    trailing: Text(
      _formatLastMessageTime(channel.lastMessageAt),
      style: TextStyle(
        fontSize: 12,
        // ---> CHANGED: Now matches your app's dynamic theme perfectly
        color: hasUnread
            ? Theme.of(context).colorScheme.primary
            : Colors.grey.shade500,
        fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
      ),
    ),

    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ChatScreen(channel: channel)),
      );
    },
  );
}

// ==========================================
// TAB 1: ALL CHATS (Groups & DMs)
// ==========================================
class AllChatsTab extends ConsumerWidget {
  const AllChatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(userChannelsProvider);
    final currentUserId = ref.watch(authStateProvider).value?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'RST Workspace',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => showSearch(
              context: context,
              delegate: ChatSearchDelegate(
                ref: ref,
                currentUserId: currentUserId,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: channelsAsync.when(
        data: (channels) {
          final groups = channels.where((c) => c.type != 'dm').toList();
          final dms = channels.where((c) => c.type == 'dm').toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              if (groups.isNotEmpty)
                _buildSection(context, 'GROUPS', groups, ref, currentUserId),
              if (dms.isNotEmpty)
                _buildSection(
                  context,
                  'DIRECT MESSAGES',
                  dms,
                  ref,
                  currentUserId,
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List channels,
    WidgetRef ref,
    String? currentUserId,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 20, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
          ),
          ...channels.map(
            (c) => buildSharedChannelTile(
              context: context,
              ref: ref,
              channel: c,
              currentUserId: currentUserId,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ==========================================
// TAB 2: DIRECT MESSAGES TAB
// ==========================================
class DirectMessagesTab extends ConsumerWidget {
  const DirectMessagesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(userChannelsProvider);
    final currentUserId = ref.watch(authStateProvider).value?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Direct Messages',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: channelsAsync.when(
        data: (channels) {
          final dms = channels.where((c) => c.type == 'dm').toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              if (dms.isNotEmpty)
                Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    children: dms
                        .map(
                          (c) => buildSharedChannelTile(
                            context: context,
                            ref: ref,
                            channel: c,
                            currentUserId: currentUserId,
                          ),
                        )
                        .toList(),
                  ),
                )
              else
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40.0),
                    child: Text('No DMs found'),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

// ==========================================
// TAB 3: PROFILE SETTINGS
// ==========================================
class ProfileSettingsTab extends ConsumerWidget {
  const ProfileSettingsTab({super.key});

  void _openNotificationSettings() {
    AppSettings.openAppSettings(type: AppSettingsType.notification);
  }

  void _showAboutRSTChat(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'RST Chat',
      applicationVersion: '1.0.0+2',
      applicationIcon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.chat_bubble, color: Colors.white, size: 32),
      ),
      applicationLegalese:
          '© 2026 Royal Synergy Technology\nFounded by Jivan JD',
      children: [
        const SizedBox(height: 16),
        const Text(
          'A private, secure workspace designed for seamless communication and collaboration.',
          style: TextStyle(fontSize: 14),
        ),
      ],
    );
  }

  void _showSupportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Wrap(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 20, bottom: 8, top: 8),
                  child: Text(
                    'Contact Support',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.phone_outlined,
                    color: Colors.green,
                  ),
                  title: const Text('Call Us'),
                  subtitle: const Text('+91 7099552355'),
                  onTap: () async {
                    final Uri url = Uri.parse('tel:+917099552355');
                    if (await canLaunchUrl(url)) await launchUrl(url);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.email_outlined, color: Colors.blue),
                  title: const Text('Email Us'),
                  subtitle: const Text('rstrohan1@gmail.com'),
                  onTap: () async {
                    final Uri url = Uri.parse(
                      'mailto:rstrohan1@gmail.com?subject=RST Chat Support&body=Hi Jivan, I need help with...',
                    );
                    if (await canLaunchUrl(url)) await launchUrl(url);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final currentTheme = ref.watch(themeModeProvider);

    final displayName = user?.displayName ?? 'Jivan JD';
    final email = user?.email ?? '';
    final photoUrl = user?.photoURL;
    final isDarkMode = currentTheme == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),

              // --- 1. PROFILE CARD ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withOpacity(0.1),
                  ),
                ),
                child: Row(
                  children: [
                    // ---> UPDATED AVATAR SQUARISH <---
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: _getAvatarBackgroundColor(displayName),
                        borderRadius: BorderRadius.circular(18),
                        image: photoUrl != null
                            ? DecorationImage(
                                image: NetworkImage(photoUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: photoUrl == null
                          ? Text(
                              displayName.isNotEmpty
                                  ? displayName[0].toUpperCase()
                                  : 'R',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              _buildSectionHeader('Preferences'),
              _buildSettingsTile(
                context,
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                onTap: _openNotificationSettings,
              ),

              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4.0,
                  vertical: 2.0,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isDarkMode
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                title: const Text(
                  'Dark Mode',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                trailing: Switch(
                  value: isDarkMode,
                  onChanged: (value) {
                    ref.read(themeModeProvider.notifier).state = value
                        ? ThemeMode.dark
                        : ThemeMode.light;
                  },
                ),
              ),

              const SizedBox(height: 16),

              // ---> ACCENT COLOR PICKER <---
              const Padding(
                padding: EdgeInsets.only(left: 20.0, bottom: 12.0),
                child: Text(
                  'Accent Color',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  children:
                      [
                        const Color(0xFF0F766E), // Teal
                        const Color(0xFF2563EB), // Blue
                        const Color(0xFF9333EA), // Purple
                        const Color(0xFFEA580C), // Orange
                        const Color(0xFFE11D48), // Rose
                        const Color(0xFF475569), // Slate
                      ].map((color) {
                        final isSelected =
                            ref.watch(themeColorProvider) == color;
                        return GestureDetector(
                          onTap: () async {
                            // 1. Update app UI instantly
                            ref.read(themeColorProvider.notifier).state = color;

                            // 2. Save to Firestore
                            if (user != null) {
                              try {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(user.uid)
                                    .update({
                                      'themeColor': colorToHex(color),
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    });
                              } catch (e) {
                                debugPrint("Failed to save theme color: $e");
                              }
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6.0),
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                              boxShadow: [
                                if (isSelected)
                                  BoxShadow(
                                    color: color.withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                              ],
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                ),
              ),

              const SizedBox(height: 24),
              _buildSectionHeader('About'),
              _buildSettingsTile(
                context,
                icon: Icons.info_outline,
                title: 'About RST Chat',
                onTap: () => _showAboutRSTChat(context),
              ),
              _buildSettingsTile(
                context,
                icon: Icons.help_outline,
                title: 'Help & Support',
                onTap: () => _showSupportOptions(context),
              ),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  label: const Text(
                    'Log Out',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: Colors.redAccent.withOpacity(0.5),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, left: 4.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 4.0,
        vertical: 2.0,
      ),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Colors.grey,
      ),
      onTap: onTap,
    );
  }
}

// ==========================================
// NAV BAR ITEM UI
// ==========================================
class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 20 : 16,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Colors.grey.shade600,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==========================================
// SEARCH DELEGATE
// ==========================================
class ChatSearchDelegate extends SearchDelegate {
  final WidgetRef ref;
  final String? currentUserId;
  ChatSearchDelegate({required this.ref, required this.currentUserId});

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _buildGlobalResults();

  @override
  Widget buildSuggestions(BuildContext context) => _buildGlobalResults();

  Widget _buildGlobalResults() {
    if (query.trim().length < 2) {
      return const Center(
        child: Text('Type at least 2 characters to search...'),
      );
    }

    return FutureBuilder<List<dynamic>>(
      future: ref.read(channelRepositoryProvider).globalSearch(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final results = snapshot.data ?? [];

        if (results.isEmpty) {
          return const Center(child: Text('No users or groups found.'));
        }

        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final item = results[index];

            if (item is AppUser) {
              // ---> SQUARISH AVATAR IN SEARCH <---
              return ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _getAvatarBackgroundColor(item.displayName),
                    borderRadius: BorderRadius.circular(12),
                    image: item.photoURL != null
                        ? DecorationImage(
                            image: NetworkImage(item.photoURL!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: item.photoURL == null
                      ? Text(
                          item.displayName.isNotEmpty
                              ? item.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        )
                      : null,
                ),
                title: Text(item.displayName),
                subtitle: const Text('Start a direct message'),
                onTap: () async {
                  final channel = await ref
                      .read(channelRepositoryProvider)
                      .getOrCreateDM(item);
                  if (context.mounted) {
                    close(context, null);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(channel: channel),
                      ),
                    );
                  }
                },
              );
            } else {
              return buildSharedChannelTile(
                context: context,
                ref: ref,
                channel: item,
                currentUserId: currentUserId,
              );
            }
          },
        );
      },
    );
  }
}
