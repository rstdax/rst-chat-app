import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/channel_model.dart';
import '../data/chat_repository.dart';
import '../../auth/data/auth_repository.dart';
import 'member_management_screen.dart';
import 'package:rst_chat_app/features/chat/widgets/message_bubble.dart';
import 'agora_call_screen.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/meet/v2.dart' as meet;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:intl/intl.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final ChannelModel channel;
  const ChatScreen({super.key, required this.channel});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _isUploading = false;
  bool _isLoadingMore = false; // ---> NEW: Tracks the button state <---

  final Set<String> _locallyMarkedAsRead = {};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentUserId = ref.read(authStateProvider).value?.uid;
      if (currentUserId != null) {
        ref
            .read(chatRepositoryProvider)
            .markChannelAsRead(widget.channel.id, currentUserId);
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _showMeetingOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Text(
                  'Start a Video Call',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.video_camera_back,
                    color: Colors.blue,
                  ),
                ),
                title: const Text(
                  'Google Meet',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Generate an external meeting link'),
                onTap: () {
                  Navigator.pop(context);
                  _createGoogleMeet();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.phone_in_talk, color: Colors.green),
                ),
                title: const Text(
                  'In-App Video Call',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Seamless native calling via Agora'),
                onTap: () {
                  Navigator.pop(context);
                  _createAgoraCall();
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _createGoogleMeet() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generating Google Meet link...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['https://www.googleapis.com/auth/meetings.space.created'],
      );

      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account == null) return;

      final httpClient = await googleSignIn.authenticatedClient();
      if (httpClient == null) {
        throw Exception('Failed to securely connect to Google.');
      }

      final meetApi = meet.MeetApi(httpClient);
      final space = await meetApi.spaces.create(meet.Space());

      final meetLink = space.meetingUri;

      if (meetLink != null) {
        final currentUserId = ref.read(authStateProvider).value?.uid;

        await FirebaseFirestore.instance
            .collection('channels')
            .doc(widget.channel.id)
            .collection('messages')
            .add({
              'text': 'Join my Google Meet',
              'type': 'meet_link',
              'meetUrl': meetLink,
              'senderId': currentUserId,
              'createdAt': FieldValue.serverTimestamp(),
              'isCallActive': true,
            });
      }
    } catch (e) {
      debugPrint('Google Meet creation failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not create meeting. Check your connection.'),
          ),
        );
      }
    }
  }

  void _createAgoraCall() async {
    final roomName = 'rst_call_${DateTime.now().millisecondsSinceEpoch}';
    final currentUserId = ref.read(authStateProvider).value?.uid;

    await FirebaseFirestore.instance
        .collection('channels')
        .doc(widget.channel.id)
        .collection('messages')
        .add({
          'text': 'In-App Video Call Started',
          'type': 'agora_call',
          'roomName': roomName,
          'senderId': currentUserId,
          'createdAt': FieldValue.serverTimestamp(),
          'isCallActive': true,
        });

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AgoraCallScreen(channelName: roomName, isOutgoing: true),
        ),
      );
    }
  }

  void _sendMessage() {
    final text = _messageController.text;
    if (text.trim().isEmpty) return;
    ref.read(chatRepositoryProvider).sendMessage(widget.channel.id, text);
    _messageController.clear();
  }

  Future<void> _pickAndSendImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (image == null) return;

    setState(() => _isUploading = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendImageMessage(widget.channel.id, File(image.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showCreatePollDialog() {
    final questionController = TextEditingController();
    final optionsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create a Poll'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: questionController,
              decoration: const InputDecoration(labelText: 'Poll Question'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: optionsController,
              decoration: const InputDecoration(
                labelText: 'Options (comma separated)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final question = questionController.text.trim();
              final optionsRaw = optionsController.text
                  .split(',')
                  .map((o) => o.trim())
                  .where((o) => o.isNotEmpty)
                  .toList();
              if (question.isNotEmpty && optionsRaw.length >= 2) {
                ref
                    .read(chatRepositoryProvider)
                    .sendPollMessage(widget.channel.id, question, optionsRaw);
                Navigator.pop(context);
              }
            },
            child: const Text('Post Poll'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authStateProvider).value?.uid;
    final messagesAsync = ref.watch(channelMessagesProvider(widget.channel.id));
    final typingUsersAsync = ref.watch(typingUsersProvider(widget.channel.id));
    final currentLimit = ref.watch(messageLimitProvider(widget.channel.id));

    // ---> NEW: Use valueOrNull to keep old messages on screen during reload <---
    final messages = messagesAsync.valueOrNull ?? [];

    // Turn off the local loading spinner once the network returns the new batch
    if (_isLoadingMore && messages.length >= currentLimit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isLoadingMore = false);
      });
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Text(widget.channel.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.channel.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.channel.type == 'group')
                    Text(
                      '${widget.channel.memberIds.length} members',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.video_call),
            onPressed: () => _showMeetingOptions(context),
          ),
          if (widget.channel.type == 'group')
            Consumer(
              builder: (context, ref, child) {
                final user = ref.watch(authStateProvider).value;
                final bool isAllowed =
                    user?.email == 'rstrohan1@gmail.com' ||
                    (widget.channel.adminIds.contains(user?.uid)) ||
                    (widget.channel.createdBy == user?.uid);

                if (isAllowed) {
                  return IconButton(
                    icon: const Icon(Icons.person_add_outlined),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            MemberManagementScreen(channel: widget.channel),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Builder(
              builder: (context) {
                // Show standard loading indicator ONLY if it's the very first time opening the chat
                if (messagesAsync.isLoading && messages.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (messages.isEmpty) {
                  return const Center(child: Text('No messages yet. Say hi!'));
                }

                // If we have fewer messages than our limit, we hit the end of the chat history
                final hasMore = messages.length >= currentLimit;

                return ListView.builder(
                  reverse: true,
                  itemCount: hasMore ? messages.length + 1 : messages.length,
                  itemBuilder: (context, index) {
                    // ---> NEW: Smart Load More Button <---
                    if (index == messages.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: _isLoadingMore
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    side: BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary.withOpacity(0.5),
                                    ),
                                    foregroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  onPressed: () {
                                    setState(() => _isLoadingMore = true);

                                    // Expand limit by 50 to trigger the background network request
                                    ref
                                            .read(
                                              messageLimitProvider(
                                                widget.channel.id,
                                              ).notifier,
                                            )
                                            .state +=
                                        50;

                                    // Failsafe: Turn spinner off after 2 seconds if no new messages existed
                                    Future.delayed(
                                      const Duration(seconds: 2),
                                      () {
                                        if (mounted && _isLoadingMore) {
                                          setState(
                                            () => _isLoadingMore = false,
                                          );
                                        }
                                      },
                                    );
                                  },
                                  icon: const Icon(Icons.history, size: 18),
                                  label: const Text('Load older messages'),
                                ),
                        ),
                      );
                    }

                    final msg = messages[index];
                    final isMe = msg.senderId == currentUserId;

                    if (!isMe && currentUserId != null) {
                      final hasRead = (msg.readBy ?? []).contains(
                        currentUserId,
                      );
                      if (!hasRead && !_locallyMarkedAsRead.contains(msg.id)) {
                        _locallyMarkedAsRead.add(msg.id);
                        Future.microtask(
                          () => ref
                              .read(chatRepositoryProvider)
                              .markMessageAsRead(widget.channel.id, msg.id),
                        );
                      }
                    }

                    if (msg.type == 'meet_link') {
                      return _buildMeetingCard(
                        context: context,
                        msg: msg,
                        currentUserId: currentUserId ?? '',
                        title: 'Google Meet',
                        icon: Icons.video_camera_back,
                        color: Colors.blue,
                        onJoin: () async {
                          final urlString =
                              msg.meetUrl ?? 'https://meet.google.com';
                          final url = Uri.parse(urlString);

                          try {
                            await launchUrl(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (e) {
                            debugPrint('Could not launch $urlString: $e');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Could not open Google Meet.'),
                                ),
                              );
                            }
                          }
                        },
                        onEnd: () {
                          ref
                              .read(chatRepositoryProvider)
                              .endCall(widget.channel.id, msg.id);
                        },
                      );
                    } else if (msg.type == 'agora_call') {
                      return _buildMeetingCard(
                        context: context,
                        msg: msg,
                        currentUserId: currentUserId ?? '',
                        title: 'Native Video Call',
                        icon: Icons.phone_in_talk,
                        color: Colors.green,
                        onJoin: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AgoraCallScreen(
                                channelName: msg.roomName ?? 'default_room',
                                isOutgoing: false,
                              ),
                            ),
                          );
                        },
                        onEnd: () {
                          ref
                              .read(chatRepositoryProvider)
                              .endCall(widget.channel.id, msg.id);
                        },
                      );
                    }

                    return MessageBubble(
                      message: msg,
                      isMe: isMe,
                      channelId: widget.channel.id,
                    );
                  },
                );
              },
            ),
          ),

          typingUsersAsync.when(
            data: (typingUsers) {
              if (typingUsers.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${typingUsers.join(", ")} ${typingUsers.length == 1 ? "is" : "are"} typing...',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          if (_isUploading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 12,
      ).copyWith(bottom: 24),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            color: Colors.grey.shade500,
            onPressed: _isUploading ? null : _pickAndSendImage,
          ),
          IconButton(
            icon: const Icon(Icons.poll_outlined),
            color: Colors.grey.shade500,
            onPressed: _showCreatePollDialog,
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              onChanged: (_) => ref
                  .read(chatRepositoryProvider)
                  .updateTypingStatus(widget.channel.id),
              decoration: InputDecoration(
                hintText: 'Message securely...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade500,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1E1E1E)
                    : Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: _sendMessage,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

Widget _buildMeetingCard({
  required BuildContext context,
  required dynamic msg,
  required String title,
  required IconData icon,
  required Color color,
  required String currentUserId,
  required VoidCallback onJoin,
  required VoidCallback onEnd,
}) {
  final bool isActive = msg.isCallActive ?? true;
  final bool isHost = msg.senderId == currentUserId;

  final DateTime? initTime = msg.createdAt;
  final String timeString = initTime != null
      ? DateFormat('h:mm a').format(initTime)
      : 'Unknown time';

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isActive
          ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5)
          : Colors.grey.withOpacity(0.1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isActive ? color.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
      ),
    ),
    child: Column(
      children: [
        Icon(
          isActive ? icon : Icons.call_end,
          size: 40,
          color: isActive ? color : Colors.grey,
        ),
        const SizedBox(height: 8),
        Text(
          isActive ? title : 'Call Ended',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: isActive
                ? Theme.of(context).colorScheme.onSurface
                : Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Initiated at $timeString',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),

        if (isActive) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
              ),
              onPressed: onJoin,
              child: const Text('Join Call'),
            ),
          ),
          if (isHost) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: onEnd,
                child: const Text('End Call for Everyone'),
              ),
            ),
          ],
        ],
      ],
    ),
  );
}
